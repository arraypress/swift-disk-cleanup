//
//  HandBack.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The part of a removal diskmaid leaves to a person, as one line: root-owned
//  paths removed, system launch jobs unloaded, and the installer receipts of
//  what goes forgotten — after the files, so a receipt never outlives them
//  and never goes while they stay.
//

import Foundation

public enum HandBack {

    /// The one sudo line for `taking`, or `nil` when diskmaid does it all.
    ///
    /// A receipt (an item's `receipt`/`receipts` evidence) is forgotten only
    /// when every item in `all` that names it is being taken. `receipts` are
    /// ones no item names — content already gone — and are always forgotten.
    public static func line(_ taking: [Item], among all: [Item], receipts orphaned: [String] = []) -> String? {
        let ids = Set(taking.map(\.id))
        var forget: [String] = []
        for receipt in orphaned + all.flatMap(\.receipts) where !forget.contains(receipt) {
            let naming = all.filter { $0.receipts.contains(receipt) }
            if naming.allSatisfy({ ids.contains($0.id) }) { forget.append(receipt) }
        }
        return UninstallMatch.byHand(
            paths: taking.filter { $0.removal == .sudo && $0.path.hasPrefix("/") }.map(\.path),
            systemJobs: taking.compactMap { $0.evidence["launchDomain"] == "system" ? $0.evidence["launchLabel"] : nil },
            receipts: forget
        )
    }
}

public extension Item {
    /// The installer receipts this item's files belong to.
    var receipts: [String] {
        let many = evidence["receipts"].map { $0.split(separator: " ").map(String.init) } ?? []
        return (evidence["receipt"].map { [$0] } ?? []) + many
    }
}
