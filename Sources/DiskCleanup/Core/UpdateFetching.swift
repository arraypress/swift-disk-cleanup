//
//  UpdateFetching.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What an update check reads the network through — a stand-in in tests,
/// so they never reach a feed, the App Store or Homebrew.
public protocol UpdateFetching: Sendable {
    /// The body at a URL; throws on any failure, a non-200 included.
    func data(from url: URL) async throws -> Data
}
