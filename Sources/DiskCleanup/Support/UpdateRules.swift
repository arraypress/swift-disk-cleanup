//
//  UpdateRules.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Whether an app is out of date, pure. A Sparkle feed is compared the way
//  Sparkle compares — the build (`CFBundleVersion` against
//  `sparkle:version`) when both have one; everything else by the version
//  people see. Versions that cannot be ordered are unknown, never "current".
//

import Foundation

enum UpdateRules {

    /// The status of `installed` against `latest`.
    ///
    /// - Parameters:
    ///   - installed: The app's own short version and build.
    ///   - latest: The source's newest short version and build.
    static func status(installed: (version: String?, build: String?), latest: (version: String?, build: String?)) -> UpdateStatus {
        if let have = installed.build, let newest = latest.build, let order = VersionOrder.compare(have, newest) {
            return order == .orderedAscending ? .available : .current
        }
        guard let have = installed.version, let newest = latest.version,
              let order = VersionOrder.compare(have, newest) else { return .unknown }
        return order == .orderedAscending ? .available : .current
    }

    /// How to update an app from a source.
    static func how(_ source: UpdateSource, cask: String?, viaHomebrew: Bool) -> String {
        switch source {
        case .appStore: return "the App Store"
        case .sparkle: return "the app's own updater (its menu: Check for Updates…)"
        case .homebrew: return viaHomebrew ? "brew upgrade --cask \(cask ?? "")" : "the app's own updater, or its website"
        case .none: return "no update source: not from the App Store, no update feed, no Homebrew cask"
        }
    }
}
