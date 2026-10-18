//
//  TreeSizer.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Sizing every folder of a tree down to a depth in ONE walk per top-level
//  child, the children walked in parallel. A file counts in each folder
//  above it that is shallow enough to show, through that folder's own clone
//  tally, so each folder's size is the same Sizer would give it alone:
//  allocated blocks, hard links once, clones' shared blocks once, iCloud
//  placeholders never opened, refused folders "not visible" — never zero.
//

import Darwin
import Foundation
import os

public enum TreeSizer {

    /// One folder's running total during the walk. Built and changed by one
    /// worker only, and handed over through the lock once that walk is done.
    final class Tally: @unchecked Sendable {
        let path: String
        let level: Int
        var bytes: Int64 = 0
        var apparent: Int64 = 0
        var clones = Sizer.CloneTally()
        var visibility = Visibility.visible
        var children: [Tally] = []

        init(path: String, level: Int) {
            self.path = path
            self.level = level
        }
    }

    /// `path` and its folders `depth` levels down, sized. `progress` hears
    /// each top-level child as it finishes, and how many there are.
    public static func tree(_ path: String, depth: Int, progress: ((Int, Int) -> Void)? = nil) -> WhereNode {
        let root = Tally(path: PathText.normalised(path), level: 0)
        var info = stat()
        guard lstat(root.path, &info) == 0 else {
            return WhereNode(path: root.path, bytes: nil, apparentBytes: nil, visibility: errno == EPERM || errno == EACCES ? .notVisible : .absent)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            let measured = Sizer.measure(root.path)
            return WhereNode(path: root.path, bytes: measured.bytes, apparentBytes: measured.apparentBytes, visibility: measured.visibility)
        }
        let listing = PathProbe.list(root.path)
        guard listing.visibility == .visible else {
            return WhereNode(path: root.path, bytes: nil, apparentBytes: nil, visibility: listing.visibility)
        }
        let children = listing.names.map { root.path == "/" ? "/" + $0 : root.path + "/" + $0 }
        let done = OSAllocatedUnfairLock(initialState: 0)
        let walked = OSAllocatedUnfairLock(initialState: [Int: Tally]())
        DispatchQueue.concurrentPerform(iterations: children.count) { index in
            let tally = walk(children[index], depth: depth - 1)
            walked.withLock { $0[index] = tally }
            let count = done.withLock { $0 += 1; return $0 }
            progress?(count, children.count)
        }
        root.children = walked.withLock { $0 }.sorted { $0.key < $1.key }.map(\.value)
        root.bytes = Int64(info.st_blocks) * 512 + root.children.reduce(0) { $0 + $1.bytes }
        root.apparent = Int64(info.st_blocks) * 512 + root.children.reduce(0) { $0 + $1.apparent }
        if root.children.contains(where: { $0.visibility != .visible }) { root.visibility = .partial }
        return node(root)
    }

    /// One top-level child, walked once, with a tally for each folder at most
    /// `depth` levels below it.
    static func walk(_ path: String, depth: Int) -> Tally {
        let top = Tally(path: path, level: 0)
        let copy = strdup(path)
        defer { free(copy) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [copy, nil]
        guard let stream = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            top.visibility = .notVisible
            return top
        }
        defer { fts_close(stream) }
        var stack: [Tally] = []
        var linked = Set<UInt64>()
        while let entry = fts_read(stream) {
            let kind = Int32(entry.pointee.fts_info)
            let level = Int(entry.pointee.fts_level)
            switch kind {
            case FTS_DP:
                if let last = stack.last, last.level == level { stack.removeLast() }
                continue
            case FTS_DNR, FTS_ERR, FTS_NS:
                let error = entry.pointee.fts_errno
                let refused = error == EPERM || error == EACCES
                if level == 0 {
                    top.visibility = refused ? .notVisible : .absent
                    return top
                }
                // fts may have reported the folder already, opening its tally,
                // and sends no post-order entry for one it could not read.
                let path = String(cString: entry.pointee.fts_path)
                if let open = stack.last, open.path == path {
                    stack.removeLast()
                    if refused {
                        open.visibility = .notVisible
                    } else {
                        open.visibility = .partial
                    }
                } else if kind == FTS_DNR, level <= depth, refused {
                    let tally = Tally(path: path, level: level)
                    tally.visibility = .notVisible
                    stack.last?.children.append(tally)
                }
                for tally in stack { tally.visibility = .partial }
                continue
            default:
                break
            }
            guard let stat = entry.pointee.fts_statp?.pointee else { continue }
            if stat.st_flags & UInt32(SF_DATALESS) != 0 {
                if kind == FTS_D { fts_set(stream, entry, FTS_SKIP) }
                continue
            }
            let allocated = Int64(stat.st_blocks) * 512
            if kind == FTS_D {
                let tally = level == 0 ? top : Tally(path: String(cString: entry.pointee.fts_path), level: level)
                for open in stack {
                    open.bytes += allocated
                    open.apparent += allocated
                }
                if level <= depth {
                    if level > 0 { stack.last?.children.append(tally) }
                    tally.bytes += allocated
                    tally.apparent += allocated
                    stack.append(tally)
                }
                continue
            }
            if stat.st_nlink > 1 {
                guard linked.insert(UInt64(stat.st_ino)).inserted else { continue }
            }
            let clone = kind == FTS_F && allocated >= Sizer.cloneFloor ? Sizer.cloneShare(entry.pointee.fts_accpath) : nil
            if stack.isEmpty {
                // The top-level child is itself a file or a link.
                top.bytes += allocated
                top.apparent += allocated
                continue
            }
            for open in stack {
                open.bytes += open.clones.add(clone, allocated: allocated)
                open.apparent += allocated
            }
        }
        return top
    }

    static func node(_ tally: Tally) -> WhereNode {
        let hidden = tally.visibility == .notVisible
        return WhereNode(path: tally.path, bytes: hidden ? nil : tally.bytes, apparentBytes: hidden ? nil : tally.apparent,
                         visibility: tally.visibility, children: tally.children.map(node))
    }
}
