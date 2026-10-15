//
//  AppIndex.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Every app in the app folders, by bundle id: /Applications (and one level
//  of subfolders, which covers Utilities and Setapp), ~/Applications,
//  /System/Applications and the Homebrew Caskroom. An app whose Info.plist
//  cannot be read is counted, because the leftover finder refuses to guess
//  while any app is unreadable.
//

import Foundation

public struct AppIndex: Sendable {

    public let apps: [String: [InstalledApp]]
    /// App bundles whose Info.plist could not be read.
    public let unreadable: [String]

    /// Indexes the given folders.
    public static func build(folders: [URL]) -> AppIndex {
        var apps: [String: [InstalledApp]] = [:]
        var unreadable: [String] = []
        for folder in folders {
            for path in bundles(in: folder.path, depth: folder.path.hasSuffix("Caskroom") ? 3 : 2) {
                if let app = read(appAt: path) {
                    apps[app.bundleID.lowercased(), default: []].append(app)
                } else {
                    unreadable.append(path)
                }
            }
        }
        return AppIndex(apps: apps, unreadable: unreadable)
    }

    /// The `.app` bundles under `folder`, not looking inside any bundle.
    static func bundles(in folder: String, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        var found: [String] = []
        for name in PathProbe.list(folder).names where !name.hasPrefix(".") {
            let path = folder + "/" + name
            if name.hasSuffix(".app") {
                found.append(path)
            } else if PathProbe.isDirectory(path) {
                found += bundles(in: path, depth: depth - 1)
            }
        }
        return found
    }

    /// An app bundle's identity: `Contents/Info.plist`, or for an iOS app on
    /// Apple silicon, the plist of the app inside `Wrapper/`.
    public static func read(appAt path: String) -> InstalledApp? {
        var candidates = [path + "/Contents/Info.plist"]
        let wrapper = path + "/Wrapper"
        candidates += PathProbe.list(wrapper).names.filter { $0.hasSuffix(".app") }.map { wrapper + "/" + $0 + "/Info.plist" }
        for plist in candidates {
            if let data = PathProbe.read(plist), let info = PlistValues.bundleInfo(data) {
                return InstalledApp(bundleID: info.bundleID, path: path, version: info.version, build: info.build, name: info.name)
            }
        }
        return nil
    }

    /// The installed copies of a bundle id, from the folders and LaunchServices together.
    func answer(_ bundleID: String, lookup: any ApplicationLookup) -> AppAnswer {
        var found = apps[bundleID.lowercased()] ?? []
        switch lookup.launchServices(bundleID) {
        case .installed(let more): found += more.filter { app in !found.contains { $0.path == app.path } }
        case .noAnswer(let why) where found.isEmpty: return .noAnswer(why)
        default: break
        }
        return found.isEmpty ? .notInstalled : .installed(found)
    }

    /// Every bundle id and vendor prefix present, lower-cased.
    var knownIDs: (ids: Set<String>, vendors: Set<String>) {
        let ids = Set(apps.keys)
        return (ids, Set(ids.map(BundleIDs.vendor)))
    }
}
