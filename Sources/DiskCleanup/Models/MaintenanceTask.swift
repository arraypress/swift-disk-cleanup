//
//  MaintenanceTask.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One maintenance job macOS really has, and what it fixes.
public struct MaintenanceTask: Codable, Equatable, Sendable {
    /// `dns`, `spotlight`, `launch-services`, `logs`, `quicklook`.
    public let id: String
    public let title: String
    /// One line: the problem it fixes.
    public let fixes: String
    /// The commands, in order, as argument lists starting with the tool's path.
    /// Empty for `logs`, which goes through the catalogue's `user-logs` rule.
    public let commands: [[String]]
    /// Root's: diskmaid prints the line and never runs it.
    public let needsRoot: Bool
    /// What a person should know first (Spotlight re-indexing takes a while).
    public let warning: String?
    /// For `logs`: only logs untouched this many days.
    public let olderThanDays: Int?

    public init(id: String, title: String, fixes: String, commands: [[String]], needsRoot: Bool,
                warning: String? = nil, olderThanDays: Int? = nil) {
        self.id = id
        self.title = title
        self.fixes = fixes
        self.commands = commands
        self.needsRoot = needsRoot
        self.warning = warning
        self.olderThanDays = olderThanDays
    }
}

/// What running one task did.
public struct MaintenanceOutcome: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        /// Every command ran and exited 0 (or, for logs, nothing failed).
        case ran
        /// A command failed or could not start; `detail` says which and why.
        case failed
        /// Root's: `detail` is the line for a person to run.
        case byHand = "by-hand"
    }

    public let task: String
    public let result: Result
    public let detail: String?
    /// For `logs`: what each one did.
    public let removals: [RemovalOutcome]

    public init(task: String, result: Result, detail: String? = nil, removals: [RemovalOutcome] = []) {
        self.task = task
        self.result = result
        self.detail = detail
        self.removals = removals
    }
}
