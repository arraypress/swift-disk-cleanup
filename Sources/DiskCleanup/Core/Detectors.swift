//
//  Detectors.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Each detector turns a rule's places into candidates. Plain rules need only
//  their paths expanded; the rest read something first — simctl's device
//  list, an installer's Info.plist, Core AI's build folders.
//

import Foundation

enum Detectors {

    /// What the detectors share: the app index and the launch jobs, built once.
    struct Shared: Sendable {
        let index: AppIndex
        let running: Set<String>
        /// Launch job labels and plist names, lower-cased.
        let launchNames: Set<String>
        let ownedPlaces: [String]
    }

    // MARK: Paths

    static func paths(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        for place in places(rule, context: context) {
            let expansion = PathProbe.expand(place)
            result.roots += expansion.roots
            for path in expansion.paths {
                var candidate = Candidate(path: path)
                let name = PathText.lastComponent(path)
                if let pattern = rule.protect.first(where: { Glob.matches($0, name) }) {
                    candidate.protected = "kept by this rule (\(pattern))"
                }
                result.candidates.append(candidate)
            }
        }
        return result
    }

    /// A rule's paths and globs with the home filled in, and the environment's
    /// overrides for caches that can move (real homes only).
    static func places(_ rule: Rule, context: CleanupContext) -> [String] {
        let root = context.root.path == "/" ? "" : context.root.path
        var places = (rule.paths + rule.globs).map { $0.hasPrefix("/") ? root + $0 : PathText.expand($0, home: context.home.path) }
        if !context.isFixture {
            let overrides: [String: String] = ["uv-cache": "UV_CACHE_DIR", "hf-hub": "HF_HUB_CACHE"]
            if let key = overrides[rule.id], let value = context.environment[key], value.hasPrefix("/") {
                places = [value]
            } else if rule.id == "hf-hub", let value = context.environment["HF_HOME"], value.hasPrefix("/") {
                places = [value + "/hub"]
            }
        }
        return places
    }

    // MARK: Device support

    static func deviceSupport(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = paths(rule, context: context)
        let byPlatform = Dictionary(grouping: result.candidates.indices) { PathText.parent(result.candidates[$0].path) }
        for (_, indices) in byPlatform {
            let names = indices.map { PathText.lastComponent(result.candidates[$0].path) }
            let kept = DeviceSupportNames.kept(names, keep: rule.keepNewest ?? 1)
            for index in indices {
                let name = PathText.lastComponent(result.candidates[index].path)
                if let version = DeviceSupportNames.version(name) {
                    result.candidates[index].evidence["version"] = version.version
                    result.candidates[index].evidence["build"] = version.build ?? ""
                }
                result.candidates[index].evidence["platform"] = PathText.lastComponent(PathText.parent(result.candidates[index].path))
                if kept.contains(name) {
                    result.candidates[index].protected = "the newest build for this device model, kept"
                }
            }
        }
        return result
    }

    // MARK: Chat stores

    /// Chat stores as found, with WhatsApp's unlisted media as evidence and a
    /// note. Report only: Group Containers are never removed from, so the
    /// note says where it can be cleared.
    static func chatStores(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = paths(rule, context: context)
        for index in result.candidates.indices where result.candidates[index].path.hasSuffix(".net.whatsapp.WhatsApp.shared") {
            switch ChatMedia.whatsAppUnlisted(container: result.candidates[index].path) {
            case .success(let unlisted):
                result.candidates[index].evidence["listedMedia"] = String(unlisted.listed)
                result.candidates[index].evidence["unlistedMediaFiles"] = String(unlisted.files)
                result.candidates[index].evidence["unlistedMediaBytes"] = String(unlisted.bytes)
                if unlisted.files > 0 {
                    let size = ByteCountFormatter.string(fromByteCount: unlisted.bytes, countStyle: .file)
                    result.notes.append("WhatsApp: \(unlisted.files) media file(s) (\(size) of their own) in Message/Media are not in its database — a deleted chat's media or a download that looped. Clear them in WhatsApp's storage settings, or quit WhatsApp and remove them by hand.")
                }
            case .failure(let reason):
                result.candidates[index].evidence["unlistedMedia"] = "not checked: \(reason.text)"
            }
        }
        return result
    }

    // MARK: Simulators

    static func simulatorDevices(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        guard let xcrun = CommandLocator.find("xcrun", in: context) else {
            result.roots.append(("xcrun", .absent))
            return result
        }
        guard let output = CommandRunner.run(xcrun, ["simctl", "list", "devices", "-j"], timeout: 90), output.succeeded,
              let devices = SimctlJSON.devices(output.stdout) else {
            result.notes.append("simctl did not list devices")
            result.roots.append(("simctl", .absent))
            return result
        }
        let fallback = context.home.path + "/Library/Developer/CoreSimulator/Devices"
        result.roots.append((fallback, PathProbe.visibility(fallback)))
        for device in devices {
            let path = device.folder ?? fallback + "/" + device.udid
            guard PathProbe.exists(path) else { continue }
            var candidate = Candidate(path: path, evidence: [
                "udid": device.udid, "name": device.name, "runtime": device.runtime,
                "state": device.state ?? "", "available": device.isAvailable ? "yes" : "no",
            ])
            if device.isAvailable { candidate.tier = .report }
            result.candidates.append(candidate)
        }
        return result
    }

    static func simulatorRuntimes(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        guard let xcrun = CommandLocator.find("xcrun", in: context) else {
            result.roots.append(("xcrun", .absent))
            return result
        }
        guard let output = CommandRunner.run(xcrun, ["simctl", "runtime", "list", "-j"], timeout: 90), output.succeeded,
              let runtimes = SimctlJSON.runtimes(output.stdout) else {
            result.notes.append("simctl did not list runtimes")
            result.roots.append(("simctl", .absent))
            return result
        }
        result.roots.append(("simctl runtime list", .visible))
        let shared = SimctlJSON.shared(runtimes)
        for runtime in runtimes {
            var candidate = Candidate(path: "simulator-runtime:\(runtime.identifier)", evidence: [
                "identifier": runtime.identifier, "runtime": runtime.runtimeIdentifier,
                "version": runtime.version ?? "", "build": runtime.build ?? "", "state": runtime.state ?? "",
            ])
            candidate.bytes = runtime.bytes
            candidate.skipMeasure = true
            candidate.isVirtual = true
            if !shared.contains(runtime.identifier) {
                candidate.tier = .report
            } else if !runtime.deletable {
                candidate.protected = "simctl says it cannot be deleted"
            } else {
                candidate.byIDOnly = true
                candidate.evidence["sharedWith"] = runtimes
                    .filter { $0.runtimeIdentifier == runtime.runtimeIdentifier && $0.identifier != runtime.identifier }
                    .map { "\($0.build ?? $0.identifier)" }.joined(separator: ", ")
            }
            result.candidates.append(candidate)
        }
        return result
    }

    // MARK: Package managers

    static func homebrew(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        guard let place = places(rule, context: context).first else { return result }
        guard let brew = CommandLocator.find("brew", in: context) else {
            result.roots.append((place, .absent))
            return result
        }
        var environment = context.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        guard let output = CommandRunner.run(brew, ["cleanup", "-n"], timeout: 180, environment: environment),
              output.succeeded, let bytes = BrewOutput.wouldFree(output.text) else {
            result.notes.append("brew cleanup -n did not answer")
            result.roots.append((place, .absent))
            return result
        }
        result.roots.append((place, .visible))
        var candidate = Candidate(path: place, evidence: [
            "wouldRemove": String(output.text.components(separatedBy: "Would remove").count - 1),
        ])
        candidate.bytes = bytes
        candidate.skipMeasure = true
        if bytes > 0 { result.candidates.append(candidate) }
        return result
    }

    // MARK: ML caches

    static func coreAIBuilds(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        let current = context.osBuild
        for root in places(rule, context: context) {
            let listing = PathProbe.list(root)
            result.roots.append((root, listing.visibility))
            for name in listing.names where !name.hasPrefix(".") {
                let path = root + "/" + name
                guard PathProbe.isDirectory(path) else { continue }
                if OSBuild.isBuild(name) {
                    result.candidates += buildFolder(path, build: name, current: current)
                } else {
                    // `sync`, `tmp`: build folders one level down.
                    for inner in PathProbe.list(path).names where !inner.hasPrefix(".") {
                        let innerPath = path + "/" + inner
                        guard PathProbe.isDirectory(innerPath) else { continue }
                        if OSBuild.isBuild(inner), inner != current, current != nil {
                            result.candidates.append(Candidate(path: innerPath, evidence: ["build": inner, "current": current ?? ""]))
                        } else {
                            result.candidates.append(Candidate(path: innerPath, evidence: ["build": inner, "current": current ?? ""], tier: .review))
                        }
                    }
                }
            }
        }
        return result
    }

    /// A build's folder: whole and safe when it is not this Mac's build;
    /// split per tool and review when it is.
    private static func buildFolder(_ path: String, build: String, current: String?) -> [Candidate] {
        guard let current, build == current else {
            return [Candidate(path: path, evidence: ["build": build, "current": current ?? "unknown"],
                              tier: current == nil ? .review : nil)]
        }
        return PathProbe.list(path).names.filter { !$0.hasPrefix(".") }.map { tool in
            Candidate(path: path + "/" + tool, evidence: ["build": build, "current": current, "tool": tool], tier: .review)
        }
    }

    static func huggingFaceRepos(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        for root in places(rule, context: context) {
            let listing = PathProbe.list(root)
            result.roots.append((root, listing.visibility))
            for name in listing.names {
                guard let repo = ModelStoreNames.huggingFace(name) else { continue }
                let path = root + "/" + name
                let snapshots = PathProbe.list(path + "/snapshots").names.count
                result.candidates.append(Candidate(path: path, evidence: [
                    "repo": repo.repo, "kind": repo.kind, "revisions": String(snapshots),
                ]))
            }
        }
        return result
    }

    static func ollamaModels(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        for root in places(rule, context: context) {
            let manifests = root + "/manifests"
            result.roots.append((root, PathProbe.visibility(root)))
            for path in files(under: manifests, depth: 5) {
                guard let data = PathProbe.read(path, limit: 1 << 20), let bytes = ModelStoreNames.ollamaBytes(data),
                      let model = ModelStoreNames.ollamaModel(path, manifests: manifests) else { continue }
                var candidate = Candidate(path: path, evidence: ["model": model])
                candidate.bytes = bytes
                candidate.skipMeasure = true
                result.candidates.append(candidate)
            }
        }
        return result
    }

    static func lmStudioModels(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        for root in places(rule, context: context) {
            let listing = PathProbe.list(root)
            result.roots.append((root, listing.visibility))
            for publisher in listing.names where !publisher.hasPrefix(".") {
                for model in PathProbe.list(root + "/" + publisher).names where !model.hasPrefix(".") {
                    let path = root + "/" + publisher + "/" + model
                    if PathProbe.isDirectory(path) {
                        result.candidates.append(Candidate(path: path, evidence: ["model": publisher + "/" + model]))
                    }
                }
            }
        }
        return result
    }

    static func files(under folder: String, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        var found: [String] = []
        for name in PathProbe.list(folder).names where !name.hasPrefix(".") {
            let path = folder + "/" + name
            if PathProbe.isDirectory(path) { found += files(under: path, depth: depth - 1) } else if PathProbe.isFile(path) { found.append(path) }
        }
        return found
    }

    // MARK: Snapshots

    static func snapshots(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = DetectorResult()
        guard let tmutil = CommandLocator.find("tmutil", in: context),
              let output = CommandRunner.run(tmutil, ["listlocalsnapshots", "/"], timeout: 60), output.succeeded else {
            result.roots.append(("tmutil", .absent))
            return result
        }
        result.roots.append(("tmutil listlocalsnapshots /", .visible))
        for name in TmutilText.snapshots(output.text) {
            var candidate = Candidate(path: "snapshot:\(name)", evidence: ["snapshot": name])
            candidate.skipMeasure = true
            candidate.isVirtual = true
            if TmutilText.isSystemOwned(name) { candidate.protected = "belongs to the system (OS update)" }
            result.candidates.append(candidate)
        }
        return result
    }

    // MARK: Installers

    static func installers(_ rule: Rule, context: CleanupContext, options: ScanScope, shared: Shared,
                           progress: ((String) -> Void)?) -> DetectorResult {
        var result = DetectorResult()
        var found: [String] = []
        for folder in (options.installerFolders ?? context.installerFolders).map(\.path) {
            let visibility = PathProbe.visibility(folder)
            result.roots.append((folder, visibility))
            guard visibility == .visible else { continue }
            found += installerPaths(in: folder, depth: 2)
        }
        // Leftover macOS installers sit in the app folders.
        for folder in context.applicationFolders.map(\.path) where !folder.hasSuffix("Caskroom") {
            found += PathProbe.list(folder).names
                .filter { $0.lowercased().hasPrefix("install macos") && $0.hasSuffix(".app") }
                .map { folder + "/" + $0 }
        }
        for path in found {
            progress?("reading \(PathText.lastComponent(path))")
            guard let info = InstallerReader.inspect(path, context: context, index: shared.index) else { continue }
            var candidate = Candidate(path: path, evidence: evidence(of: info))
            if info.kind == .xip { candidate.tier = .review }
            if info.verdict != .dead { candidate.protected = "\(info.verdict.rawValue): \(info.reason)" }
            result.candidates.append(candidate)
        }
        return result
    }

    static func installerPaths(in folder: String, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        var found: [String] = []
        for name in PathProbe.list(folder).names where !name.hasPrefix(".") {
            let path = folder + "/" + name
            if InstallerReader.kind(of: path) != nil, !Sizer.isDataless(path) {
                found.append(path)
            } else if PathProbe.isDirectory(path), !name.hasSuffix(".app"), !Sizer.isDataless(path) {
                found += installerPaths(in: path, depth: depth - 1)
            }
        }
        return found
    }

    static func evidence(of info: InstallerInfo) -> [String: String] {
        var evidence: [String: String] = ["kind": info.kind.rawValue, "verdict": info.verdict.rawValue, "reason": info.reason]
        evidence["bundleID"] = info.bundleID
        evidence["name"] = info.name
        evidence["version"] = info.version
        evidence["build"] = info.build
        evidence["installedVersion"] = info.installedVersion
        evidence["installedPath"] = info.installedPath
        if !info.packageIDs.isEmpty { evidence["packages"] = info.packageIDs.joined(separator: ", ") }
        return evidence
    }

    // MARK: Leftovers

    static func leftovers(_ rule: Rule, context: CleanupContext, catalogue: Catalogue, shared: Shared) -> DetectorResult {
        var result = paths(rule, context: context)
        let candidates = result.candidates
        result.candidates = []
        guard shared.index.unreadable.isEmpty else {
            result.notes.append("\(rule.id): not judged — \(shared.index.unreadable.count) app(s) have an unreadable Info.plist, and a leftover is only called when every app answered")
            return result
        }
        let known = shared.index.knownIDs
        var unanswered = 0
        for candidate in candidates {
            let path = candidate.path
            let name = PathText.lastComponent(path)
            let owner: String?
            if rule.id == "leftover-containers" {
                owner = PathProbe.read(path + "/.com.apple.containermanagerd.metadata.plist").flatMap(PlistValues.containerOwner)
            } else if name.hasSuffix(".savedState") {
                owner = String(name.dropLast(".savedState".count))
            } else {
                owner = name
            }
            guard let id = owner, BundleIDs.looksLikeBundleID(id), !BundleIDs.isApple(id) else { continue }
            guard PathSafety.reason(for: path, catalogue: catalogue, home: context.home.path) == nil else { continue }
            guard !shared.ownedPlaces.contains(where: { owned in
                Glob.hasWildcard(owned) ? Glob.matchesPath(owned, path) : PathText.overlaps(path, owned)
            }) else { continue }
            guard !BundleIDs.isRelated(id, to: known.ids, vendors: known.vendors),
                  !BundleIDs.isRelated(id, to: shared.running, vendors: Set(shared.running.map(BundleIDs.vendor))),
                  !shared.launchNames.contains(where: { $0.contains(id.lowercased()) }) else { continue }
            switch context.lookup.launchServices(id) {
            case .installed: continue
            case .noAnswer: unanswered += 1; continue
            case .notInstalled: break
            }
            switch context.lookup.spotlight(id) {
            case .installed: continue
            case .noAnswer: unanswered += 1; continue
            case .notInstalled: break
            }
            result.candidates.append(Candidate(path: path, evidence: [
                "bundleID": id,
                "checked": "app folders, running apps, launch jobs, LaunchServices, Spotlight: none",
            ]))
        }
        if unanswered > 0 {
            result.notes.append("\(rule.id): \(unanswered) left alone because LaunchServices or Spotlight did not answer")
        }
        return result
    }

    /// An app's library outside the home folder, kept while any of `apps` is
    /// installed. The same checks as a leftover — app folders, running apps,
    /// LaunchServices, Spotlight — but an Apple id matches only exactly
    /// (some Apple app is always installed), and a third party's matches its
    /// whole vendor. No answer, or an unreadable app, keeps it.
    static func appLibraries(_ rule: Rule, context: CleanupContext, shared: Shared) -> DetectorResult {
        var result = paths(rule, context: context)
        guard !result.candidates.isEmpty else { return result }
        guard shared.index.unreadable.isEmpty else {
            result.notes.append("\(rule.id): not judged — \(shared.index.unreadable.count) app(s) have an unreadable Info.plist")
            result.candidates = []
            return result
        }
        let known = shared.index.knownIDs
        let running = Set(shared.running.map { $0.lowercased() })
        func installed(_ id: String) -> Bool? {
            let present = BundleIDs.isApple(id)
                ? known.ids.contains(id.lowercased()) || running.contains(id.lowercased())
                : BundleIDs.isRelated(id, to: known.ids, vendors: known.vendors)
                    || BundleIDs.isRelated(id, to: running, vendors: Set(running.map(BundleIDs.vendor)))
            if present { return true }
            for answer in [context.lookup.launchServices(id), context.lookup.spotlight(id)] {
                switch answer {
                case .installed: return true
                case .noAnswer: return nil
                case .notInstalled: continue
                }
            }
            return false
        }
        var answers: [Bool?] = []
        for id in rule.apps {
            let answer = installed(id)
            answers.append(answer)
            if answer != false { break }
        }
        guard answers.allSatisfy({ $0 == false }) else {
            if answers.contains(where: { $0 == nil }) {
                result.notes.append("\(rule.id): left alone because LaunchServices or Spotlight did not answer")
            }
            result.candidates = []
            return result
        }
        for index in result.candidates.indices {
            result.candidates[index].evidence["apps"] = rule.apps.joined(separator: ", ")
            result.candidates[index].evidence["checked"] = "app folders, running apps, LaunchServices, Spotlight: none installed"
        }
        return result
    }

    static func groupContainers(_ rule: Rule, context: CleanupContext, shared: Shared) -> DetectorResult {
        var result = paths(rule, context: context)
        let known = shared.index.knownIDs
        result.candidates = result.candidates.compactMap { candidate in
            let name = PathText.lastComponent(candidate.path)
            let owner = PathProbe.read(candidate.path + "/.com.apple.containermanagerd.metadata.plist")
                .flatMap(PlistValues.containerOwner) ?? name
            let base = BundleIDs.groupBase(owner)
            guard BundleIDs.looksLikeBundleID(base) || base.split(separator: ".").count == 2 else { return nil }
            guard !BundleIDs.isApple(base), !base.lowercased().hasPrefix("apple."),
                  !BundleIDs.isRelated(base, to: known.ids, vendors: known.vendors),
                  !BundleIDs.isRelated(base, to: shared.running, vendors: Set(shared.running.map(BundleIDs.vendor))) else { return nil }
            return Candidate(path: candidate.path, evidence: ["group": owner, "checked": "no installed or running app from this vendor"])
        }
        return result
    }

    static func launchAgents(_ rule: Rule, context: CleanupContext) -> DetectorResult {
        var result = paths(rule, context: context)
        result.candidates = result.candidates.compactMap { candidate in
            guard let data = PathProbe.read(candidate.path, limit: 1 << 20), let job = PlistValues.launchJob(data),
                  let program = job.program, program.hasPrefix("/"), !PathProbe.exists(program) else { return nil }
            return Candidate(path: candidate.path, evidence: ["label": job.label ?? "", "program": program, "programExists": "no"])
        }
        return result
    }

    /// Launch job labels and plist names in the context's launch folders.
    static func launchNames(_ context: CleanupContext) -> Set<String> {
        var names = Set<String>()
        for folder in context.launchFolders.map(\.path) {
            for name in PathProbe.list(folder).names where name.hasSuffix(".plist") {
                names.insert(name.lowercased())
                if let data = PathProbe.read(folder + "/" + name, limit: 1 << 20), let label = PlistValues.launchJob(data)?.label {
                    names.insert(label.lowercased())
                }
            }
        }
        return names
    }

    /// Every place a rule with a named owner covers: a cache a tool owns is
    /// never an orphan, even when that tool has no app.
    static func ownedPlaces(_ catalogue: Catalogue, home: String) -> [String] {
        catalogue.rules.filter { $0.owner != nil && $0.detector != .marker }
            .flatMap { ($0.paths + $0.globs).map { PathText.expand($0, home: home) } }
    }
}
