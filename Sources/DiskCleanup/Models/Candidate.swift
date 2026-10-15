//
//  Candidate.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a detector hands the scanner before measuring: a path and what it
/// learned about it.
struct Candidate: Sendable {
    let path: String
    var evidence: [String: String] = [:]
    /// A tier other than the rule's (a kept-newest device support folder is
    /// still safe tier, but an available simulator is report).
    var tier: Tier?
    var protected: String?
    /// Known already (simctl, brew); otherwise the path is measured.
    var bytes: Int64?
    /// Set when `bytes` is known and the path must not be walked.
    var skipMeasure = false
    /// The item is not a file (a snapshot, a runtime image).
    var isVirtual = false
    /// Check git before cleaning (build folders).
    var checkGit = false
    /// Never taken by a category clean, only by id.
    var byIDOnly = false
}
