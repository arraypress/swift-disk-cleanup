//
//  CleanupContext+Live.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Darwin
import Foundation

public extension CleanupContext {

    /// The real context, or one pointed at a fixture home.
    ///
    /// - Parameter home: A stand-in home folder. Everything is then read from
    ///   inside it, the Trash is `<home>/.Trash`, and commands are looked for
    ///   only in `<home>/bin` — the real `brew`, `xcrun` and `tmutil` are out
    ///   of reach, and `/Library/…` rules read `<home>/root/Library/…`.
    static func live(home: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> CleanupContext {
        let realHome = FileManager.default.homeDirectoryForCurrentUser
        let isFixture = home != nil
        // realpath, so /tmp/x and /private/tmp/x are one home. (Foundation's
        // resolvingSymlinksInPath goes the other way and strips /private.)
        let home = realPath(home ?? realHome)
        let os = OSBuild.parse(ProcessInfo.processInfo.operatingSystemVersionString)
        func at(_ relative: String) -> URL { home.appendingPathComponent(relative, isDirectory: true) }
        let projectNames = ["Developer", "Projects", "Code", "code", "src", "dev", "work", "repos", "GitHub", "Sites"]
        return CleanupContext(
            home: home,
            isFixture: isFixture,
            applicationFolders: isFixture ? [at("Applications")] : [
                URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), at("Applications"),
                URL(fileURLWithPath: "/opt/homebrew/Caskroom"), URL(fileURLWithPath: "/usr/local/Caskroom"),
            ],
            installerFolders: [at("Downloads"), at("Desktop")],
            projectRoots: projectNames.map(at).filter { PathProbe.isDirectory($0.path) },
            commandFolders: isFixture ? [at("bin")] : CommandLocator.standardFolders(home: home, environment: environment),
            launchFolders: isFixture ? [at("Library/LaunchAgents")] : [
                at("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons"),
            ],
            osBuild: os.build,
            osVersion: os.version,
            journal: home.appendingPathComponent("Library/Application Support/diskmaid/journal.json"),
            trashFolder: isFixture ? at(".Trash") : nil,
            environment: environment,
            lookup: SystemApplicationLookup(home: home),
            root: isFixture ? at("root") : URL(fileURLWithPath: "/")
        )
    }
}

/// The path with every symlink resolved, as the kernel sees it.
private func realPath(_ url: URL) -> URL {
    guard let resolved = realpath(url.path, nil) else { return url }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
}
