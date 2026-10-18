//
//  WhereNode.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What the catalogue says about a place: the rule or category that owns
/// it, its tier, and its app.
public struct PlaceLabel: Codable, Equatable, Sendable {
    /// A rule id, or `protected` for a place no rule may reach.
    public let rule: String
    public let category: String?
    public let tier: String?
    public let owner: String?
    /// The place is inside what the rule found, rather than the thing itself.
    public let inside: Bool

    public init(rule: String, category: String?, tier: String?, owner: String?, inside: Bool) {
        self.rule = rule
        self.category = category
        self.tier = tier
        self.owner = owner
        self.inside = inside
    }
}

/// One folder of a `where` tree, biggest children first.
public struct WhereNode: Codable, Sendable {
    public let path: String
    /// Allocated bytes, APFS clones' shared blocks once; `nil` when not visible.
    public var bytes: Int64?
    /// The same with every clone in full.
    public var apparentBytes: Int64?
    public var visibility: Visibility
    public var label: PlaceLabel?
    public var children: [WhereNode]
    /// Children left out for being under the size asked for.
    public var smallerCount: Int
    public var smallerBytes: Int64

    public init(path: String, bytes: Int64?, apparentBytes: Int64?, visibility: Visibility, label: PlaceLabel? = nil,
                children: [WhereNode] = [], smallerCount: Int = 0, smallerBytes: Int64 = 0) {
        self.path = path
        self.bytes = bytes
        self.apparentBytes = apparentBytes
        self.visibility = visibility
        self.label = label
        self.children = children
        self.smallerCount = smallerCount
        self.smallerBytes = smallerBytes
    }
}
