//
//  Item.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One thing a rule found: a folder, a file, a simulator, a snapshot.
public struct Item: Codable, Equatable, Sendable {
    /// `<rule>-<8 hex>`, stable for the same rule and path across runs.
    public let id: String
    public let rule: String
    public let category: CleanupCategory
    public let path: String
    /// Allocated bytes; `nil` where the size cannot be known (a snapshot).
    public var bytes: Int64?
    /// `bytes` with every APFS clone counted in full; `nil` when not measured.
    public var apparentBytes: Int64?
    public var tier: Tier
    public let removal: Removal
    public let regenerable: Bool
    public let owner: String?
    /// The newest modification time inside it.
    public var newest: Date?
    public var visibility: Visibility
    /// Why it is shown but will not be cleaned, if it will not.
    public var protected: String?
    /// What the rule read to decide: bundle id, versions, marker file…
    public var evidence: [String: String]
    public let note: String?
    /// Who it was at measuring time; `nil` for things that are not files.
    public var identity: FileIdentity?
    /// Goes only when named by id, never with its category — for things where
    /// taking every one would leave none (two images of one simulator runtime).
    public var byIDOnly: Bool

    public init(id: String, rule: String, category: CleanupCategory, path: String, bytes: Int64?,
                tier: Tier, removal: Removal, regenerable: Bool, owner: String?, newest: Date?,
                visibility: Visibility, protected: String?, evidence: [String: String],
                note: String?, identity: FileIdentity?, byIDOnly: Bool = false, apparentBytes: Int64? = nil) {
        self.id = id
        self.rule = rule
        self.category = category
        self.path = path
        self.bytes = bytes
        self.apparentBytes = apparentBytes
        self.tier = tier
        self.removal = removal
        self.regenerable = regenerable
        self.owner = owner
        self.newest = newest
        self.visibility = visibility
        self.protected = protected
        self.evidence = evidence
        self.note = note
        self.identity = identity
        self.byIDOnly = byIDOnly
    }
}
