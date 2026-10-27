//
//  AppArchitecture.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Which processors an app's main binary is built for.
public enum AppArchitecture: String, Sendable, Codable, CaseIterable, Hashable {
    /// Apple silicon only.
    case appleSilicon = "apple-silicon"
    /// Apple silicon and Intel in one binary.
    case universal
    /// Intel only: runs on Apple silicon through Rosetta, which Apple is winding down.
    case intel
    /// The binary could not be read.
    case unknown
}
