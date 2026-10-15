//
//  SimulatorDevice.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One simulator, as `simctl list devices -j` describes it.
public struct SimulatorDevice: Codable, Equatable, Sendable {
    public let udid: String
    public let name: String
    public let runtime: String
    public let state: String?
    public let isAvailable: Bool
    /// The device's folder (the parent of its `data`), when simctl says.
    public let folder: String?

    public init(udid: String, name: String, runtime: String, state: String?, isAvailable: Bool, folder: String?) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.state = state
        self.isAvailable = isAvailable
        self.folder = folder
    }
}
