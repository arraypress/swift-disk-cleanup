//
//  ApplicationLookup.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import AppKit
import Foundation

/// Asking the system about apps. A protocol so tests can stand in for
/// LaunchServices and Spotlight without the real machine's answers.
public protocol ApplicationLookup: Sendable {
    /// What LaunchServices knows by this bundle id.
    func launchServices(_ bundleID: String) -> AppAnswer
    /// What Spotlight knows by this bundle id; a timeout is `.noAnswer`.
    func spotlight(_ bundleID: String) -> AppAnswer
    /// The bundle ids of the apps running now.
    func runningBundleIDs() -> Set<String>
}

/// LaunchServices, Spotlight and NSWorkspace, for real.
public struct SystemApplicationLookup: ApplicationLookup {

    /// Paths whose apps do not count as installed: the Trash, mounted
    /// volumes, and the private mount points the installer reader uses.
    public let ignoredPrefixes: [String]

    public init(home: URL) {
        ignoredPrefixes = [home.path + "/.Trash", "/Volumes", NSTemporaryDirectory(), "/private/var/folders"]
    }

    public func launchServices(_ bundleID: String) -> AppAnswer {
        let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            .filter { url in !ignoredPrefixes.contains { url.path.hasPrefix($0) } }
        let apps = urls.compactMap { AppIndex.read(appAt: $0.path) }
        return apps.isEmpty ? .notInstalled : .installed(apps)
    }

    public func spotlight(_ bundleID: String) -> AppAnswer {
        guard BundleIDs.looksLikeBundleID(bundleID) else { return .noAnswer("not a bundle id") }
        guard let output = CommandRunner.run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '\(bundleID)'"], timeout: 8) else {
            return .noAnswer("mdfind did not start")
        }
        guard !output.timedOut else { return .noAnswer("Spotlight timed out") }
        guard output.status == 0 else { return .noAnswer("Spotlight failed: \(output.errorText)") }
        let paths = output.text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { path in !ignoredPrefixes.contains { path.hasPrefix($0) } }
        guard !paths.isEmpty else { return .notInstalled }
        let apps = paths.compactMap { AppIndex.read(appAt: $0) }
        // Spotlight found something by that id that is not a readable app:
        // still a "yes", because a yes is what keeps data.
        return .installed(apps.isEmpty ? [InstalledApp(bundleID: bundleID, path: paths[0], version: nil, build: nil, name: nil)] : apps)
    }

    public func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }
}
