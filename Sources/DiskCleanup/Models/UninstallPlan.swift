//
//  UninstallPlan.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Who an uninstall is for, as resolved from what was typed.
public struct UninstallIdentity: Codable, Equatable, Sendable {
    /// What was asked for: a .app path, a name, a bundle id, a package id, a
    /// vendor (`com.valhalladsp`) or a team id.
    public let input: String
    /// The apps' bundle ids, installed or gone.
    public var bundleIDs: [String] = []
    /// Display and product names, for name matches.
    public var names: [String] = []
    /// The reverse-DNS vendor, never Apple's: `com.apple` names no one vendor.
    public var vendor: String?
    /// Code-signing team ids.
    public var teamIDs: [String] = []
    /// Installed app bundles.
    public var apps: [String] = []
    /// Installer receipts that matched.
    public var receipts: [String] = []

    public init(input: String) {
        self.input = input
    }
}

/// Everything an uninstall would take, in evidence tiers, and what it could not do itself.
///
/// Each item's `evidence["match"]` is `exact` (a receipt owns it, or it is
/// named by the bundle id), `likely` (team id or vendor prefix), or
/// `review`  (a name match, or shared with another app). Exact and likely
/// items are safe tier and go with `--yes`; review items only by id or when
/// asked. `evidence["why"]` says what matched.
public struct UninstallPlan: Sendable {
    public let identity: UninstallIdentity
    public var items: [Item]
    /// Bundle ids of the apps running now: removing refuses while they are.
    public var running: [String]
    public var notes: [String]

    public init(identity: UninstallIdentity, items: [Item] = [], running: [String] = [], notes: [String] = []) {
        self.identity = identity
        self.items = items
        self.running = running
        self.notes = notes
    }
}
