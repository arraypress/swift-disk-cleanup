//
//  HdiutilOutput.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum HdiutilOutput {

    /// Where `hdiutil attach -plist` mounted the image's volumes.
    static func mountPoints(_ data: Data) -> [String] {
        guard let plist = PlistValues.dictionary(data),
              let entities = plist["system-entities"] as? [[String: Any]] else { return [] }
        return entities.compactMap { $0["mount-point"] as? String }
    }

    /// `hdiutil isencrypted` prints `encrypted: YES` or `encrypted: NO`.
    static func isEncrypted(_ text: String) -> Bool? {
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard lower.contains("encrypted:") else { continue }
            if lower.contains("yes") { return true }
            if lower.contains("no") { return false }
        }
        return nil
    }

    /// Whether `hdiutil imageinfo -plist` says the image carries a licence
    /// agreement; `nil` when it does not say either way.
    static func hasLicenceAgreement(_ data: Data) -> Bool? {
        guard let plist = PlistValues.dictionary(data),
              let properties = plist["Properties"] as? [String: Any] else { return nil }
        return properties["Software License Agreement"] as? Bool
    }
}
