//
//  VersionOrder.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Comparing app versions the way people write them: `1.10` is newer than
//  `1.9`, `2.0` equals `2`, `3.1b2` is older than `3.1`'s next release only
//  as far as its digits say.
//

import Foundation

enum VersionOrder {

    /// The version's parts: runs of digits as numbers, anything else as text.
    static func parts(_ version: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var currentIsDigit: Bool?
        for character in version {
            let isDigit = character.isASCII && character.isNumber
            let isWord = character.isLetter
            guard isDigit || isWord else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                currentIsDigit = nil
                continue
            }
            if let currentIsDigit, currentIsDigit != isDigit, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = isDigit
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Orders two version strings; `nil` when either has no digits to go on.
    static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        var left = parts(a), right = parts(b)
        guard left.contains(where: { Int($0) != nil }), right.contains(where: { Int($0) != nil }) else { return nil }
        // Trailing zeros carry no meaning: 2.0 is 2.
        while left.count > 1, left.last == "0" { left.removeLast() }
        while right.count > 1, right.last == "0" { right.removeLast() }
        for index in 0..<max(left.count, right.count) {
            guard index < left.count else { return .orderedAscending }
            guard index < right.count else { return .orderedDescending }
            let l = left[index], r = right[index]
            if let ln = Int(l), let rn = Int(r) {
                if ln != rn { return ln < rn ? .orderedAscending : .orderedDescending }
            } else if Int(l) != nil {
                return .orderedDescending   // 1.2.1 is after 1.2b
            } else if Int(r) != nil {
                return .orderedAscending
            } else if l.lowercased() != r.lowercased() {
                return l.lowercased() < r.lowercased() ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
