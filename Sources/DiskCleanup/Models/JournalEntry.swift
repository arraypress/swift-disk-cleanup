//
//  JournalEntry.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One move to the Trash, remembered so it can be put back.
public struct JournalEntry: Codable, Equatable, Sendable {
    /// Unique per entry.
    public let id: String
    /// The `clean` run it belonged to; `undo --last` restores a whole batch.
    public let batch: String
    public let original: String
    /// Where the Trash put it (it may have been renamed on the way in).
    public let trashed: String
    public let at: Date
    public let bytes: Int64?
    public let rule: String
    /// Set once `undo` has put it back.
    public var restoredAt: Date?

    public init(id: String, batch: String, original: String, trashed: String, at: Date,
                bytes: Int64?, rule: String, restoredAt: Date? = nil) {
        self.id = id
        self.batch = batch
        self.original = original
        self.trashed = trashed
        self.at = at
        self.bytes = bytes
        self.rule = rule
        self.restoredAt = restoredAt
    }
}
