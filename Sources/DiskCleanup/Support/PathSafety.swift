//
//  PathSafety.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The places no rule may ever reach, checked when an item is found AND again
//  just before it is removed. A catalogue mistake cannot get past this: the
//  list of system paths is code, not data.
//

import Foundation

enum PathSafety {

    /// System locations: SIP, the per-user temporary folders, keychains and
    /// launchd's own folders.
    static let systemPaths = [
        "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
        "/private/var/folders", "/var/folders", "/private/var/db", "/var/db", "/private/etc", "/etc",
        "/Library/Keychains", "/Library/Apple", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/Security", "/Library/SystemExtensions", "/Library/StagedExtensions", "/cores",
    ]

    /// Why `path` must never be removed, or `nil` when it may be.
    static func reason(for path: String, catalogue: Catalogue, home: String) -> String? {
        let path = PathText.normalised(path)
        guard path.hasPrefix("/") else { return "not an absolute path" }
        if PathText.components(path).contains("..") { return "a path with .. in it" }
        // The home folder itself, or anything above it, is never an item.
        if PathText.isWithin(home, path) { return "the home folder or above it" }
        if PathText.components(path).count < 2 { return "a top-level folder" }
        for system in systemPaths where PathText.isWithin(path, system) {
            return "a system location (\(system))"
        }
        for entry in catalogue.protect {
            let protected = PathText.expand(entry, home: home)
            if PathText.overlaps(path, protected) {
                return "protected (\(entry))"
            }
        }
        let lowered = PathText.components(path).map { $0.lowercased() }
        for fragment in catalogue.protectNames {
            let fragment = fragment.lowercased()
            if lowered.contains(where: { $0.contains(fragment) }) {
                return "protected name (\(fragment))"
            }
        }
        return nil
    }
}
