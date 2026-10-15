//
//  Tier.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How much judgement an item needs before it goes.
public enum Tier: String, Codable, CaseIterable, Sendable, Comparable {
    /// Rebuilds itself or is provably dead: cleaned by `clean <category>`.
    case safe
    /// Probably fine, but costly or personal to lose: cleaned only when asked
    /// for by id or with review included.
    case review
    /// Shown for its size, never cleaned by this library.
    case report

    public static func < (lhs: Tier, rhs: Tier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
