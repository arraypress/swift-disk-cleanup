//
//  BundleIDs.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Deciding whether a folder named like a bundle id belongs to nothing. The
//  match is EXACT, then widened only in the direction of keeping: anything
//  sharing a vendor prefix with an installed app counts as that vendor's.
//

import Foundation

enum BundleIDs {

    /// Reverse-DNS, three parts or more, the characters a bundle id may use.
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// Apple's own ids: system services have no app to find, so they would
    /// all look orphaned.
    static func isApple(_ id: String) -> Bool {
        id.lowercased().hasPrefix("com.apple.")
    }

    /// The first two parts, lower-cased: `com.google`.
    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Whether `id` is, or shares a vendor with, any id in `known`.
    static func isRelated(_ id: String, to known: Set<String>, vendors: Set<String>) -> Bool {
        known.contains(id.lowercased()) || vendors.contains(vendor(id))
    }

    /// A group container's name without its team or `group.` prefix:
    /// `ABCDE12345.com.x.shared` → `com.x.shared`.
    static func groupBase(_ name: String) -> String {
        var name = name
        if let first = name.split(separator: ".").first, first.count == 10,
           first.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            name = String(name.dropFirst(first.count + 1))
        }
        if name.lowercased().hasPrefix("group.") { name = String(name.dropFirst(6)) }
        return name
    }
}
