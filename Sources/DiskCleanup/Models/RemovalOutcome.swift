//
//  RemovalOutcome.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What happened to one planned item.
public struct RemovalOutcome: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        /// Moved to the Trash and journalled.
        case trashed
        /// Unlinked.
        case deleted
        /// The owning tool's command ran and succeeded.
        case commanded
        /// A setting changed (the Dock's icons), the original journalled for undo.
        case edited
        /// Not touched, on purpose (changed since planning, protected, gone).
        case skipped
        /// Tried and failed.
        case failed
    }

    public let id: String
    public let path: String
    public let result: Result
    /// The Trash path, or the command that ran.
    public let to: String?
    /// Bytes given back — "up to", since APFS clones share blocks. For the
    /// Trash, nothing is freed until it is emptied.
    public let bytes: Int64?
    public let reason: String?

    public init(id: String, path: String, result: Result, to: String? = nil, bytes: Int64? = nil, reason: String? = nil) {
        self.id = id
        self.path = path
        self.result = result
        self.to = to
        self.bytes = bytes
        self.reason = reason
    }
}
