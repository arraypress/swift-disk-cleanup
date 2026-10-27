//
//  AppStackReport.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One installed app: what it is built with, the file that says so, and its size.
public struct AppStackReport: Sendable, Equatable, Codable {
    /// The app's name.
    public var name: String
    /// Its bundle id, when its Info.plist could be read.
    public var bundleID: String?
    /// Where it is.
    public var path: String
    /// Its version, as it shows it.
    public var version: String?
    /// What it is built with.
    public var stack: AppStack
    /// The file inside the app that says so — nil for native.
    public var evidence: String?
    /// The bundle's size on disk (not its data or caches).
    public var bytes: Int64
    /// The bundled runtime's own size — the copy of Chromium, Flutter, Qt or
    /// Java the app carries — when it has one.
    public var runtimeBytes: Int64?
    /// The Electron version, for an Electron app: `42.11.1`.
    public var electronVersion: String?
    /// Which processors its main binary is built for.
    public var architecture: AppArchitecture
    /// When it was last opened, as Spotlight recorded it; nil when Spotlight
    /// has no date (never opened, or not indexed).
    public var lastOpened: Date?

    /// A report.
    ///
    /// - Parameters:
    ///   - name: The app's name.
    ///   - bundleID: Its bundle id.
    ///   - path: Where it is.
    ///   - version: Its version.
    ///   - stack: What it is built with.
    ///   - evidence: The file that says so.
    ///   - bytes: The bundle's size.
    ///   - runtimeBytes: The bundled runtime's size.
    ///   - electronVersion: The Electron version.
    ///   - architecture: Which processors it is built for.
    ///   - lastOpened: When it was last opened.
    public init(name: String, bundleID: String?, path: String, version: String?, stack: AppStack, evidence: String?,
                bytes: Int64, runtimeBytes: Int64? = nil, electronVersion: String? = nil,
                architecture: AppArchitecture = .unknown, lastOpened: Date? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.version = version
        self.stack = stack
        self.evidence = evidence
        self.bytes = bytes
        self.runtimeBytes = runtimeBytes
        self.electronVersion = electronVersion
        self.architecture = architecture
        self.lastOpened = lastOpened
    }
}
