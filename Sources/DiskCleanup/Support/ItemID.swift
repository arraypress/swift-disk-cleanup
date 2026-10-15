//
//  ItemID.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import CryptoKit
import Foundation

enum ItemID {

    /// `<rule>-<first 8 hex of SHA-256(path)>`: the same for the same rule and
    /// path on every run, so `list` today and `clean` tomorrow agree.
    static func make(rule: String, path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(rule)-\(hex)"
    }

    /// Whether a string has an item id's shape.
    static func isItemID(_ text: String) -> Bool {
        guard let dash = text.lastIndex(of: "-") else { return false }
        let hex = text[text.index(after: dash)...]
        return hex.count == 8 && hex.allSatisfy(\.isHexDigit) && dash > text.startIndex
    }

    /// The rule an item id names.
    static func rule(of id: String) -> String? {
        guard isItemID(id), let dash = id.lastIndex(of: "-") else { return nil }
        return String(id[..<dash])
    }
}
