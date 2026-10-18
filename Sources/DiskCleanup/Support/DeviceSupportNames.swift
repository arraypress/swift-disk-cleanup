//
//  DeviceSupportNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Xcode names device support folders `18.1 (22B83)` or, lately,
//  `iPhone17,1 18.1 (22B83)` — one per device model, and one per build: a
//  beta, its release and a point fix can all say 27.0. So the newest is
//  judged by version, then build, and kept per model. A folder with no
//  model is the old layout, and anything newer on the platform supersedes it.
//

import Foundation

enum DeviceSupportNames {

    /// The OS version and build in a folder name.
    static func version(_ name: String) -> (version: String, build: String?)? {
        let pattern = /(?:^|\s)(\d+(?:\.\d+)+)(?:\s*\(([^)]+)\))?/
        guard let match = name.firstMatch(of: pattern) else { return nil }
        return (String(match.1), match.2.map(String.init))
    }

    /// The device model a folder name starts with (`iPhone17,1`), if any.
    static func model(_ name: String) -> String? {
        name.firstMatch(of: /^([A-Za-z]+\d+,\d+)\s/).map { String($0.1) }
    }

    /// Orders two builds of one version: `24A437` after `24A435`, and a beta
    /// (`24A5430a`, four digits and a letter) before any release of its train.
    /// `nil` when either is missing or not shaped like a build.
    static func compareBuilds(_ a: String?, _ b: String?) -> ComparisonResult? {
        let pattern = /^(\d+)([A-Z])(\d+)([a-z]?)$/
        guard let a, let b, let left = a.wholeMatch(of: pattern), let right = b.wholeMatch(of: pattern),
              let leftMajor = Int(left.1), let rightMajor = Int(right.1),
              let leftNumber = Int(left.3), let rightNumber = Int(right.3) else { return nil }
        if leftMajor != rightMajor { return leftMajor < rightMajor ? .orderedAscending : .orderedDescending }
        if left.2 != right.2 { return left.2 < right.2 ? .orderedAscending : .orderedDescending }
        let leftBeta = !left.4.isEmpty, rightBeta = !right.4.isEmpty
        if leftBeta != rightBeta { return leftBeta ? .orderedAscending : .orderedDescending }
        if leftNumber != rightNumber { return leftNumber < rightNumber ? .orderedAscending : .orderedDescending }
        return left.4 == right.4 ? .orderedSame : (left.4 < right.4 ? .orderedAscending : .orderedDescending)
    }

    /// Orders two folder names by version, then build. Builds that cannot be
    /// read leave equal versions equal, so both are kept.
    static func compare(_ a: (version: String, build: String?), _ b: (version: String, build: String?)) -> ComparisonResult {
        let byVersion = VersionOrder.compare(a.version, b.version) ?? .orderedSame
        return byVersion != .orderedSame ? byVersion : compareBuilds(a.build, b.build) ?? .orderedSame
    }

    /// The names to keep: the `keep` newest per device model, and a folder
    /// with no model only while it is among the newest on the platform.
    /// Names with no readable version are always kept — not knowing is not
    /// "old".
    static func kept(_ names: [String], keep: Int) -> Set<String> {
        let versioned = names.compactMap { name in version(name).map { (name: name, version: $0) } }
        func newest(_ group: [(name: String, version: (version: String, build: String?))]) -> [String] {
            var distinct: [(version: String, build: String?)] = []
            for entry in group.map(\.version) where !distinct.contains(where: { compare($0, entry) == .orderedSame }) {
                distinct.append(entry)
            }
            distinct.sort { compare($0, $1) == .orderedDescending }
            guard keep > 0, !distinct.isEmpty else { return [] }
            let cutoff = distinct[min(keep, distinct.count) - 1]
            return group.filter { compare($0.version, cutoff) != .orderedAscending }.map(\.name)
        }
        var kept = Set(names.filter { version($0) == nil })
        let platformNewest = Set(newest(versioned))
        for name in versioned.map(\.name) where model(name) == nil && platformNewest.contains(name) { kept.insert(name) }
        let modelled = versioned.compactMap { entry in model(entry.name).map { (model: $0, entry: entry) } }
        for group in Dictionary(grouping: modelled, by: \.model).values { kept.formUnion(newest(group.map(\.entry))) }
        return kept
    }
}
