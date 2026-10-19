//
//  IgnoreList.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What one ignore entry names.
public enum IgnoreKind: String, Codable, Sendable, CaseIterable {
    /// A place, and everything in it or holding it: `~/Library/Caches/Foo`.
    case path
    /// Every item a catalogue rule finds: `user-logs`.
    case rule
    /// One item, by its id: `hf-hub-1a2b3c4d`.
    case item
}

/// One thing the person told diskmaid never to touch.
public struct IgnoreEntry: Codable, Equatable, Sendable {
    public let kind: IgnoreKind
    /// A path (`~/…` inside the home folder), a rule id or an item id.
    public let value: String
    public let added: Date

    public init(kind: IgnoreKind, value: String, added: Date = Date()) {
        self.kind = kind
        self.value = value
        self.added = added
    }
}

/// Everything ignored: still shown, never cleaned, uninstalled or offered.
public struct IgnoreList: Codable, Equatable, Sendable {
    public var entries: [IgnoreEntry]

    public init(entries: [IgnoreEntry] = []) {
        self.entries = entries
    }
}
