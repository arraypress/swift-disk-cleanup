//
//  Planner.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turning "clean these" into the items that will go.
public enum Planner {

    /// Splits arguments into categories and item ids; anything else is refused.
    public static func targets(_ arguments: [String]) throws(DiskCleanupError) -> CleanTargets {
        let parsed = try Selection.parse(arguments)
        return CleanTargets(categories: parsed.categories, ids: parsed.ids)
    }

    /// The categories a scan must cover to find every target.
    public static func categories(for targets: CleanTargets, catalogue: Catalogue) throws(DiskCleanupError) -> Set<CleanupCategory> {
        var categories = targets.categories
        for id in targets.ids {
            guard let rule = catalogue.rule(forItem: id) else { throw .itemNotFound(id) }
            categories.insert(rule.category)
        }
        return categories
    }

    /// The items a clean takes from a scan. A named id the scan did not find
    /// is an error: it may already be gone, or the id is wrong.
    public static func select(_ targets: CleanTargets, from report: ScanReport, includeReview: Bool,
                              olderThanDays: Int?, now: Date = Date()) throws(DiskCleanupError) -> CleanSelection {
        for id in targets.ids.sorted() where !report.items.contains(where: { $0.id == id }) {
            throw .itemNotFound(id)
        }
        let picked = Selection.pick(report.items, categories: targets.categories, ids: targets.ids,
                                    includeReview: includeReview, olderThanDays: olderThanDays, now: now)
        return CleanSelection(take: picked.take, held: picked.held.map { HeldItem(item: $0.0, reason: $0.1) })
    }
}
