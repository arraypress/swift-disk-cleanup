//
//  AppUpdate.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One app's update check.
public struct AppUpdate: Sendable, Equatable, Codable {
    /// The app's name.
    public var name: String
    /// Its bundle id.
    public var bundleID: String
    /// Where it is.
    public var path: String
    /// The version installed, as the app itself says (never Homebrew's
    /// record of it, which goes stale when an app updates itself).
    public var installed: String?
    /// The newest version known.
    public var latest: String?
    /// Where the newest version was learned.
    public var source: UpdateSource
    /// Whether it is out of date.
    public var status: UpdateStatus
    /// How to update it, or why nothing could say.
    public var detail: String

    /// A check.
    ///
    /// - Parameters:
    ///   - name: The app's name.
    ///   - bundleID: Its bundle id.
    ///   - path: Where it is.
    ///   - installed: The version installed.
    ///   - latest: The newest version known.
    ///   - source: Where that was learned.
    ///   - status: Whether it is out of date.
    ///   - detail: How to update it, or why nothing could say.
    public init(name: String, bundleID: String, path: String, installed: String?, latest: String?,
                source: UpdateSource, status: UpdateStatus, detail: String) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.installed = installed
        self.latest = latest
        self.source = source
        self.status = status
        self.detail = detail
    }
}
