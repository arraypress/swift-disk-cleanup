//
//  DeviceSupportNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Xcode names device support folders `18.1 (22B83)` or, lately,
//  `iPhone17,1 18.1 (22B83)`. The version is the run of dots before the
//  bracket; the model prefix, when there is one, is ignored.
//

import Foundation

enum DeviceSupportNames {

    /// The OS version and build in a folder name.
    static func version(_ name: String) -> (version: String, build: String?)? {
        let pattern = /(?:^|\s)(\d+(?:\.\d+)+)(?:\s*\(([^)]+)\))?/
        guard let match = name.firstMatch(of: pattern) else { return nil }
        return (String(match.1), match.2.map(String.init))
    }

    /// The names to keep: the `keep` newest versions. Names with no
    /// readable version are always kept — not knowing is not "old".
    static func kept(_ names: [String], keep: Int) -> Set<String> {
        let versioned = names.compactMap { name in version(name).map { (name, $0.version) } }
        let distinct = Set(versioned.map(\.1)).sorted { VersionOrder.compare($0, $1) == .orderedDescending }
        let keepVersions = Set(distinct.prefix(max(keep, 0)))
        var kept = Set(names.filter { version($0) == nil })
        for (name, version) in versioned where keepVersions.contains(version) { kept.insert(name) }
        return kept
    }
}
