//
//  InstallerKind.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What sort of installer a file is.
public enum InstallerKind: String, Codable, CaseIterable, Sendable {
    case dmg
    case pkg
    /// A zip holding an app bundle. A zip of anything else is not an installer.
    case zip
    /// An Apple `.xip`, almost always Xcode.
    case xip
    /// A leftover `Install macOS ….app`.
    case macOSInstaller = "macos-installer"
}
