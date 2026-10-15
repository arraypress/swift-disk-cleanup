//
//  Claims.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  One path, one item. When rules overlap — the broad `~/Library/Caches/*`
//  sweep and the specific SwiftPM rule both find `org.swift.swiftpm` — the
//  rule earlier in the catalogue keeps it, and a later item that contains an
//  earlier one is dropped whole rather than allowed to delete what the
//  earlier rule protected.
//

import Foundation

enum Claims {

    /// The items to keep, in order, and the ids dropped with the id that won.
    static func resolve(_ items: [Item]) -> (kept: [Item], dropped: [String: String]) {
        var kept: [Item] = []
        var claimed: [(path: String, id: String)] = []
        var dropped: [String: String] = [:]
        for item in items {
            if !item.path.hasPrefix("/") {
                kept.append(item)   // a snapshot or a runtime image: not a path
                continue
            }
            if let winner = claimed.first(where: { PathText.overlaps(item.path, $0.path) }) {
                dropped[item.id] = winner.id
                continue
            }
            claimed.append((item.path, item.id))
            kept.append(item)
        }
        return (kept, dropped)
    }
}
