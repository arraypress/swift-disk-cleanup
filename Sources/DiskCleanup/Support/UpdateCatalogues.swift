//
//  UpdateCatalogues.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The two public catalogues an update check reads, pure: the App Store's
//  lookup answer, and Homebrew's cask catalogue — each cask's version, by
//  the app bundle it installs.
//

import Foundation

enum UpdateCatalogues {

    /// The App Store's version from a `itunes.apple.com/lookup?bundleId=` answer.
    static func appStoreVersion(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else { return nil }
        return results.first?["version"] as? String
    }

    /// A cask as an update check needs it.
    struct Cask: Sendable, Equatable {
        let token: String
        let version: String
    }

    /// Every cask with a real version, by the `.app` it installs, lower-cased
    /// (`1password.app` → 1password 8.12.42), and by the bundle ids its
    /// uninstall step quits (`net.mullvad.vpn`) — a cask that installs a
    /// package names no app, but says which app to quit. A cask's
    /// `version,build` reads as its version; `latest` is left out.
    static func casks(_ data: Data) -> [String: Cask] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var found: [String: Cask] = [:]
        for cask in list {
            guard let token = cask["token"] as? String, let raw = cask["version"] as? String,
                  let version = caskVersion(raw) else { continue }
            for artifact in (cask["artifacts"] as? [[String: Any]]) ?? [] {
                for step in ((artifact["uninstall"] as? [Any]) ?? []).compactMap({ $0 as? [String: Any] }) {
                    let quit = (step["quit"] as? String).map { [$0] } ?? (step["quit"] as? [String]) ?? []
                    for id in quit where found["id:" + id.lowercased()] == nil {
                        found["id:" + id.lowercased()] = Cask(token: token, version: version)
                    }
                }
                for app in (artifact["app"] as? [Any]) ?? [] {
                    // An entry is a name, or a name with a `target` it is renamed to.
                    let name = (app as? String) ?? ((app as? [String: Any])?["target"] as? String)
                    guard let name else { continue }
                    let key = (name as NSString).lastPathComponent.lowercased()
                    if found[key] == nil { found[key] = Cask(token: token, version: version) }
                }
            }
        }
        return found
    }

    /// A cask version as a comparable one: before any comma, never `latest`.
    static func caskVersion(_ raw: String) -> String? {
        let version = String(raw.split(separator: ",", maxSplits: 1).first ?? "")
        return version.isEmpty || version == "latest" ? nil : version
    }
}
