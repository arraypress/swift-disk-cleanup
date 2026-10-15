//
//  SimulatorRuntime.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One installed simulator runtime image, as `simctl runtime list -j` describes it.
public struct SimulatorRuntime: Codable, Equatable, Sendable {
    /// The image's own identifier — what `simctl runtime delete` takes.
    public let identifier: String
    /// The runtime it provides (`com.apple.CoreSimulator.SimRuntime.iOS-27-0`).
    public let runtimeIdentifier: String
    public let version: String?
    public let build: String?
    public let bytes: Int64?
    public let deletable: Bool
    public let state: String?

    public init(identifier: String, runtimeIdentifier: String, version: String?, build: String?,
                bytes: Int64?, deletable: Bool, state: String?) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.version = version
        self.build = build
        self.bytes = bytes
        self.deletable = deletable
        self.state = state
    }
}
