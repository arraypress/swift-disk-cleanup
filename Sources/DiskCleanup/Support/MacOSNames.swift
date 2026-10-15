//
//  MacOSNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  An `Install macOS Sonoma.app` carries its own app version (19.x), not the
//  macOS version it installs, so the name is what says which release it is.
//  A name not in this table is "unknown": never guessed.
//

import Foundation

enum MacOSNames {

    static let versions: [String: String] = [
        "high sierra": "10.13", "mojave": "10.14", "catalina": "10.15", "big sur": "11",
        "monterey": "12", "ventura": "13", "sonoma": "14", "sequoia": "15", "tahoe": "26",
    ]

    /// `Install macOS Sonoma.app` → `14`.
    static func version(ofInstaller name: String) -> String? {
        let lower = name.lowercased()
        guard lower.hasPrefix("install macos") else { return nil }
        // Longest first, so "big sur" is not read as something shorter.
        for (release, version) in versions.sorted(by: { $0.key.count > $1.key.count }) where lower.contains(release) {
            return version
        }
        return nil
    }
}
