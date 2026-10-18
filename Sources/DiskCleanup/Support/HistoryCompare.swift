//
//  HistoryCompare.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Two scans side by side. Only categories both covered are compared, so a
//  scan of one category never makes the rest look gone; items line up by
//  id (rule + path); one that could not be measured either time is skipped.
//

import Foundation

enum HistoryCompare {

    /// A report as a history entry.
    static func entry(_ report: ScanReport, at: Date) -> HistoryEntry {
        HistoryEntry(
            at: at,
            categories: Dictionary(uniqueKeysWithValues: report.categories.map { ($0.category.rawValue, $0.bytes) }),
            items: report.items.map { HistoryItem(id: $0.id, path: $0.path, rule: $0.rule, category: $0.category.rawValue, bytes: $0.bytes) }
        )
    }

    static func compare(_ before: HistoryEntry, _ after: HistoryEntry) -> ScanChanges {
        let shared = Set(before.categories.keys).intersection(after.categories.keys)
        var categories: [SizeChange] = []
        for name in shared {
            let old = before.categories[name] ?? 0, new = after.categories[name] ?? 0
            guard old != new else { continue }
            categories.append(SizeChange(id: name, path: nil, rule: nil, category: name, beforeBytes: old, afterBytes: new,
                                         deltaBytes: new - old, status: new > old ? "grew" : "shrank"))
        }
        let old = Dictionary(before.items.filter { shared.contains($0.category) }.map { ($0.id, $0) }) { first, _ in first }
        let new = Dictionary(after.items.filter { shared.contains($0.category) }.map { ($0.id, $0) }) { first, _ in first }
        var items: [SizeChange] = []
        for id in Set(old.keys).union(new.keys) {
            let was = old[id], now = new[id]
            let describe = (now ?? was)!
            switch (was?.bytes, now?.bytes) {
            case let (a?, b?) where a != b:
                items.append(change(describe, a, b, b - a, b > a ? "grew" : "shrank"))
            case let (nil, b?) where was == nil && b > 0:
                items.append(change(describe, nil, b, b, "new"))
            case let (a?, nil) where now == nil && a > 0:
                items.append(change(describe, a, nil, -a, "gone"))
            default:
                continue
            }
        }
        let byChange: (SizeChange, SizeChange) -> Bool = { a, b in
            abs(a.deltaBytes) != abs(b.deltaBytes) ? abs(a.deltaBytes) > abs(b.deltaBytes) : a.id < b.id
        }
        let grew = items.filter { $0.deltaBytes > 0 }.reduce(0) { $0 + $1.deltaBytes }
        let shrank = items.filter { $0.deltaBytes < 0 }.reduce(0) { $0 - $1.deltaBytes }
        return ScanChanges(since: before.at, until: after.at, grewBytes: grew, shrankBytes: shrank, netBytes: grew - shrank,
                           categories: categories.sorted(by: byChange), items: items.sorted(by: byChange))
    }

    static func change(_ item: HistoryItem, _ before: Int64?, _ after: Int64?, _ delta: Int64, _ status: String) -> SizeChange {
        SizeChange(id: item.id, path: item.path, rule: item.rule, category: item.category, beforeBytes: before, afterBytes: after,
                   deltaBytes: delta, status: status)
    }
}
