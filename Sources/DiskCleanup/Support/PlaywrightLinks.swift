//
//  PlaywrightLinks.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Playwright keeps a register of every install that uses its browser
//  folder: `ms-playwright/.links/<hash>` holds the path of one
//  `playwright-core`, whose `browsers.json` lists the builds it needs
//  (`{"browsers": [{"name": "chromium-headless-shell", "revision": "1248",
//  "revisionOverrides": {"mac12": "1220"}}]}`). A build's folder is the name
//  with dashes as underscores, a dash, and the revision. Read off real
//  installs (Playwright 1.5x); every override is counted as needed, since
//  which one this Mac's OS picks is Playwright's call.
//

import Foundation

enum PlaywrightLinks {

    /// The install a `.links` file points at: one absolute path.
    static func install(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("/") && !text.contains("\n") ? text : nil
    }

    /// The browser folder names a `browsers.json` needs.
    static func folders(_ browsersJSON: Data) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: browsersJSON) as? [String: Any],
              let browsers = object["browsers"] as? [[String: Any]] else { return [] }
        var folders: Set<String> = []
        for browser in browsers {
            guard let name = browser["name"] as? String else { continue }
            let stem = name.replacingOccurrences(of: "-", with: "_")
            var revisions = [browser["revision"]].compactMap { $0.map { "\($0)" } }
            revisions += ((browser["revisionOverrides"] as? [String: Any]) ?? [:]).values.map { "\($0)" }
            folders.formUnion(revisions.map { stem + "-" + $0 })
        }
        return folders
    }
}
