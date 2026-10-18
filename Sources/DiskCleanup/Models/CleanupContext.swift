//
//  CleanupContext.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where a scan looks and what it may run: the home folder, the app folders
/// that answer "is it installed", where the owning tools' commands are found,
/// the Trash and the undo journal.
///
/// ``CleanupContext/live(home:)`` builds the real one. Pointed at a fixture
/// home it changes four things on purpose: app folders, launch agents and the
/// Trash all come from inside that home, and commands are looked for ONLY in
/// `<home>/bin` — so a test can never run the real `brew cleanup` or
/// `simctl delete` against this Mac.
public struct CleanupContext: Sendable {
    public var home: URL
    /// Whether `home` is a stand-in rather than the user's own.
    public var isFixture: Bool
    /// Where installed apps are looked for, besides LaunchServices.
    public var applicationFolders: [URL]
    /// Where `installers` looks by default.
    public var installerFolders: [URL]
    /// Where build folders are looked for by default.
    public var projectRoots: [URL]
    /// Where the owning tools' commands are looked for, in order.
    public var commandFolders: [URL]
    /// Launch agent and daemon folders, read for leftover checks.
    public var launchFolders: [URL]
    /// Where the catalogue's absolute paths (`/Library/…`) are read: `/`, or
    /// `<home>/root` for a fixture, so a test never reads this Mac's own.
    public var root: URL
    /// The running OS's build (`26A428`), for Core AI's cache.
    public var osBuild: String?
    /// The running OS's version (`27.0`), for macOS installers.
    public var osVersion: String?
    /// The undo journal.
    public var journal: URL
    /// Where trashed items go: `nil` is the system Trash.
    public var trashFolder: URL?
    /// Environment overrides for caches that move (`HF_HUB_CACHE`, `UV_CACHE_DIR`).
    public var environment: [String: String]
    public var lookup: any ApplicationLookup
    /// Installer receipts, signatures, launchd and quitting, for `uninstall`.
    public var records: any InstallRecords
    public var now: Date

    public init(home: URL, isFixture: Bool, applicationFolders: [URL], installerFolders: [URL],
                projectRoots: [URL], commandFolders: [URL], launchFolders: [URL], osBuild: String?,
                osVersion: String?, journal: URL, trashFolder: URL?, environment: [String: String],
                lookup: any ApplicationLookup, records: any InstallRecords = SystemInstallRecords(),
                root: URL = URL(fileURLWithPath: "/"), now: Date = Date()) {
        self.home = home
        self.isFixture = isFixture
        self.applicationFolders = applicationFolders
        self.installerFolders = installerFolders
        self.projectRoots = projectRoots
        self.commandFolders = commandFolders
        self.launchFolders = launchFolders
        self.root = root
        self.osBuild = osBuild
        self.osVersion = osVersion
        self.journal = journal
        self.trashFolder = trashFolder
        self.environment = environment
        self.lookup = lookup
        self.records = records
        self.now = now
    }
}
