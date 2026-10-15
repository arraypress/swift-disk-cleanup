//
//  CategoryTotal.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One category's line in a scan.
public struct CategoryTotal: Codable, Equatable, Sendable {
    public let category: CleanupCategory
    /// Whether it could be looked at. `not-visible` means Full Disk Access,
    /// never "nothing there".
    public let visibility: Visibility
    public let items: Int
    /// Everything found, every tier.
    public let bytes: Int64
    /// What `clean <category>` would take: safe and not protected.
    public let safeBytes: Int64
    /// What needs a look first: review tier, not protected.
    public let reviewBytes: Int64
    /// Shown only.
    public let reportBytes: Int64
    /// Found but held back (recent, tracked by git, kept newest…).
    public let protectedBytes: Int64
    /// The tiers present.
    public let tiers: [Tier]

    public init(category: CleanupCategory, visibility: Visibility, items: Int, bytes: Int64,
                safeBytes: Int64, reviewBytes: Int64, reportBytes: Int64, protectedBytes: Int64,
                tiers: [Tier]) {
        self.category = category
        self.visibility = visibility
        self.items = items
        self.bytes = bytes
        self.safeBytes = safeBytes
        self.reviewBytes = reviewBytes
        self.reportBytes = reportBytes
        self.protectedBytes = protectedBytes
        self.tiers = tiers
    }
}
