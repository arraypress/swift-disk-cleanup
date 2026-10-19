//
//  IgnoreMatch.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Which ignore entry, if any, holds an item back. A path entry holds what
//  lies inside it and what holds it — removing a folder would take the
//  ignored place inside it along — so it is matched by overlap, never by
//  equality alone. A rule entry holds everything that rule found; an item
//  entry holds that one id.
//

import Foundation

enum IgnoreMatch {

    /// Rule names made by code rather than the catalogue, which may be ignored too.
    static let codeRules = ["uninstall", "duplicate", "big-file", "startup-agent", "plugin"]

    /// The entry that holds `item` back, or `nil`.
    static func entry(for item: Item, in list: IgnoreList, home: String) -> IgnoreEntry? {
        list.entries.first { entry in
            switch entry.kind {
            case .item: return item.id == entry.value
            case .rule: return item.rule == entry.value
            case .path:
                guard item.path.hasPrefix("/") else { return false }
                return PathText.overlaps(item.path, PathText.expand(entry.value, home: home))
            }
        }
    }

    /// What a held item says: `ignored (by you): ~/Library/Caches/Foo`.
    static func reason(_ entry: IgnoreEntry) -> String {
        "ignored (by you): \(entry.value)"
    }

    /// What `text` names: a path (anything with a `/`, or `~`), an item id,
    /// or a rule — the catalogue's or one of the code's own.
    static func entry(for text: String, catalogue: Catalogue, home: String, now: Date = Date()) throws(DiskCleanupError) -> IgnoreEntry {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("~") || text.contains("/") {
            let expanded = PathText.normalised(PathText.expand(text, home: home))
            guard expanded.hasPrefix("/"), !PathText.components(expanded).contains("..") else {
                throw .unknownTarget("\(text) (a path must be absolute or start with ~/)")
            }
            return IgnoreEntry(kind: .path, value: PathText.abbreviated(expanded, home: home), added: now)
        }
        if catalogue.rules.contains(where: { $0.id == text }) || codeRules.contains(text) {
            return IgnoreEntry(kind: .rule, value: text, added: now)
        }
        if ItemID.isItemID(text) {
            return IgnoreEntry(kind: .item, value: text, added: now)
        }
        throw .unknownTarget(text)
    }
}
