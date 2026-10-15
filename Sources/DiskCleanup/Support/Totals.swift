//
//  Totals.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum Totals {

    /// A category's visibility from the visibility of each place it looked.
    static func visibility(_ seen: [Visibility]) -> Visibility {
        let present = seen.filter { $0 != .absent }
        guard !present.isEmpty else { return .absent }
        if present.allSatisfy({ $0 == .notVisible }) { return .notVisible }
        if present.contains(.notVisible) || present.contains(.partial) { return .partial }
        return .visible
    }

    /// One line per category, in category order.
    static func categories(_ items: [Item], visibility: [CleanupCategory: [Visibility]],
                           scanned: [CleanupCategory]) -> [CategoryTotal] {
        scanned.map { category in
            let mine = items.filter { $0.category == category }
            func sum(_ predicate: (Item) -> Bool) -> Int64 {
                mine.filter(predicate).reduce(0) { $0 + ($1.bytes ?? 0) }
            }
            var seen = visibility[category] ?? []
            seen += mine.map(\.visibility)
            return CategoryTotal(
                category: category,
                visibility: Totals.visibility(seen),
                items: mine.count,
                bytes: sum { _ in true },
                safeBytes: sum { $0.tier == .safe && $0.protected == nil },
                reviewBytes: sum { $0.tier == .review && $0.protected == nil },
                reportBytes: sum { $0.tier == .report },
                protectedBytes: sum { $0.tier != .report && $0.protected != nil },
                tiers: Tier.allCases.filter { tier in mine.contains { $0.tier == tier } }
            )
        }
    }
}
