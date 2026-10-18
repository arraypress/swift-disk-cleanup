//
//  ScanHistory.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One item's size in a saved scan.
public struct HistoryItem: Codable, Equatable, Sendable {
    /// Stable for the same rule and path, so scans line up by it.
    public let id: String
    public let path: String
    public let rule: String
    public let category: String
    /// `nil` when it could not be measured.
    public let bytes: Int64?

    public init(id: String, path: String, rule: String, category: String, bytes: Int64?) {
        self.id = id
        self.path = path
        self.rule = rule
        self.category = category
        self.bytes = bytes
    }
}

/// One saved scan: when, which categories it covered, and what each came to.
public struct HistoryEntry: Codable, Equatable, Sendable {
    public let at: Date
    /// Category → bytes, for the categories this scan covered.
    public let categories: [String: Int64]
    public let items: [HistoryItem]

    public init(at: Date, categories: [String: Int64], items: [HistoryItem]) {
        self.at = at
        self.categories = categories
        self.items = items
    }
}

/// How one item or category changed between two scans.
public struct SizeChange: Codable, Equatable, Sendable {
    /// An item id, or a category name.
    public let id: String
    public let path: String?
    public let rule: String?
    public let category: String
    public let beforeBytes: Int64?
    public let afterBytes: Int64?
    /// After less before; what came or went entirely counts in full.
    public let deltaBytes: Int64
    /// `grew`, `shrank`, `new` or `gone`.
    public let status: String

    public init(id: String, path: String?, rule: String?, category: String, beforeBytes: Int64?, afterBytes: Int64?,
                deltaBytes: Int64, status: String) {
        self.id = id
        self.path = path
        self.rule = rule
        self.category = category
        self.beforeBytes = beforeBytes
        self.afterBytes = afterBytes
        self.deltaBytes = deltaBytes
        self.status = status
    }
}

/// What grew and shrank since a saved scan, biggest change first.
public struct ScanChanges: Codable, Equatable, Sendable {
    /// When the scan compared against was made.
    public let since: Date
    public let until: Date
    /// Everything that grew or appeared, added up.
    public let grewBytes: Int64
    /// Everything that shrank or went, added up (a positive number).
    public let shrankBytes: Int64
    /// Grew less shrank.
    public let netBytes: Int64
    public let categories: [SizeChange]
    public let items: [SizeChange]

    public init(since: Date, until: Date, grewBytes: Int64, shrankBytes: Int64, netBytes: Int64,
                categories: [SizeChange], items: [SizeChange]) {
        self.since = since
        self.until = until
        self.grewBytes = grewBytes
        self.shrankBytes = shrankBytes
        self.netBytes = netBytes
        self.categories = categories
        self.items = items
    }
}
