//
//  CommandOutput.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a child process left behind.
public struct CommandOutput: Equatable, Sendable {
    public let status: Int32
    public let timedOut: Bool
    public let stdout: Data
    public let stderr: Data

    public init(status: Int32, timedOut: Bool, stdout: Data, stderr: Data) {
        self.status = status
        self.timedOut = timedOut
        self.stdout = stdout
        self.stderr = stderr
    }
}
