//
//  DockEdit.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Taking an uninstalled app's icon out of the Dock, and putting it back:
//
//  1. read `persistent-apps` and `recent-apps` and find the app's tiles —
//     none left means nothing to do;
//  2. journal the exact arrays it is about to replace (and what it will
//     write) BEFORE writing, so a crash leaves the original on record;
//  3. write the arrays without those tiles through cfprefsd, restart the
//     Dock, and read them back: the tiles must be gone and the rest as written.
//
//  Undo writes the journalled arrays back — exactly — and restarts the Dock,
//  but only while the Dock still holds what diskmaid wrote: if it changed
//  since (an icon dragged in or out), nothing is overwritten.
//

import Foundation

public enum DockEdit {

    /// The rule on journal entries, so undo knows an entry is a Dock edit.
    public static let rule = "dock"

    /// What the Dock holds of an app: the array, the tile's index and its name.
    public struct Tile: Equatable, Sendable {
        public let key: String
        public let index: Int
        public let label: String?
    }

    /// The tiles that are these apps, in both arrays.
    public static func tiles(bundleIDs: [String], apps: [String], dock: any DockPreferences) -> [Tile] {
        DockTiles.keys.flatMap { key -> [Tile] in
            guard let tiles = dock.value(key) as? [Any] else { return [] }
            return DockTiles.matching(tiles, bundleIDs: bundleIDs, apps: apps).map { Tile(key: key, index: $0, label: DockTiles.label(tiles[$0])) }
        }
    }

    /// The bundle ids and app paths an uninstall's Dock item stands for.
    static func targets(_ item: Item) -> (bundleIDs: [String], apps: [String]) {
        func list(_ key: String) -> [String] { (item.evidence[key] ?? "").split(separator: "\n").map(String.init) }
        return (list("dockBundleIDs"), list("dockApps"))
    }

    /// Removes the item's tiles from the Dock, journalled in `batch`.
    static func remove(_ item: Item, context: CleanupContext, batch: String) -> RemovalOutcome {
        func outcome(_ result: RemovalOutcome.Result, _ reason: String? = nil) -> RemovalOutcome {
            RemovalOutcome(id: item.id, path: item.path, result: result, to: result == .edited ? "com.apple.dock" : nil, reason: reason)
        }
        let dock = context.dock
        let (bundleIDs, apps) = targets(item)
        var before: [String: Any] = [:]
        var edited: [String: Any] = [:]
        var removed = 0
        for key in DockTiles.keys {
            guard let tiles = dock.value(key) as? [Any] else { continue }
            let found = DockTiles.matching(tiles, bundleIDs: bundleIDs, apps: apps)
            guard !found.isEmpty else { continue }
            before[key] = tiles
            edited[key] = DockTiles.removing(tiles, at: found)
            removed += found.count
        }
        guard removed > 0 else { return outcome(.skipped, "the Dock has no icon for it any more") }
        guard let backup = DockTiles.archive(before), let after = DockTiles.archive(edited) else {
            return outcome(.failed, "the Dock's icons could not be copied for undo, so the Dock was left alone")
        }
        let entry = JournalEntry(id: UUID().uuidString.lowercased(), batch: batch, original: "com.apple.dock",
                                 trashed: "", at: Date(), bytes: nil, rule: rule, backup: backup, after: after)
        do {
            try JournalStore.append(entry, to: context.journal)
        } catch {
            return outcome(.failed, "the undo journal could not be written, so the Dock was left alone: \(error.localizedDescription)")
        }
        for (key, value) in edited where !dock.set(key, value) {
            for (key, value) in before { _ = dock.set(key, value) }
            return outcome(.failed, "cfprefsd did not take the Dock's new \(key); the original was written back")
        }
        let restarted = dock.restart()
        for (key, value) in edited where !DockTiles.same(dock.value(key), value) {
            return outcome(.failed, "after a restart the Dock's \(key) is not what was written; `diskmaid undo` puts the original back")
        }
        return outcome(.edited, restarted ? nil : "the Dock did not restart; it shows the change when it next starts")
    }

    /// Puts a Dock edit's arrays back exactly, unless the Dock changed since.
    static func restore(_ entry: JournalEntry, context: CleanupContext) -> (RestoreOutcome.Result, String?) {
        guard let before = DockTiles.unarchive(entry.backup), let after = DockTiles.unarchive(entry.after) else {
            return (.failed, "the journal entry holds no readable copy of the Dock's icons")
        }
        let dock = context.dock
        if let key = after.keys.sorted().first(where: { !DockTiles.same(dock.value($0), after[$0]) }) {
            return (.occupied, "the Dock's \(key) changed after diskmaid's edit, so it was left as it is")
        }
        for (key, value) in before where !dock.set(key, value) {
            return (.failed, "cfprefsd did not take the Dock's \(key)")
        }
        let restarted = dock.restart()
        if let key = before.keys.sorted().first(where: { !DockTiles.same(dock.value($0), before[$0]) }) {
            return (.failed, "after a restart the Dock's \(key) is not the original")
        }
        return (.restored, restarted ? nil : "the Dock did not restart; it shows the icon when it next starts")
    }
}
