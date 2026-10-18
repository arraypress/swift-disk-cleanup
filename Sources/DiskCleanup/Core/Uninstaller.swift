//
//  Uninstaller.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Everything one app — or one vendor's apps — left on a Mac, found from
//  what it is rather than what it is called, and installed or long gone:
//
//  1. who: bundle id, team id, names and vendor, from the .app while it is
//     here, and the installer receipts that match — by exact id, the bundle
//     id's prefix or the vendor's (`com.apple` is never a vendor);
//  2. exact: what a receipt owns (the deepest paths it owns whole, never a
//     shared parent like Library/Application Support/Avid), the app, the
//     ~/Library places named by its bundle id, its launch jobs and helpers;
//  3. likely: group containers of its team or vendor, and audio plug-ins
//     whose bundle id has the vendor's prefix;
//  4. review: folders and dotfiles whose name holds its name or the
//     vendor's, and anything another installed app also uses.
//
//  No symlink is followed out of where it matched; nothing under /System,
//  no Apple app in /System/Applications and nothing the catalogue protects
//  (bar an app's own plist and group container) is ever offered.
//

import Darwin
import Foundation

public enum Uninstaller {

    /// Protected places whose contents an uninstall may take, item by item.
    /// The two system folders are root's: what is in them only ever goes in
    /// the sudo line a person runs, never by diskmaid's hand.
    public static let allowedInside = ["~/Library/Preferences", "~/Library/Group Containers", "~/Library/LaunchAgents",
                                       "/Library/LaunchAgents", "/Library/LaunchDaemons"]

    /// Evidence tiers, strongest first.
    enum Match: String, Comparable {
        case exact, likely, review
        static func < (a: Match, b: Match) -> Bool { a.order < b.order }
        var order: Int { self == .exact ? 0 : self == .likely ? 1 : 2 }
    }

    /// What uninstalling `target` would take. Nothing is changed.
    public static func plan(_ target: String, catalogue: Catalogue, context: CleanupContext) throws(DiskCleanupError) -> UninstallPlan {
        var search = Search(context: context, catalogue: catalogue)
        try search.resolve(target)
        search.collect()
        return search.finish()
    }

    /// The plan's items to take: exact and likely ones, review ones when
    /// asked or named, and named ones that stay with why.
    public static func select(_ plan: UninstallPlan, ids: Set<String>, includeReview: Bool, now: Date = Date())
        -> (take: [Item], held: [(Item, String)]) {
        let pick = Selection.pick(plan.items, categories: [.leftovers], ids: ids,
                                  includeReview: includeReview, olderThanDays: nil, now: now)
        return (pick.take, pick.held.map { ($0.0, $0.1) })
    }

    /// The one line a person runs for the part diskmaid does not do as
    /// itself: root-owned paths, system launch jobs, and the receipts whose
    /// every path is being taken. `nil` when there is none.
    public static func byHand(_ taking: [Item], plan: UninstallPlan) -> String? {
        let ids = Set(taking.map(\.id))
        let receipts = plan.identity.receipts.filter { receipt in
            plan.items.filter { $0.evidence["receipt"] == receipt }.allSatisfy { ids.contains($0.id) }
        }
        return UninstallMatch.byHand(
            paths: taking.filter { $0.removal == .sudo }.map(\.path),
            systemJobs: taking.compactMap { $0.evidence["launchDomain"] == "system" ? $0.evidence["launchLabel"] : nil },
            receipts: receipts
        )
    }

    /// Takes `items`: refuses while the app runs unless `quit` (then asks it
    /// to quit), unloads its own launch agents, and moves what this user owns
    /// to the Trash, journalled for undo. Root-owned items are skipped with
    /// the sudo command; `byHand` gives the whole line.
    public static func remove(_ items: [Item], plan: UninstallPlan, quit: Bool, catalogue: Catalogue, context: CleanupContext,
                              batch: String = Remover.newBatchID(),
                              progress: ((Item) -> Void)? = nil) throws(DiskCleanupError) -> [RemovalOutcome] {
        var running = stillRunning(plan, context: context)
        if !running.isEmpty {
            guard quit else { throw .appRunning(running) }
            for id in running { _ = context.records.quit(id) }
            running = stillRunning(plan, context: context)
            guard running.isEmpty else { throw .appRunning(running) }
        }
        for item in items where item.evidence["launchDomain"] == "gui" {
            if let label = item.evidence["launchLabel"] { _ = context.records.bootout(label: label) }
        }
        return Remover.remove(items, catalogue: catalogue, context: context, batch: batch, allowing: allowedInside, progress: progress)
    }

    static func stillRunning(_ plan: UninstallPlan, context: CleanupContext) -> [String] {
        let running = context.lookup.runningBundleIDs()
        return plan.identity.bundleIDs.filter { running.contains($0.lowercased()) }
    }

    /// Whether this user can move `path` to the Trash: they own it and may
    /// write the folder it is in. Otherwise only root can remove it.
    static func needsRoot(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_uid != getuid() || access(PathText.parent(path), W_OK) != 0
    }

    /// Whether `path` is where its name says: no folder on the way to it is a
    /// symlink to somewhere else.
    static func staysPut(_ path: String) -> Bool {
        let parent = PathText.parent(path)
        guard let resolved = realpath(parent, nil) else { return false }
        defer { free(resolved) }
        return PathText.normalised(String(cString: resolved)) == PathText.normalised(parent)
    }

    // MARK: The search

    struct Found {
        var match: Match
        var why: String
        var evidence: [String: String] = [:]
    }

    struct Search {
        let context: CleanupContext
        let catalogue: Catalogue
        var identity = UninstallIdentity(input: "")
        var index = AppIndex(apps: [:], unreadable: [])
        var receipts: [PackageReceipt] = []
        var found: [String: Found] = [:]
        var notes: [String] = []

        init(context: CleanupContext, catalogue: Catalogue) {
            self.context = context
            self.catalogue = catalogue
        }

        var home: String { context.home.path }
        var root: String { context.root.path == "/" ? "" : context.root.path }
        var bundleIDs: [String] { identity.bundleIDs.map { $0.lowercased() } }
        var tokens: [String] { UninstallMatch.tokens(names: identity.names, vendor: identity.vendor) }

        /// Installed apps that are not being uninstalled.
        var others: [InstalledApp] {
            index.apps.values.flatMap { $0 }.filter { app in
                !bundleIDs.contains(app.bundleID.lowercased()) && !identity.apps.contains(app.path)
            }
        }

        // MARK: 1. Who

        mutating func resolve(_ target: String) throws(DiskCleanupError) {
            identity = UninstallIdentity(input: target)
            index = AppIndex.build(folders: context.applicationFolders)
            let lowered = target.lowercased()
            let parts = target.split(separator: ".", omittingEmptySubsequences: false)

            if target.contains("/") {
                let path = PathText.normalised(PathText.expand(target, home: home))
                guard let app = AppIndex.read(appAt: path) else { throw .refusedTarget("\(target) is not an app bundle") }
                try adopt(app)
            } else if UninstallMatch.isTeamID(target) {
                identity.teamIDs = [target]
                for app in index.apps.values.flatMap({ $0 }) where !BundleIDs.isApple(app.bundleID)
                    && context.records.teamID(appAt: app.path) == target {
                    try adopt(app)
                }
                let vendors = Set(identity.bundleIDs.map(BundleIDs.vendor))
                if vendors.count == 1 { identity.vendor = vendors.first }
            } else if parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), BundleIDs.looksLikeBundleID(target + ".x") {
                guard !BundleIDs.isApple(lowered + ".") else {
                    throw .refusedTarget("com.apple is not one vendor: name the app's bundle id, like com.apple.garageband10")
                }
                identity.vendor = lowered
                for app in index.apps.values.flatMap({ $0 }) where app.bundleID.lowercased().hasPrefix(lowered + ".") {
                    try adopt(app)
                }
            } else if BundleIDs.looksLikeBundleID(target) {
                let apps = installed(target)
                if apps.isEmpty {
                    identity.bundleIDs = [target]
                    identity.names = [Search.nameFromID(target)]
                } else {
                    for app in apps { try adopt(app) }
                }
                if !BundleIDs.isApple(target) { identity.vendor = BundleIDs.vendor(target) }
            } else {
                let wanted = UninstallMatch.folded(lowered.hasSuffix(".app") ? String(target.dropLast(4)) : target)
                let apps = index.apps.values.flatMap { $0 }.filter { app in
                    UninstallMatch.folded(app.name ?? "") == wanted
                        || UninstallMatch.folded(PathText.lastComponent(app.path).replacingOccurrences(of: ".app", with: "")) == wanted
                }
                for app in apps { try adopt(app) }
                if identity.names.isEmpty { identity.names = [target] }
            }
            matchReceipts()
        }

        /// The installed copies of a bundle id: app folders first, then LaunchServices.
        func installed(_ bundleID: String) -> [InstalledApp] {
            if let apps = index.apps[bundleID.lowercased()], !apps.isEmpty { return apps }
            if case .installed(let apps) = context.lookup.launchServices(bundleID) { return apps }
            return []
        }

        mutating func adopt(_ app: InstalledApp) throws(DiskCleanupError) {
            if PathText.isWithin(app.path, "/System") || PathText.isWithin(app.path, root + "/System") {
                throw .refusedTarget("\(app.name ?? app.bundleID) is part of macOS (\(app.path))")
            }
            if !identity.bundleIDs.contains(where: { $0.lowercased() == app.bundleID.lowercased() }) {
                identity.bundleIDs.append(app.bundleID)
            }
            if !identity.apps.contains(app.path) { identity.apps.append(app.path) }
            for name in [app.name, PathText.lastComponent(app.path).replacingOccurrences(of: ".app", with: "")].compactMap({ $0 })
            where !identity.names.contains(name) {
                identity.names.append(name)
            }
            if !BundleIDs.isApple(app.bundleID), let team = context.records.teamID(appAt: app.path), !identity.teamIDs.contains(team) {
                identity.teamIDs.append(team)
            }
        }

        /// `com.apple.garageband10` → `garageband`: a name for a gone app.
        static func nameFromID(_ id: String) -> String {
            let last = String(id.split(separator: ".").last ?? "")
            let trimmed = String(last.reversed().drop(while: \.isNumber).reversed())
            return trimmed.count >= 4 ? trimmed : last
        }

        mutating func matchReceipts() {
            guard let ids = context.records.packageIDs() else {
                notes.append("installer receipts were not read: pkgutil did not answer")
                return
            }
            let input = identity.input.lowercased()
            let nameOnly = identity.bundleIDs.isEmpty && identity.vendor == nil && identity.teamIDs.isEmpty
            for id in ids {
                let lowered = id.lowercased()
                let byBundle = bundleIDs.contains { lowered == $0 || lowered.hasPrefix($0 + ".") }
                let byVendor = identity.vendor.map { lowered.hasPrefix($0 + ".") } ?? false
                let byName = nameOnly && !BundleIDs.isApple(id) && tokens.contains { UninstallMatch.folded(id).contains($0) }
                guard lowered == input || byBundle || byVendor || byName, let receipt = context.records.receipt(id) else { continue }
                identity.receipts.append(id)
                receipts.append(receipt)
            }
        }

        // MARK: 2–4. What

        mutating func collect() {
            for receipt in receipts { collectReceipt(receipt) }
            for app in identity.apps { add(app, .exact, "the app (\(identity.bundleIDs.joined(separator: ", ")))") }
            // An app a receipt owns says who it is, even when only a package id was typed.
            for (path, entry) in found where entry.evidence["receipt"] != nil && path.hasSuffix(".app") {
                if let app = AppIndex.read(appAt: path), !bundleIDs.contains(app.bundleID.lowercased()) {
                    identity.bundleIDs.append(app.bundleID)
                    if let name = app.name { identity.names.append(name) }
                }
            }
            collectLibrary()
            collectLaunchJobs()
            collectHelpers()
            collectGroupContainers()
            collectPlugIns()
            collectNames()
        }

        /// The deepest paths a receipt owns whole: a bundle it lists, a file it
        /// lists, or a folder whose every entry it lists and whose name is the
        /// product's or the vendor's. A folder holding anything else is shared.
        mutating func collectReceipt(_ receipt: PackageReceipt) {
            let base = UninstallMatch.base(of: receipt, root: root.isEmpty ? "/" : root)
            let listed = Set(receipt.files.map { PathText.components($0).joined(separator: "/") })
            var taken: [String] = []
            for relative in listed.sorted(by: { PathText.components($0).count < PathText.components($1).count }) {
                guard !taken.contains(where: { relative.hasPrefix($0 + "/") }) else { continue }
                let path = "/" + (PathText.components(base) + PathText.components(relative)).joined(separator: "/")
                guard PathProbe.exists(path), staysPut(path) else { continue }
                let name = PathText.lastComponent(path)
                let owned = !PathProbe.isDirectory(path) || UninstallMatch.isBundle(name)
                    || (UninstallMatch.matchedToken(name, tokens: tokens + [UninstallMatch.folded(receipt.id)]) != nil
                        && ownsWhole(path, relative: relative, listed: listed))
                guard owned else { continue }
                taken.append(relative)
                add(path, .exact, "receipt \(receipt.id)", ["receipt": receipt.id])
            }
        }

        func ownsWhole(_ path: String, relative: String, listed: Set<String>) -> Bool {
            PathProbe.list(path).names.allSatisfy { name in
                let child = relative + "/" + name
                guard listed.contains(child) else { return false }
                return !PathProbe.isDirectory(path + "/" + name) || ownsWhole(path + "/" + name, relative: child, listed: listed)
            }
        }

        /// ~/Library places an app's sandbox and frameworks name by bundle id.
        mutating func collectLibrary() {
            let library = home + "/Library"
            for name in PathProbe.list(library + "/Containers").names {
                let path = library + "/Containers/" + name
                let owner = (PathProbe.read(path + "/.com.apple.containermanagerd.metadata.plist").flatMap(PlistValues.containerOwner) ?? name).lowercased()
                if let id = bundleIDs.first(where: { owner == $0 || owner.hasPrefix($0 + ".") }) {
                    add(path, .exact, "container of \(id)")
                }
            }
            let named: [(String, (String, String) -> Bool)] = [
                ("Caches", { $0 == $1 }), ("HTTPStorages", { $0 == $1 || $0 == $1 + ".binarycookies" }),
                ("WebKit", { $0 == $1 }), ("Logs", { $0 == $1 }), ("Application Support", { $0 == $1 }),
                ("Saved Application State", { $0 == $1 + ".savedstate" }), ("Preferences", { $0 == $1 + ".plist" }),
                ("Preferences/ByHost", { $0.hasPrefix($1 + ".") && $0.hasSuffix(".plist") }),
            ]
            for (folder, matches) in named {
                for name in PathProbe.list(library + "/" + folder).names {
                    if let id = bundleIDs.first(where: { matches(name.lowercased(), $0) }) {
                        add(library + "/" + folder + "/" + name, .exact, "named by bundle id \(id)")
                    }
                }
            }
        }

        /// Launch agents and daemons that run the app, or carry its bundle id
        /// (exact) or its vendor's prefix (likely) as their label.
        mutating func collectLaunchJobs() {
            let owned = found.filter { $0.value.match == .exact }.map(\.key) + identity.apps
            let folders = [(home + "/Library/LaunchAgents", "gui"), (root + "/Library/LaunchAgents", "gui"),
                           (root + "/Library/LaunchDaemons", "system")]
            for (folder, domain) in folders {
                for name in PathProbe.list(folder).names where name.hasSuffix(".plist") {
                    let path = folder + "/" + name
                    guard let data = PathProbe.read(path, limit: 1 << 20), let job = PlistValues.launchJob(data) else { continue }
                    let label = (job.label ?? String(name.dropLast(6)))
                    let lowered = label.lowercased()
                    let extra = ["launchLabel": label, "launchDomain": domain]
                    if let program = job.program, owned.contains(where: { PathText.isWithin(root + program, $0) || PathText.isWithin(program, $0) }) {
                        add(path, .exact, "launch job runs \(program)", extra)
                    } else if let id = bundleIDs.first(where: { lowered == $0 || lowered.hasPrefix($0 + ".") }) {
                        add(path, .exact, "launch job label \(label) is \(id)'s", extra)
                    } else if let vendor = identity.vendor, lowered.hasPrefix(vendor + ".") {
                        add(path, shared(vendor) == nil ? .likely : .review, "launch job label \(label) has the vendor prefix",
                            extra.merging(sharedNote(vendor)) { a, _ in a })
                    }
                }
            }
        }

        /// /Library/PrivilegedHelperTools items named by the bundle id or vendor.
        mutating func collectHelpers() {
            let folder = root + "/Library/PrivilegedHelperTools"
            for name in PathProbe.list(folder).names {
                let lowered = name.lowercased()
                if let id = bundleIDs.first(where: { lowered == $0 || lowered.hasPrefix($0 + ".") }) {
                    add(folder + "/" + name, .exact, "helper named by bundle id \(id)")
                } else if let vendor = identity.vendor, lowered.hasPrefix(vendor + ".") {
                    add(folder + "/" + name, shared(vendor) == nil ? .likely : .review, "helper has the vendor prefix", sharedNote(vendor))
                }
            }
        }

        /// Group containers: the app's own by bundle id, its team's or vendor's
        /// as likely — or review when another installed app is the vendor's too.
        mutating func collectGroupContainers() {
            let folder = home + "/Library/Group Containers"
            for name in PathProbe.list(folder).names {
                let base = BundleIDs.groupBase(name).lowercased()
                let path = folder + "/" + name
                if let id = bundleIDs.first(where: { base == $0 || base.hasPrefix($0 + ".") }) {
                    add(path, .exact, "group container of \(id)")
                } else if let team = identity.teamIDs.first(where: { name.hasPrefix($0 + ".") }) {
                    let vendor = BundleIDs.vendor(base)
                    add(path, shared(vendor) == nil ? .likely : .review, "team id \(team)", sharedNote(vendor))
                } else if let vendor = identity.vendor, base.hasPrefix(vendor + ".") {
                    add(path, shared(vendor) == nil ? .likely : .review, "group container has the vendor prefix", sharedNote(vendor))
                }
            }
        }

        /// Audio plug-ins (AU, VST, VST3, CLAP, AAX) whose bundle id is the
        /// app's (exact) or has the vendor's prefix (likely).
        mutating func collectPlugIns() {
            var folders: [String] = []
            for base in [root + "/Library/Audio/Plug-Ins", home + "/Library/Audio/Plug-Ins"] {
                folders += PathProbe.list(base).names.map { base + "/" + $0 }
            }
            folders.append(root + "/Library/Application Support/Avid/Audio/Plug-Ins")
            for folder in folders {
                for name in PathProbe.list(folder).names where UninstallMatch.isBundle(name) {
                    let path = folder + "/" + name
                    guard let data = PathProbe.read(path + "/Contents/Info.plist"), let id = PlistValues.bundleInfo(data)?.bundleID.lowercased() else { continue }
                    if bundleIDs.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) {
                        add(path, .exact, "plug-in bundle id \(id)")
                    } else if let vendor = identity.vendor, id.hasPrefix(vendor + ".") {
                        add(path, shared(vendor) == nil ? .likely : .review, "plug-in bundle id \(id) has the vendor prefix", sharedNote(vendor))
                    }
                }
            }
        }

        /// Name matches, always review: Application Support (both), Preferences,
        /// Logs, and dotfiles in the home folder.
        mutating func collectNames() {
            let tokens = self.tokens
            guard !tokens.isEmpty else { return }
            let folders = [home + "/Library/Application Support", root + "/Library/Application Support",
                           home + "/Library/Preferences", home + "/Library/Logs"]
            var places = folders.flatMap { folder in PathProbe.list(folder).names.map { folder + "/" + $0 } }
            places += PathProbe.list(home).names.filter { $0.hasPrefix(".") && $0 != ".Trash" }.map { home + "/" + $0 }
            for path in places {
                guard let token = UninstallMatch.matchedToken(PathText.lastComponent(path), tokens: tokens) else { continue }
                let vendorFolder = identity.vendor.map { UninstallMatch.vendorStem($0) == token } ?? false
                let users = others.filter { app in
                    UninstallMatch.folded(app.name ?? "").contains(token)
                        || UninstallMatch.folded(PathText.lastComponent(app.path)).contains(token)
                        || (vendorFolder && BundleIDs.vendor(app.bundleID) == identity.vendor)
                }
                var extra: [String: String] = [:]
                if !users.isEmpty { extra["sharedWith"] = Search.names(users) }
                add(path, .review, "name match \"\(token)\"", extra)
            }
        }

        /// Installed apps outside the uninstall from `vendor`, if any.
        func shared(_ vendor: String) -> [InstalledApp]? {
            guard !BundleIDs.isApple(vendor + ".") else { return nil }
            let users = others.filter { BundleIDs.vendor($0.bundleID) == vendor }
            return users.isEmpty ? nil : users
        }

        func sharedNote(_ vendor: String) -> [String: String] {
            shared(vendor).map { ["sharedWith": Search.names($0)] } ?? [:]
        }

        static func names(_ apps: [InstalledApp]) -> String {
            Array(Set(apps.map { $0.name ?? PathText.lastComponent($0.path) })).sorted().joined(separator: ", ")
        }

        /// Records `path`, keeping the strongest evidence for it.
        mutating func add(_ path: String, _ match: Match, _ why: String, _ evidence: [String: String] = [:]) {
            let path = "/" + PathText.components(path).joined(separator: "/")
            guard PathProbe.exists(path), staysPut(path) else { return }
            if let earlier = found[path], earlier.match <= match { return }
            var entry = Found(match: match, why: why, evidence: evidence)
            if let sharedWith = evidence["sharedWith"] { entry.why += " — also used by \(sharedWith)" }
            found[path] = entry
        }

        // MARK: The plan

        /// Items, strongest first. One inside another of the same or stronger
        /// evidence goes with it; one inside a weaker (review) item stays its
        /// own, so taking only exact items still takes it.
        func finish() -> UninstallPlan {
            let ordered = found.sorted { a, b in
                a.value.match != b.value.match ? a.value.match < b.value.match : a.key < b.key
            }
            var items: [Item] = []
            var kept: [(String, Match)] = []
            for (path, entry) in ordered {
                if kept.contains(where: { PathText.isWithin(path, $0.0) && $0.1 <= entry.match && path != $0.0 }) { continue }
                kept.append((path, entry.match))
                items.append(item(path, entry))
            }
            let running = context.lookup.runningBundleIDs()
            var notes = self.notes
            if identity.apps.isEmpty && !identity.bundleIDs.isEmpty {
                notes.append("no app by \(identity.bundleIDs.joined(separator: ", ")) is installed: looking for what it left")
            }
            return UninstallPlan(identity: identity, items: items,
                                 running: identity.bundleIDs.filter { running.contains($0.lowercased()) }, notes: notes)
        }

        func item(_ path: String, _ entry: Found) -> Item {
            let measurement = Sizer.measure(path)
            var evidence = entry.evidence
            evidence["match"] = entry.match.rawValue
            evidence["why"] = entry.why
            let protected = PathSafety.reason(for: path, catalogue: catalogue, home: home, allowing: Uninstaller.allowedInside)
            return Item(
                id: ItemID.make(rule: "uninstall", path: path), rule: "uninstall", category: .leftovers, path: path,
                bytes: measurement.visibility == .notVisible ? nil : measurement.bytes,
                tier: entry.match == .review ? .review : .safe,
                removal: Uninstaller.needsRoot(path) ? .sudo : .trash, regenerable: false,
                owner: identity.names.first ?? identity.input, newest: measurement.newest,
                visibility: measurement.visibility, protected: protected, evidence: evidence, note: nil,
                identity: Sizer.identity(path, bytes: measurement.bytes)
            )
        }
    }
}
