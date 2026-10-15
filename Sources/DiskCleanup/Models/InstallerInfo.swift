//
//  InstallerInfo.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What was read out of one installer, and the verdict.
public struct InstallerInfo: Codable, Equatable, Sendable {
    public let path: String
    public let kind: InstallerKind
    public var bundleID: String?
    public var name: String?
    /// The version the installer would put down.
    public var version: String?
    public var build: String?
    /// Package receipts it would write, for a pkg with no app inside.
    public var packageIDs: [String]
    public var installedPath: String?
    public var installedVersion: String?
    public var verdict: InstallerVerdict
    /// Why, in a few words.
    public var reason: String

    public init(path: String, kind: InstallerKind, bundleID: String? = nil, name: String? = nil,
                version: String? = nil, build: String? = nil, packageIDs: [String] = [],
                installedPath: String? = nil, installedVersion: String? = nil,
                verdict: InstallerVerdict, reason: String) {
        self.path = path
        self.kind = kind
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
        self.packageIDs = packageIDs
        self.installedPath = installedPath
        self.installedVersion = installedVersion
        self.verdict = verdict
        self.reason = reason
    }
}
