//
//  CommandLocator.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum CommandLocator {

    /// The first executable called `name` in the context's command folders.
    static func find(_ name: String, in context: CleanupContext) -> String? {
        guard !name.contains("/") else { return nil }
        for folder in context.commandFolders {
            let path = folder.appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// The command folders for a real home: PATH, then the usual installers' bins.
    static func standardFolders(home: URL, environment: [String: String]) -> [URL] {
        var seen = Set<String>()
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let usual = ["/opt/homebrew/bin", "/usr/local/bin", home.path + "/.local/bin",
                     home.path + "/.cargo/bin", home.path + "/.bun/bin", "/usr/bin", "/bin"]
        return (fromPath + usual).filter { $0.hasPrefix("/") && seen.insert($0).inserted }.map { URL(fileURLWithPath: $0) }
    }
}
