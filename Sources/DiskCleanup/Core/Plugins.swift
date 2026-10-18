//
//  Plugins.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Every plugin on the Mac — audio (AU, VST, VST3, CLAP, AAX), Quick Look,
//  preference panes, Internet plug-ins, legacy Safari extensions — with
//  vendor, version and architectures. Only one that provably cannot load
//  may go (review): AAX with no Pro Tools, a binary with no arm64 slice on
//  Apple silicon without Rosetta, an Internet plug-in (no browser loads
//  them) or a .safariextz (Safari dropped them). The rest are a report.
//  What you own goes to the Trash with undo; root's, in the sudo line.
//

import Foundation

public enum Plugins {

    /// Rule name on the removable items; their category is internal only.
    public static let rule = "plugin"

    /// Rosetta's runtime: present means x86_64 plugins still load in an x86_64 host.
    static let rosettaRuntime = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"

    /// Everything found, grouped by vendor then format, and the items that may go.
    public static func inventory(catalogue: Catalogue, context: CleanupContext, appleSilicon: Bool = Plugins.isAppleSilicon) -> (entries: [PluginEntry], items: [Item], rosetta: Bool, notes: [String]) {
        let root = context.root.path == "/" ? "" : context.root.path
        let home = context.home.path
        let rosetta = PathProbe.exists(root + rosettaRuntime)
        var places: [(String, String)] = []
        for base in [root + "/Library/Audio/Plug-Ins", home + "/Library/Audio/Plug-Ins"] {
            places += [("Components", "AU"), ("VST", "VST"), ("VST3", "VST3"), ("CLAP", "CLAP")].map { (base + "/" + $0.0, $0.1) }
        }
        places.append((root + "/Library/Application Support/Avid/Audio/Plug-Ins", "AAX"))
        for base in [root + "/Library", home + "/Library"] {
            places += [(base + "/QuickLook", "Quick Look"), (base + "/PreferencePanes", "Preference Pane"), (base + "/Internet Plug-Ins", "Internet Plug-in")]
        }
        places.append((home + "/Library/Safari/Extensions", "Safari Extension"))

        var notes: [String] = []
        var proTools: Bool?
        var entries: [PluginEntry] = []
        var items: [Item] = []
        for (folder, format) in places {
            let listing = PathProbe.list(folder)
            if listing.visibility == .notVisible { notes.append("\(folder) is not visible without Full Disk Access") }
            for name in listing.names where !name.hasPrefix(".") {
                let path = folder + "/" + name
                let info = PathProbe.read(path + "/Contents/Info.plist").flatMap(PlistValues.dictionary) ?? [:]
                let id = info["CFBundleIdentifier"] as? String
                let executable = info["CFBundleExecutable"] as? String
                let archs = executable.flatMap { PathProbe.read(path + "/Contents/MacOS/" + $0, limit: 4096) }.flatMap(MachOText.architectures)
                var cannotLoad: String?
                switch format {
                case "Safari Extension" where name.hasSuffix(".safariextz"):
                    cannotLoad = "a legacy .safariextz: Safari has not loaded these since Safari 13"
                case "Internet Plug-in":
                    cannotLoad = "an Internet plug-in: no current browser loads them"
                case "AAX":
                    if proTools == nil { proTools = proToolsInstalled(context) }
                    if proTools == false { cannotLoad = "AAX loads only in Pro Tools, which is not installed" }
                default:
                    break
                }
                if cannotLoad == nil, appleSilicon, !rosetta, let archs, !archs.contains("arm64") {
                    cannotLoad = "built for \(archs.joined(separator: ", ")) only, and this Apple silicon Mac has no Rosetta"
                }
                let measured = Sizer.measure(path)
                var itemID: String?
                if let cannotLoad {
                    let item = Item(id: ItemID.make(rule: rule, path: path), rule: rule, category: .leftovers, path: path,
                                    bytes: measured.bytes, tier: .review, removal: Uninstaller.needsRoot(path) ? .sudo : .trash,
                                    regenerable: false, owner: id.map(BundleIDs.vendor), newest: measured.newest, visibility: measured.visibility,
                                    protected: PathSafety.reason(for: path, catalogue: catalogue, home: home),
                                    evidence: ["format": format, "cannotLoad": cannotLoad], note: nil,
                                    identity: Sizer.identity(path, bytes: measured.bytes), apparentBytes: measured.apparentBytes)
                    items.append(item)
                    itemID = item.id
                }
                entries.append(PluginEntry(path: path, format: format, name: (name as NSString).deletingPathExtension, bundleID: id,
                                           vendor: id.map(BundleIDs.vendor) ?? "unknown", version: info["CFBundleShortVersionString"] as? String,
                                           architectures: archs, bytes: measured.visibility == .notVisible ? nil : measured.bytes,
                                           cannotLoad: cannotLoad, itemID: itemID))
            }
        }
        entries.sort { ($0.vendor, $0.format, $0.name.lowercased()) < ($1.vendor, $1.format, $1.name.lowercased()) }
        return (entries, items, rosetta, notes)
    }

    /// Pro Tools by any Avid app id: anything of Avid's keeps AAX plugins.
    static func proToolsInstalled(_ context: CleanupContext) -> Bool {
        let index = AppIndex.build(folders: context.applicationFolders)
        return Detectors.appInstalled("com.avid.ProTools", known: index.knownIDs, running: context.lookup.runningBundleIDs(), context: context) != false
    }

    /// Whether this process runs on Apple silicon.
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// The items to take: the named ones, or every one with `all`.
    public static func select(_ items: [Item], ids: Set<String>, all: Bool, now: Date = Date()) -> (take: [Item], held: [(Item, String)]) {
        BigFiles.select(items, ids: ids, all: all, now: now)
    }
}
