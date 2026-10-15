//
//  MacOSInstallerData.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Where an `Install macOS ….app` says which macOS it installs. Its own app
//  version is the installer's (19.x for Sonoma), and its name only helps
//  for releases already in ``MacOSNames`` — so the version comes from the
//  data it carries: `InstallInfo.plist` up to Catalina, and from Big Sur on
//  the software-update asset XML inside `SharedSupport.dmg`.
//

import Foundation

enum MacOSInstallerData {

    /// Where the software-update XML sits inside `SharedSupport.dmg`.
    static let softwareUpdateXML =
        "com_apple_MobileAsset_MacSoftwareUpdate/com_apple_MobileAsset_MacSoftwareUpdate.xml"

    /// `InstallInfo.plist` → `System Image Info` → `version`.
    static func version(installInfo data: Data) -> String? {
        guard let plist = PlistValues.dictionary(data),
              let image = plist["System Image Info"] as? [String: Any],
              let version = image["version"] as? String else { return nil }
        return cleaned(version)
    }

    /// The software-update XML → the first asset's `OSVersion`.
    static func version(softwareUpdate data: Data) -> String? {
        guard let plist = PlistValues.dictionary(data),
              let assets = plist["Assets"] as? [[String: Any]] else { return nil }
        return assets.lazy.compactMap { ($0["OSVersion"] as? String).flatMap(cleaned) }.first
    }

    /// `14.4`, `27.0`; anything that is not dotted numbers is not a version.
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: /\d+(\.\d+)*/) != nil ? trimmed : nil
    }
}
