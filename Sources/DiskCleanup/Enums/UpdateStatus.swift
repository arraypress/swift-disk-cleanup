//
//  UpdateStatus.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Whether an app is out of date.
public enum UpdateStatus: String, Sendable, Codable, CaseIterable, Hashable {
    /// A newer version exists.
    case available
    /// The installed version is the newest known.
    case current
    /// Nothing could say — no source, a source that did not answer, or
    /// versions that cannot be ordered. Never read as "up to date".
    case unknown
}
