//
//  DockPreferences.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Where the Dock keeps its icons — com.apple.dock's `persistent-apps` and
//  `recent-apps` — read and written through cfprefsd, never by editing the
//  plist file under it (cfprefsd holds its own copy and would write it
//  back). A protocol so tests stand in for the Dock.
//

import AppKit
import CoreFoundation
import Foundation

public protocol DockPreferences: Sendable {
    /// The Dock's value for `key`, as a property list; `nil` when it has none.
    func value(_ key: String) -> Any?
    /// Writes `key` (`nil` removes it) and syncs. Whether it was stored.
    func set(_ key: String, _ value: Any?) -> Bool
    /// Restarts the Dock so it reads its preferences again. Whether it came back.
    func restart() -> Bool
}

/// The real Dock: CFPreferences on `com.apple.dock`, and `killall Dock`
/// (launchd starts it again at once).
public struct SystemDockPreferences: DockPreferences {

    static var domain: CFString { "com.apple.dock" as CFString }

    public init() {}

    public func value(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(Self.domain)
        return CFPreferencesCopyAppValue(key as CFString, Self.domain)
    }

    public func set(_ key: String, _ value: Any?) -> Bool {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, Self.domain)
        return CFPreferencesAppSynchronize(Self.domain)
    }

    public func restart() -> Bool {
        let before = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier))
        guard let output = CommandRunner.run("/usr/bin/killall", ["Dock"], timeout: 15), output.succeeded || before.isEmpty else { return false }
        // Back once a new Dock process runs, then a moment for it to read its icons.
        for _ in 0..<40 {
            usleep(250_000)
            let now = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier)
            if now.contains(where: { !before.contains($0) }) {
                usleep(1_000_000)
                return true
            }
        }
        return false
    }
}

/// A fixture's Dock: a plain plist file no cfprefsd knows about, and a
/// restart that runs `<home>/bin/killall Dock` only if a test put one there.
public struct FileDockPreferences: DockPreferences {

    let file: URL
    let killall: URL?

    public init(file: URL, killall: URL? = nil) {
        self.file = file
        self.killall = killall
    }

    func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return plist
    }

    public func value(_ key: String) -> Any? { load()[key] }

    public func set(_ key: String, _ value: Any?) -> Bool {
        var plist = load()
        plist[key] = value
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func restart() -> Bool {
        guard let killall, FileManager.default.isExecutableFile(atPath: killall.path) else { return true }
        return CommandRunner.run(killall.path, ["Dock"], timeout: 15)?.succeeded == true
    }
}
