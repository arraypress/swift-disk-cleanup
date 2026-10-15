//
//  Catalogue.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The whole rule set: the rules in priority order, and what no rule may
/// ever reach.
///
/// Order matters. When two rules find the same path, or one finds a folder
/// inside another's, the earlier rule keeps it and the later one drops its
/// item — so the specific rules come first and the broad `~/Library/Caches/*`
/// sweep comes last.
public struct Catalogue: Equatable, Sendable {
    /// The catalogue's own revision.
    public let version: Int
    /// Paths and patterns that are never an item, whatever a rule says.
    public let protect: [String]
    /// Name fragments that protect any path containing them, case-insensitively:
    /// keychains, password managers, ssh and gpg.
    public let protectNames: [String]
    public let rules: [Rule]

    public init(version: Int, protect: [String], protectNames: [String], rules: [Rule]) {
        self.version = version
        self.protect = protect
        self.protectNames = protectNames
        self.rules = rules
    }
}
