//
//  AppAnswer.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What asking "is this app installed?" came back with. The third case is
/// the one that matters: a lookup that timed out is not a "no".
public enum AppAnswer: Equatable, Sendable {
    case installed([InstalledApp])
    case notInstalled
    case noAnswer(String)
}
