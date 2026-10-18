//
//  PackageReceipt.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// An installer receipt, as `pkgutil` keeps it: where the package installed
/// and every path it wrote, relative to there.
public struct PackageReceipt: Codable, Equatable, Sendable {
    public let id: String
    /// The volume it went on: `/` for the startup disk.
    public let volume: String
    /// The folder on that volume, `Library/Audio/Plug-Ins/Components/` or empty.
    public let location: String
    /// Files AND folders, shared parents (`Library`, `Library/Audio`) included.
    public let files: [String]

    public init(id: String, volume: String, location: String, files: [String]) {
        self.id = id
        self.volume = volume
        self.location = location
        self.files = files
    }
}
