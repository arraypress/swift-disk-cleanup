//
//  IgnoreList+Matching.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension IgnoreList {

    /// Why `item` is held back by this list — `ignored (by you): …` — or `nil`.
    func reason(for item: Item, home: String) -> String? {
        IgnoreMatch.entry(for: item, in: self, home: home).map(IgnoreMatch.reason)
    }

    /// The entry `text` names (a path, a rule id or an item id).
    static func entry(for text: String, catalogue: Catalogue, home: String, now: Date = Date()) throws(DiskCleanupError) -> IgnoreEntry {
        try IgnoreMatch.entry(for: text, catalogue: catalogue, home: home, now: now)
    }

    /// The list with `entry` added, unless it is already there.
    func adding(_ entry: IgnoreEntry) -> (list: IgnoreList, added: Bool) {
        guard !entries.contains(where: { $0.kind == entry.kind && $0.value == entry.value }) else { return (self, false) }
        return (IgnoreList(entries: entries + [entry]), true)
    }

    /// The list without the entry `entry` names, and whether one was there.
    func removing(_ entry: IgnoreEntry) -> (list: IgnoreList, removed: Bool) {
        let kept = entries.filter { !($0.kind == entry.kind && $0.value == entry.value) }
        return (IgnoreList(entries: kept), kept.count != entries.count)
    }
}
