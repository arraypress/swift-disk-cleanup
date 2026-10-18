//
//  Measurement.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a walk of one path found.
public struct Measurement: Codable, Equatable, Sendable {
    /// Allocated bytes — blocks on disk, not logical length — with each hard
    /// link counted once and blocks APFS clones share counted once. Clones
    /// outside the walk keep their shared blocks, so freeing it gives back
    /// "up to" this.
    public var bytes: Int64
    /// Files, links and other leaves counted.
    public var files: Int
    /// The newest modification time of anything inside, the path included.
    public var newest: Date?
    /// Folders macOS refused to open.
    public var unreadable: Int
    /// iCloud placeholders seen and left unopened.
    public var dataless: Int
    public var visibility: Visibility

    public init(bytes: Int64 = 0, files: Int = 0, newest: Date? = nil, unreadable: Int = 0,
                dataless: Int = 0, visibility: Visibility) {
        self.bytes = bytes
        self.files = files
        self.newest = newest
        self.unreadable = unreadable
        self.dataless = dataless
        self.visibility = visibility
    }
}
