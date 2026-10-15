//
//  Visibility.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Whether a place could be looked at. A folder macOS refused to open is
/// `notVisible`, never zero bytes.
public enum Visibility: String, Codable, CaseIterable, Sendable {
    /// Read in full.
    case visible
    /// Read, but parts of it were refused: the total is a floor.
    case partial
    /// Refused outright: needs Full Disk Access.
    case notVisible = "not-visible"
    /// Not there on this Mac.
    case absent
}
