//
//  DetectorResult.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One rule's findings, and how well it could see.
struct DetectorResult: Sendable {
    var candidates: [Candidate] = []
    /// The places it looked, and whether each could be looked at.
    var roots: [(path: String, visibility: Visibility)] = []
    var notes: [String] = []
}
