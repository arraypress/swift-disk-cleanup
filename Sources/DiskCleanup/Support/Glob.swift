//
//  Glob.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Shell-style patterns, one path component at a time. `*` never matches a
//  leading dot, so `~/Library/Caches/*` does not sweep up `.DS_Store`.
//

import Darwin
import Foundation

enum Glob {

    /// Whether a component holds a wildcard.
    static func hasWildcard(_ component: String) -> Bool {
        component.contains { "*?[".contains($0) }
    }

    /// Whether `name` matches `pattern` (one component).
    static func matches(_ pattern: String, _ name: String) -> Bool {
        guard hasWildcard(pattern) else { return pattern == name }
        return fnmatch(pattern, name, FNM_PERIOD) == 0
    }

    /// Whether a whole path matches a whole pattern, component by component.
    static func matchesPath(_ pattern: String, _ path: String) -> Bool {
        let patternParts = PathText.components(pattern)
        let pathParts = PathText.components(path)
        guard patternParts.count == pathParts.count else { return false }
        return zip(patternParts, pathParts).allSatisfy { matches($0, $1) }
    }

    /// The part of a pattern before its first wildcard, and the rest.
    ///
    /// `/u/Library/Caches/*/Cache` → (`/u/Library/Caches`, [`*`, `Cache`]).
    static func split(_ pattern: String) -> (base: String, rest: [String]) {
        let parts = PathText.components(pattern)
        guard let first = parts.firstIndex(where: hasWildcard) else {
            return (pattern, [])
        }
        let base = "/" + parts[..<first].joined(separator: "/")
        return (base, Array(parts[first...]))
    }
}
