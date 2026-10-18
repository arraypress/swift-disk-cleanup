//
//  PathText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Path arithmetic on strings, with no disk access.
//

import Foundation

enum PathText {

    /// `~/x` → `<home>/x`; anything else unchanged.
    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    /// The path's components, without empty ones.
    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// The path without a trailing slash (and `/` stays `/`).
    static func normalised(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Whether `path` is `base` or lies inside it.
    static func isWithin(_ path: String, _ base: String) -> Bool {
        let path = normalised(path), base = normalised(base)
        if path == base { return true }
        if base == "/" { return true }
        return path.hasPrefix(base + "/")
    }

    /// Whether either path lies within the other.
    static func overlaps(_ a: String, _ b: String) -> Bool {
        isWithin(a, b) || isWithin(b, a)
    }

    /// `~/…` for paths in the home folder, for showing a person.
    static func abbreviated(_ path: String, home: String) -> String {
        isWithin(path, home) && path != home ? "~" + path.dropFirst(normalised(home).count) : path
    }

    /// Single-quoted for a shell: `it's` → `'it'\''s'`.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func lastComponent(_ path: String) -> String {
        components(path).last ?? path
    }

    static func parent(_ path: String) -> String {
        let parts = components(path)
        guard parts.count > 1 else { return "/" }
        return "/" + parts.dropLast().joined(separator: "/")
    }
}
