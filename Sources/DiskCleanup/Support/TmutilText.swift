//
//  TmutilText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum TmutilText {

    /// Snapshot names from `tmutil listlocalsnapshots /`.
    static func snapshots(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }

    /// The system's own update snapshots, which are never touched.
    static func isSystemOwned(_ name: String) -> Bool {
        name.hasPrefix("com.apple.os.update")
    }
}
