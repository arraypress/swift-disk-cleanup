//
//  VersionedNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Tools that download one folder per build and never take the old one
//  away: Playwright (`chromium-1243`, `chromium-1248`), Puppeteer
//  (`mac_arm-131.0.6778.85`), JetBrains IDEs (`IntelliJIdea2025.1`). A name
//  is a product and a trailing version; within one product the newest are
//  kept and the rest are superseded. A name with no trailing version is
//  never superseded — it is not this kind of folder.
//

import Foundation

enum VersionedNames {

    /// The product and the trailing version: `chromium_headless_shell-1243`
    /// → (`chromium_headless_shell`, `1243`), `IntelliJIdea2025.1` →
    /// (`IntelliJIdea`, `2025.1`). `nil` without a product or a version.
    static func split(_ name: String) -> (product: String, version: String)? {
        guard let match = name.wholeMatch(of: /(.+?)[-_ ]?v?(\d+(?:\.\d+)*)/) else { return nil }
        let product = String(match.1)
        guard product.contains(where: \.isLetter) else { return nil }
        return (product, String(match.2))
    }

    /// The names to take: all but the `keep` newest of each product. Names
    /// that do not split, and versions that cannot be ordered, are kept.
    static func superseded(_ names: [String], keep: Int) -> Set<String> {
        var byProduct: [String: [(name: String, version: String)]] = [:]
        for name in names {
            guard let split = split(name) else { continue }
            byProduct[split.product.lowercased(), default: []].append((name, split.version))
        }
        var old: Set<String> = []
        for (_, entries) in byProduct where entries.count > keep {
            let newestFirst = entries.sorted { VersionOrder.compare($0.version, $1.version) == .orderedDescending }
            old.formUnion(newestFirst.dropFirst(max(keep, 1)).map(\.name))
        }
        return old
    }
}
