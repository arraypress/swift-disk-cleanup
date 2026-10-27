//
//  UpdateSource.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where an app's newest version was learned.
public enum UpdateSource: String, Sendable, Codable, CaseIterable, Hashable {
    /// The Mac App Store's public lookup, for an app installed from it.
    case appStore = "app-store"
    /// The app's own Sparkle feed (`SUFeedURL`).
    case sparkle
    /// Homebrew's public cask catalogue, matched by the app's name.
    case homebrew
    /// Nowhere: no feed, not in the App Store, no cask.
    case none
}
