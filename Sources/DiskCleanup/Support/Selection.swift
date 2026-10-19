//
//  Selection.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Which items a `clean` takes. A category takes its safe items (and review
//  ones when asked); an id takes that one item if it can be cleaned at all.
//  Report items, protected items and anything too young never go.
//

import Foundation

enum Selection {

    /// Splits clean targets into categories and item ids.
    static func parse(_ targets: [String]) throws(DiskCleanupError) -> (categories: Set<CleanupCategory>, ids: Set<String>) {
        var categories = Set<CleanupCategory>()
        var ids = Set<String>()
        for target in targets {
            if let category = CleanupCategory(rawValue: target) {
                categories.insert(category)
            } else if ItemID.isItemID(target) {
                ids.insert(target)
            } else {
                throw .unknownTarget(target)
            }
        }
        return (categories, ids)
    }

    /// The items to act on, and the named ones held back with why.
    static func pick(_ items: [Item], categories: Set<CleanupCategory>, ids: Set<String>,
                     includeReview: Bool, olderThanDays: Int?, now: Date) -> (take: [Item], held: [(Item, String)]) {
        var take: [Item] = []
        var held: [(Item, String)] = []
        for item in items {
            let named = ids.contains(item.id)
            guard named || categories.contains(item.category) else { continue }
            if let reason = holdReason(item, named: named, includeReview: includeReview,
                                       olderThanDays: olderThanDays, now: now) {
                if named { held.append((item, reason)) }
                continue
            }
            take.append(item)
        }
        return (take, held)
    }

    static func holdReason(_ item: Item, named: Bool, includeReview: Bool, olderThanDays: Int?, now: Date) -> String? {
        if let ignored = item.ignored { return ignored }
        if item.tier == .report { return "report only: never cleaned" }
        if let protected = item.protected { return protected }
        if item.tier == .review && !named && !includeReview { return "review tier" }
        if item.byIDOnly && !named { return "goes only by id" }
        if item.visibility == .notVisible { return "not visible without Full Disk Access" }
        if item.visibility == .partial { return "parts of it could not be read, so what it holds is not known" }
        if let days = olderThanDays {
            guard let newest = item.newest else { return "its age is unknown" }
            if newest > now.addingTimeInterval(-Double(days) * 86_400) {
                return "touched \(Ages.days(since: newest, now: now)) days ago"
            }
        }
        return nil
    }
}
