//
//  CleanSelection.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a `clean` would act on, and the items it was asked for by id but
/// will not touch, each with why.
public struct CleanSelection: Sendable {
    public let take: [Item]
    public let held: [HeldItem]

    public init(take: [Item], held: [HeldItem]) {
        self.take = take
        self.held = held
    }
}

/// An item named for cleaning that stays.
public struct HeldItem: Sendable {
    public let item: Item
    public let reason: String

    public init(item: Item, reason: String) {
        self.item = item
        self.reason = reason
    }
}

/// What a clean was asked to act on: whole categories, single items, or both.
public struct CleanTargets: Equatable, Sendable {
    public let categories: Set<CleanupCategory>
    public let ids: Set<String>

    public init(categories: Set<CleanupCategory>, ids: Set<String>) {
        self.categories = categories
        self.ids = ids
    }
}
