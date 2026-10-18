//
//  Removal.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How an item leaves the disk.
///
/// In the catalogue JSON this is `"trash"`, `"delete"`, `"sudo"`, or the owning tool's
/// own command as an array — `["uv", "cache", "prune"]`. A command argument
/// may name a placeholder (`{udid}`, `{identifier}`) the detector fills from
/// the item's evidence.
public enum Removal: Equatable, Hashable, Sendable {
    /// Moved to the Trash and journalled, so `undo` can put it back.
    case trash
    /// Unlinked: only for things that rebuild themselves.
    case delete
    /// The owning tool's command, run with no shell.
    case command([String])
    /// Owned by root. diskmaid never asks for admin rights: it prints
    /// `sudo rm -rf <path>` for a person to run, and leaves it.
    case sudo
}
