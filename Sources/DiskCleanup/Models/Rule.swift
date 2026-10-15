//
//  Rule.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One entry of the rule catalogue: where something lives, who owns it,
/// whether it rebuilds itself, and how it may leave.
///
/// Read strictly — a key the catalogue does not know is refused, so a typo
/// (`minAgeDay`) fails the build's tests instead of silently meaning "no age
/// gate". Paths start `~/` for the home folder being scanned.
public struct Rule: Equatable, Sendable {
    /// A kebab-case name, unique in the catalogue. Item ids start with it.
    public let id: String
    public let category: CleanupCategory
    /// Literal paths. With a `marker`, folder names beside the marker file.
    public let paths: [String]
    /// Shell-style patterns (`*`, `?`, `[…]`), one path component at a time.
    public let globs: [String]
    /// Files whose presence makes `paths` beside them build output
    /// (`Package.swift` → `.build`). Patterns allowed (`*.csproj`).
    public let marker: [String]
    /// The logic that turns the paths into items.
    public let detector: Detector
    /// The app or tool the data belongs to.
    public let owner: String?
    /// Whether it comes back by itself when needed.
    public let regenerable: Bool
    public let tier: Tier
    public let removal: Removal
    /// Items touched more recently than this are protected.
    public let minAgeDays: Int?
    /// Names or patterns under this rule's paths that must never be items.
    public let protect: [String]
    /// For device support: how many of the newest per platform to keep.
    public let keepNewest: Int?
    /// One line for a person: what it is and what losing it costs.
    public let note: String?

    public init(id: String, category: CleanupCategory, paths: [String] = [], globs: [String] = [],
                marker: [String] = [], detector: Detector = .paths, owner: String? = nil,
                regenerable: Bool, tier: Tier, removal: Removal, minAgeDays: Int? = nil,
                protect: [String] = [], keepNewest: Int? = nil, note: String? = nil) {
        self.id = id
        self.category = category
        self.paths = paths
        self.globs = globs
        self.marker = marker
        self.detector = detector
        self.owner = owner
        self.regenerable = regenerable
        self.tier = tier
        self.removal = removal
        self.minAgeDays = minAgeDays
        self.protect = protect
        self.keepNewest = keepNewest
        self.note = note
    }
}
