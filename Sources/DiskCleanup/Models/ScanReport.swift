//
//  ScanReport.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Everything one scan found.
public struct ScanReport: Codable, Equatable, Sendable {
    public let categories: [CategoryTotal]
    public let items: [Item]
    /// Places that could not be looked at, with why — a path per entry.
    public let notVisible: [String]
    /// Things a rule wanted to say about this run (a tool missing, a check skipped).
    public let notes: [String]
    public let seconds: Double

    public init(categories: [CategoryTotal], items: [Item], notVisible: [String], notes: [String], seconds: Double) {
        self.categories = categories
        self.items = items
        self.notVisible = notVisible
        self.notes = notes
        self.seconds = seconds
    }
}
