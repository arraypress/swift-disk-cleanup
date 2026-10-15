//
//  PathProbe.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Looking at a folder without walking it: is it there, may we read it, and
//  what is in it. Every listing in this library goes through here, so a
//  refusal is always recorded rather than read as "empty".
//

import Darwin
import Foundation

enum PathProbe {

    /// Whether `path` exists and can be listed.
    static func visibility(_ path: String) -> Visibility {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return errno == EPERM || errno == EACCES ? .notVisible : .absent
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return .visible }
        guard info.st_flags & UInt32(SF_DATALESS) == 0 else { return .visible }
        guard let directory = opendir(path) else {
            return errno == EPERM || errno == EACCES ? .notVisible : .absent
        }
        closedir(directory)
        return .visible
    }

    /// The names in a folder (no `.`/`..`), or why not. A dataless folder is
    /// reported empty without being opened.
    static func list(_ path: String) -> (names: [String], visibility: Visibility) {
        if Sizer.isDataless(path) { return ([], .visible) }
        guard let directory = opendir(path) else {
            return ([], errno == EPERM || errno == EACCES ? .notVisible : .absent)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return (names.sorted(), .visible)
    }

    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func isFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The path's own modification time.
    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }

    /// Small files only: reads at most `limit` bytes, never a placeholder.
    static func read(_ path: String, limit: Int = 4 << 20) -> Data? {
        guard isFile(path), !Sizer.isDataless(path),
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }

    /// Expands one pattern against the disk, recording where it looked.
    static func expand(_ pattern: String) -> (paths: [String], roots: [(String, Visibility)]) {
        let (base, rest) = Glob.split(pattern)
        guard !rest.isEmpty else {
            let visibility = visibility(base)
            return (visibility == .absent ? [] : [base], [(base, visibility)])
        }
        var frontier = [base]
        var roots: [(String, Visibility)] = []
        for (index, component) in rest.enumerated() {
            var next: [String] = []
            for folder in frontier {
                if Glob.hasWildcard(component) {
                    let listing = list(folder)
                    if index == 0 || listing.visibility == .notVisible { roots.append((folder, listing.visibility)) }
                    next += listing.names.filter { Glob.matches(component, $0) }.map { folder + "/" + $0 }
                } else {
                    let path = folder + "/" + component
                    if exists(path) { next.append(path) }
                }
            }
            frontier = next
        }
        return (frontier, roots)
    }
}
