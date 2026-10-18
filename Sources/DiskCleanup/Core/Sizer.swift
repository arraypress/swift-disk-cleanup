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
//  - APFS clones count their shared blocks once per walk: each file adds its
//    private bytes, and the rest — what it shares — is added once per clone
//    id. A clone that was partly rewritten gets a clone id of its own, so its
//    shared blocks can still count twice: over, never under. Clones shared
//    between two walks count in each, and files under 64 KB count in full
//    (asking for every small file doubled a full scan);
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
        var clones = CloneTally()
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
            let allocated = Int64(stat.st_blocks) * 512
            result.bytes += kind == FTS_F ? clones.add(entry.pointee.fts_accpath, allocated: allocated) : allocated
        }
        if result.unreadable > 0 { result.visibility = .partial }
        return result
    }

    /// Adds up files with the blocks APFS clones share counted once: each file
    /// adds its private bytes, and its shared bytes once per clone id.
    struct CloneTally {
        private var counted: [UInt64: Int64] = [:]

        /// What a file adds that this tally has not counted already.
        mutating func add(_ path: UnsafePointer<CChar>, allocated: Int64) -> Int64 {
            guard allocated >= Sizer.cloneFloor, let clone = Sizer.cloneShare(path) else { return allocated }
            let shared = max(0, allocated - clone.privateBytes)
            let before = counted[clone.id] ?? 0
            counted[clone.id] = max(before, shared)
            return min(clone.privateBytes, allocated) + max(0, shared - before)
        }
    }

    /// Files smaller than this count in full without asking: asking costs a
    /// second lookup per file, build folders hold hundreds of thousands of
    /// small ones, and the space clones hide is in the large ones.
    static let cloneFloor: Int64 = 65_536

    /// A file's clone id and the bytes it shares with no clone, or `nil` where
    /// the volume does not say (anything but APFS), which counts it in full.
    static func cloneShare(_ path: UnsafePointer<CChar>) -> (id: UInt64, privateBytes: Int64)? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID)
        // Laid out as: u_int32_t length, attribute_set_t returned, off_t private size, u_int64_t clone id.
        var buffer = [UInt8](repeating: 0, count: 4 + MemoryLayout<attribute_set_t>.size + 16)
        let status = buffer.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            let wanted = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID)
            guard returned.forkattr & wanted == wanted else { return nil }
            let offset = 4 + MemoryLayout<attribute_set_t>.size
            return (raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self),
                    raw.loadUnaligned(fromByteOffset: offset, as: Int64.self))
        }
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
