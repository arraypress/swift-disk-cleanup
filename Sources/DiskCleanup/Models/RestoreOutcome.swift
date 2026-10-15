//
//  RestoreOutcome.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What `undo` did with one journal entry.
public struct RestoreOutcome: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case restored
        /// Already put back by an earlier undo.
        case alreadyRestored = "already-restored"
        /// The Trash was emptied, or the item was moved out of it.
        case gone
        /// Something now sits at the original path; nothing was overwritten.
        case occupied
        case failed
    }

    public let entry: String
    public let original: String
    public let result: Result
    public let reason: String?

    public init(entry: String, original: String, result: Result, reason: String? = nil) {
        self.entry = entry
        self.original = original
        self.result = result
        self.reason = reason
    }
}
