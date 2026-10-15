//
//  Sizer.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Measuring without opening anything. fts walks the tree reading only
//  directory entries and stat results, so:
//
//  - the size is ALLOCATED blocks (st_blocks × 512), not logical length;
//  - a file with several hard links counts once per walk;
//  - an iCloud placeholder (SF_DATALESS) is counted as zero and, if it is a
//    folder, never listed — listing a dataless folder downloads it;
//  - a folder macOS refuses is counted as unreadable, which makes the result
//    `partial` or `notVisible`, never a confident zero.
//

import Darwin
import Foundation

public enum Sizer {

    /// Walks `path` and adds up what it holds.
    public static func measure(_ path: String) -> Measurement {
        var info = stat()
        if lstat(path, &info) != 0 {
            let error = errno
            return Measurement(visibility: error == EPERM || error == EACCES ? .notVisible : .absent)
        }
        var result = Measurement(visibility: .visible)
        var linked = Set<UInt64>()
        let pathCopy = strdup(path)
        defer { free(pathCopy) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [pathCopy, nil]
        guard let stream = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            return Measurement(visibility: .notVisible)
        }
        defer { fts_close(stream) }
        while let entry = fts_read(stream) {
            let kind = Int32(entry.pointee.fts_info)
            let isRoot = entry.pointee.fts_level == FTS_ROOTLEVEL
            switch kind {
            case FTS_DP:
                continue
            case FTS_DNR, FTS_ERR, FTS_NS:
                let error = entry.pointee.fts_errno
                if isRoot && (error == EPERM || error == EACCES) {
                    return Measurement(visibility: .notVisible)
                }
                result.unreadable += 1
                continue
            default:
                break
            }
            guard let stat = entry.pointee.fts_statp?.pointee else { continue }
            if stat.st_flags & UInt32(SF_DATALESS) != 0 {
                result.dataless += 1
                if kind == FTS_D { fts_set(stream, entry, FTS_SKIP) }
                continue
            }
            let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec))
            if result.newest.map({ modified > $0 }) ?? true { result.newest = modified }
            if kind == FTS_D {
                result.bytes += Int64(stat.st_blocks) * 512
                continue
            }
            if stat.st_nlink > 1 {
                guard linked.insert(UInt64(stat.st_ino)).inserted else { continue }
            }
            result.files += 1
            result.bytes += Int64(stat.st_blocks) * 512
        }
        if result.unreadable > 0 { result.visibility = .partial }
        return result
    }

    /// Who `path` is right now, with `bytes` as measured. `nil` when it is gone.
    public static func identity(_ path: String, bytes: Int64) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino),
                            modified: Int64(info.st_mtimespec.tv_sec), bytes: bytes)
    }

    /// Whether a path is an iCloud placeholder.
    public static func isDataless(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }
}
