//
//  StartupItem.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Something that starts by itself: at login, at boot, or on demand.
public struct StartupItem: Codable, Equatable, Sendable {
    /// `launch-agent`, `launch-daemon`, `app-service` (registered by an app
    /// from inside its bundle — SMAppService) or `login-item` (System Events').
    public let kind: String
    /// The launchd label, or a login item's name.
    public let label: String
    /// The plist, the helper inside an app, or the login item's app.
    public let path: String
    public let program: String?
    public let programExists: Bool?
    public let owner: String?
    public let ownerBundleID: String?
    public let team: String?
    public let isApple: Bool
    /// `nil` when launchctl was not asked (login items) or did not answer.
    public let loaded: Bool?
    public let disabled: Bool?
    /// How it can go: `trash` (yours; undo loads it again), `sudo` (root's:
    /// a printed line), `system-events`, `settings` (only its app or Login
    /// Items settings can), or `never` (Apple's).
    public let removal: String

    public init(kind: String, label: String, path: String, program: String?, programExists: Bool?, owner: String?,
                ownerBundleID: String?, team: String?, isApple: Bool, loaded: Bool?, disabled: Bool?, removal: String) {
        self.kind = kind
        self.label = label
        self.path = path
        self.program = program
        self.programExists = programExists
        self.owner = owner
        self.ownerBundleID = ownerBundleID
        self.team = team
        self.isApple = isApple
        self.loaded = loaded
        self.disabled = disabled
        self.removal = removal
    }
}

/// What asking to remove one startup item comes to.
public struct StartupRemoval: Sendable {
    public let item: StartupItem
    /// The plist as a removable item (`trash` and `sudo` only).
    public let target: Item?
    /// The line for a person to run as root.
    public let byHand: String?
    /// Login Items settings, for what only the owner app may remove.
    public let settings: URL?
}
