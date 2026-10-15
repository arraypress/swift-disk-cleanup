//
//  FileIdentity.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Who a path was when it was planned: re-read just before acting, and the
/// item is skipped if any of it moved.
public struct FileIdentity: Codable, Equatable, Hashable, Sendable {
    public let device: Int64
    public let inode: UInt64
    /// The path's own modification time, to the second.
    public let modified: Int64
    /// Allocated bytes under it at planning time.
    public let bytes: Int64

    public init(device: Int64, inode: UInt64, modified: Int64, bytes: Int64) {
        self.device = device
        self.inode = inode
        self.modified = modified
        self.bytes = bytes
    }
}
