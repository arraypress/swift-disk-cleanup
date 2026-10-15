//
//  BrewOutput.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum BrewOutput {

    /// The total in `brew cleanup -n`'s last line: "This operation would free
    /// approximately 237.5MB of disk space." Homebrew's units are binary.
    /// Zero when it says nothing would be freed.
    static func wouldFree(_ text: String) -> Int64? {
        guard let match = text.firstMatch(of: /would free approximately ([\d.]+)\s*([KMGT]?B)/) else {
            return text.contains("Would remove") ? nil : 0
        }
        guard let value = Double(match.1) else { return nil }
        let multiplier: Double = switch match.2 {
        case "KB": 1024
        case "MB": 1024 * 1024
        case "GB": 1024 * 1024 * 1024
        case "TB": 1024 * 1024 * 1024 * 1024
        default: 1
        }
        return Int64(value * multiplier)
    }
}
