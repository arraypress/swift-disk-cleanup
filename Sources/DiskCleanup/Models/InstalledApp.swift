//
//  InstalledApp.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// An app bundle found on disk, by what its Info.plist says.
public struct InstalledApp: Codable, Equatable, Hashable, Sendable {
    public let bundleID: String
    public let path: String
    /// CFBundleShortVersionString.
    public let version: String?
    /// CFBundleVersion.
    public let build: String?
    public let name: String?

    public init(bundleID: String, path: String, version: String?, build: String?, name: String?) {
        self.bundleID = bundleID
        self.path = path
        self.version = version
        self.build = build
        self.name = name
    }
}
