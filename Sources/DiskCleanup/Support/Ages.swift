//
//  Ages.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum Ages {

    /// Whole days from `date` to `now`, never negative.
    static func days(since date: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 86_400))
    }

    /// Why an item touched at `newest` is too young for a rule's age gate, if it is.
    static func tooYoung(_ newest: Date?, minDays: Int?, now: Date) -> String? {
        guard let minDays, minDays > 0, let newest else { return nil }
        let age = days(since: newest, now: now)
        guard age < minDays else { return nil }
        return "touched \(age) day\(age == 1 ? "" : "s") ago (waits \(minDays))"
    }
}
