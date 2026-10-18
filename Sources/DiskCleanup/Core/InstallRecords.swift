//
//  InstallRecords.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  What uninstalling asks the system beyond "is this app installed":
//  installer receipts, code signatures, launchd and running apps. A
//  protocol so tests stand in for pkgutil, codesign and launchctl.
//

import AppKit
import Darwin
import Foundation

public protocol InstallRecords: Sendable {
    /// Every installer receipt id, or `nil` when pkgutil did not answer.
    func packageIDs() -> [String]?
    /// One receipt with every path it lists.
    func receipt(_ id: String) -> PackageReceipt?
    /// The receipts that list `path` (on the startup disk), whether or not
    /// it is still there; `nil` when pkgutil did not answer.
    func owners(of path: String) -> [String]?
    /// The folder holding a receipt's .plist and .bom: /var/db/receipts, or
    /// SIP-restricted /Library/Apple/System/Library/Receipts, where
    /// `pkgutil --forget` reports success and changes nothing.
    func receiptStore(_ id: String) -> String?
    /// The team id an app is signed with, if any.
    func teamID(appAt path: String) -> String?
    /// Asks a running app to quit and waits for it. Whether it is gone.
    func quit(_ bundleID: String) -> Bool
    /// Unloads a launch agent from this user's own launchd domain.
    func bootout(label: String) -> Bool
}

/// pkgutil, codesign, launchctl and NSRunningApplication, for real.
///
/// Pointed at a fixture's `<home>/bin` it runs only what is there and never
/// quits an app, so a test cannot read this Mac's receipts or close its apps.
public struct SystemInstallRecords: InstallRecords {

    /// `nil` for the system's own tools.
    let fixtureBin: String?

    public init(fixtureBin: URL? = nil) {
        self.fixtureBin = fixtureBin?.path
    }

    func tool(_ name: String, system: String) -> String? {
        let path = fixtureBin.map { $0 + "/" + name } ?? system
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    public func packageIDs() -> [String]? {
        guard let pkgutil = tool("pkgutil", system: "/usr/sbin/pkgutil"),
              let output = CommandRunner.run(pkgutil, ["--pkgs"], timeout: 60), output.succeeded else { return nil }
        return output.text.split(whereSeparator: \.isNewline).map(String.init)
    }

    public func receipt(_ id: String) -> PackageReceipt? {
        guard let pkgutil = tool("pkgutil", system: "/usr/sbin/pkgutil"),
              let info = CommandRunner.run(pkgutil, ["--pkg-info", id], timeout: 60), info.succeeded,
              let files = CommandRunner.run(pkgutil, ["--files", id], timeout: 120), files.succeeded else { return nil }
        return UninstallMatch.receipt(id: id, info: info.text, files: files.text)
    }

    public func owners(of path: String) -> [String]? {
        guard let pkgutil = tool("pkgutil", system: "/usr/sbin/pkgutil"),
              let output = CommandRunner.run(pkgutil, ["--file-info", path], timeout: 60), output.succeeded else { return nil }
        return UninstallMatch.owners(fromFileInfo: output.text)
    }

    public func receiptStore(_ id: String) -> String? {
        guard fixtureBin == nil else { return nil }
        return [UninstallMatch.systemReceipts, "/var/db/receipts"].first { folder in
            FileManager.default.fileExists(atPath: folder + "/" + id + ".plist") || FileManager.default.fileExists(atPath: folder + "/" + id + ".bom")
        }
    }

    public func teamID(appAt path: String) -> String? {
        guard let codesign = tool("codesign", system: "/usr/bin/codesign"),
              let output = CommandRunner.run(codesign, ["-dv", "--verbose=2", path], timeout: 30) else { return nil }
        return UninstallMatch.teamID(fromCodesign: output.errorText + "\n" + output.text)
    }

    public func quit(_ bundleID: String) -> Bool {
        guard fixtureBin == nil else { return false }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        apps.forEach { $0.terminate() }
        for _ in 0..<40 where apps.contains(where: { !$0.isTerminated }) {
            usleep(250_000)
        }
        return apps.allSatisfy(\.isTerminated)
    }

    public func bootout(label: String) -> Bool {
        guard let launchctl = tool("launchctl", system: "/bin/launchctl"),
              let output = CommandRunner.run(launchctl, ["bootout", "gui/\(getuid())/\(label)"], timeout: 30) else { return false }
        // 3 is "no such process": it was not loaded, which is what was wanted.
        return output.succeeded || output.status == 3
    }
}
