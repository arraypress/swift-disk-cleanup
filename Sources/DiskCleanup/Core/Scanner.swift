//
//  Scanner.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  One scan: every selected rule's detector, then every path measured in
//  parallel, then the protections, then one item per path (the earlier rule
//  wins an overlap), then the totals. Nothing here changes the disk.
//

import Foundation
import os

public enum Scanner {

    /// Scans per the options. Never throws: a place that cannot be read is
    /// reported as not visible, and a rule that cannot run says so in `notes`.
    public static func scan(catalogue: Catalogue, context: CleanupContext, options: ScanScope = ScanScope(),
                            progress: ((String) -> Void)? = nil) -> ScanReport {
        let started = Date()
        let selected = catalogue.rules.filter { options.categories.isEmpty || options.categories.contains($0.category) }
        let scanned = CleanupCategory.allCases.filter { options.categories.isEmpty || options.categories.contains($0) }

        let needsApps = selected.contains { [.installers, .leftovers, .groupContainers, .appLibraries].contains($0.detector) }
        let shared = Detectors.Shared(
            index: needsApps ? AppIndex.build(folders: context.applicationFolders) : AppIndex(apps: [:], unreadable: []),
            running: needsApps ? context.lookup.runningBundleIDs() : [],
            launchNames: needsApps ? Detectors.launchNames(context) : [],
            ownedPlaces: Detectors.ownedPlaces(catalogue, home: context.home.path)
        )

        // 1. Detect, in catalogue order.
        var found: [(rule: Rule, candidate: Candidate)] = []
        var visibility: [CleanupCategory: [Visibility]] = [:]
        var notVisible: [String] = []
        var notes: [String] = []
        var markerResults: [String: [Candidate]]?
        for rule in selected {
            progress?("looking: \(rule.id)")
            var result: DetectorResult
            switch rule.detector {
            case .paths: result = Detectors.paths(rule, context: context)
            case .marker:
                if markerResults == nil {
                    let markerRules = selected.filter { $0.detector == .marker }
                    let roots = (options.projectRoots ?? context.projectRoots).map(\.path)
                    let walk = MarkerWalk.find(rules: markerRules, roots: roots, depth: options.depth)
                    markerResults = walk.byRule
                    result = DetectorResult(candidates: [], roots: walk.roots, notes: [])
                } else {
                    result = DetectorResult()
                }
                result.candidates = markerResults?[rule.id] ?? []
            case .installers: result = Detectors.installers(rule, context: context, options: options, shared: shared, progress: progress)
            case .deviceSupport: result = Detectors.deviceSupport(rule, context: context)
            case .simulatorDevices: result = Detectors.simulatorDevices(rule, context: context)
            case .simulatorRuntimes: result = Detectors.simulatorRuntimes(rule, context: context)
            case .coreAIBuilds: result = Detectors.coreAIBuilds(rule, context: context)
            case .huggingFaceRepos: result = Detectors.huggingFaceRepos(rule, context: context)
            case .ollamaModels: result = Detectors.ollamaModels(rule, context: context)
            case .lmStudioModels: result = Detectors.lmStudioModels(rule, context: context)
            case .homebrew: result = Detectors.homebrew(rule, context: context)
            case .leftovers: result = Detectors.leftovers(rule, context: context, catalogue: catalogue, shared: shared)
            case .appLibraries: result = Detectors.appLibraries(rule, context: context, shared: shared)
            case .groupContainers: result = Detectors.groupContainers(rule, context: context, shared: shared)
            case .chatStores: result = Detectors.chatStores(rule, context: context)
            case .launchAgents: result = Detectors.launchAgents(rule, context: context)
            case .snapshots: result = Detectors.snapshots(rule, context: context)
            }
            visibility[rule.category, default: []] += result.roots.map(\.visibility)
            notVisible += result.roots.filter { $0.visibility == .notVisible }.map(\.path)
            notes += result.notes
            found += result.candidates.map { (rule, $0) }
        }

        // 2. Measure, in parallel. Walking is the slow part and folders are independent.
        progress?("measuring \(found.count) places")
        let measured = OSAllocatedUnfairLock(initialState: [Int: (Measurement?, String?)]())
        let jobs = found.enumerated().map { ($0.offset, $0.element.candidate) }
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let (offset, candidate) = jobs[index]
            let measurement = candidate.skipMeasure || candidate.isVirtual || !options.measure ? nil : Sizer.measure(candidate.path)
            let git = options.measure && candidate.checkGit && candidate.protected == nil ? GitCheck.protection(candidate.path) : nil
            measured.withLock { $0[offset] = (measurement, git) }
        }
        let results = measured.withLock { $0 }

        // 3. Items, with every protection that applies.
        var items: [Item] = []
        for (offset, entry) in found.enumerated() {
            let (rule, candidate) = entry
            let (measurement, git) = results[offset] ?? (nil, nil)
            let isFile = !candidate.isVirtual
            let newest = measurement?.newest ?? (isFile ? PathProbe.modified(candidate.path) : nil)
            var evidence = candidate.evidence
            if let dataless = measurement?.dataless, dataless > 0 { evidence["icloudPlaceholders"] = String(dataless) }
            if let unreadable = measurement?.unreadable, unreadable > 0 { evidence["unreadableFolders"] = String(unreadable) }
            let lifted = options.includeRecent && rule.regenerable
            let tier = candidate.tier ?? rule.tier
            // A report item is never cleaned, so it carries only what its
            // detector said (a system snapshot), not a "held" reason.
            let placeholders = measurement?.dataless ?? 0
            let protected = tier == .report ? candidate.protected : candidate.protected
                ?? (isFile ? PathSafety.reason(for: candidate.path, catalogue: catalogue, home: context.home.path) : nil)
                ?? (placeholders > 0 ? "holds \(placeholders) iCloud placeholder(s): removing it would remove them from iCloud too" : nil)
                ?? git
                ?? (lifted ? nil : Ages.tooYoung(newest, minDays: rule.minAgeDays, now: context.now))
            let bytes = measurement?.bytes ?? candidate.bytes
            let identity: FileIdentity? = measurement.flatMap { m in m.visibility == .absent ? nil : Sizer.identity(candidate.path, bytes: m.bytes) }
            items.append(Item(
                id: ItemID.make(rule: rule.id, path: candidate.path),
                rule: rule.id, category: rule.category, path: candidate.path,
                bytes: measurement?.visibility == .notVisible ? nil : bytes,
                tier: tier, removal: rule.removal, regenerable: rule.regenerable,
                owner: candidate.evidence["tool"] ?? rule.owner, newest: newest,
                visibility: measurement?.visibility ?? .visible, protected: protected,
                evidence: evidence, note: rule.note, identity: identity, byIDOnly: candidate.byIDOnly,
                apparentBytes: measurement?.visibility == .notVisible ? nil : measurement?.apparentBytes
            ))
            if measurement?.visibility == .notVisible || measurement?.visibility == .partial {
                notVisible.append(candidate.path)
            }
        }

        // 4. One item per path.
        let kept = Claims.resolve(items).kept

        return ScanReport(
            categories: Totals.categories(kept, visibility: visibility, scanned: scanned),
            items: kept,
            notVisible: Array(Set(notVisible)).sorted(),
            notes: notes,
            seconds: Date().timeIntervalSince(started)
        )
    }
}
