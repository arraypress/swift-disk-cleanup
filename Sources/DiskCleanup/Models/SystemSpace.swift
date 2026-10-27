//
//  SystemSpace.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One APFS volume in the startup disk's container.
public struct APFSVolumeInfo: Codable, Equatable, Sendable {
    public let name: String
    /// `System`, `Data`, `Preboot`, `Recovery`, `VM`, `Update`… or empty.
    public let roles: [String]
    public let usedBytes: Int64
    public let device: String

    public init(name: String, roles: [String], usedBytes: Int64, device: String) {
        self.name = name
        self.roles = roles
        self.usedBytes = usedBytes
        self.device = device
    }
}

/// A local snapshot. macOS does not say how big one is.
public struct LocalSnapshot: Codable, Equatable, Sendable {
    public let name: String
    /// From the name, for Time Machine's (`com.apple.TimeMachine.2026-10-18-101010.local`).
    public let date: Date?
    /// The system's own (an OS update's), which is never removed.
    public let isSystem: Bool

    public init(name: String, date: Date?, isSystem: Bool) {
        self.name = name
        self.date = date
        self.isSystem = isSystem
    }
}

/// What the grey "System Data" bar is made of, as far as the Mac will say.
public struct SystemSpace: Codable, Sendable {
    public var totalBytes: Int64?
    public var usedBytes: Int64?
    public var freeBytes: Int64?
    /// Free space counting what macOS would clear for something important.
    public var importantFreeBytes: Int64?
    /// What macOS would clear itself: snapshots, caches it owns.
    public var purgeableBytes: Int64? {
        guard let importantFreeBytes, let freeBytes, importantFreeBytes > freeBytes else { return nil }
        return importantFreeBytes - freeBytes
    }
    public var container: String?
    public var volumes: [APFSVolumeInfo] = []
    /// `nil` when tmutil and diskutil did not answer.
    public var snapshots: [LocalSnapshot]?
    public var swapBytes: Int64?
    public var sleepImageBytes: Int64?
    /// What diskmaid's scan found, with clones counted in full and once.
    public var scannedApparentBytes: Int64?
    public var scannedBytes: Int64?
    public var notes: [String] = []
    /// The startup drive's own health report, when it gives one.
    public var health: DiskHealth?

    public init() {}
}

/// One line of the explanation: a figure and what it means.
public struct SystemLine: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let bytes: Int64?
    public let meaning: String

    public init(key: String, label: String, bytes: Int64?, meaning: String) {
        self.key = key
        self.label = label
        self.bytes = bytes
        self.meaning = meaning
    }
}
