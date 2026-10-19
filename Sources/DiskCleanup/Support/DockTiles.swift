//
//  DockTiles.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Reading and editing the Dock's icon arrays as plain property lists. A
//  tile is the app's when its `tile-data` names one of the app's bundle ids
//  (`bundle-identifier`, any case) or its `file-data` URL is the app's path.
//  Editing only ever drops whole tiles; every other tile, and every key of
//  it, stays exactly as it was, in its order.
//

import Foundation

public enum DockTiles {

    /// The arrays an app's icon can be in: kept in the Dock, and recent.
    public static let keys = ["persistent-apps", "recent-apps"]

    /// The indices of `tiles` that are one of these apps.
    public static func matching(_ tiles: [Any], bundleIDs: [String], apps: [String]) -> [Int] {
        let ids = Set(bundleIDs.map { $0.lowercased() })
        let paths = Set(apps.map(normalised))
        return tiles.indices.filter { index in
            guard let data = (tiles[index] as? [String: Any])?["tile-data"] as? [String: Any] else { return false }
            if let id = data["bundle-identifier"] as? String, ids.contains(id.lowercased()) { return true }
            if let path = path(ofTileData: data), paths.contains(path) { return true }
            return false
        }
    }

    /// `tiles` without the ones at `indices`, the rest untouched and in order.
    public static func removing(_ tiles: [Any], at indices: [Int]) -> [Any] {
        let drop = Set(indices)
        return tiles.indices.filter { !drop.contains($0) }.map { tiles[$0] }
    }

    /// A tile's name as the Dock shows it (`file-label`).
    public static func label(_ tile: Any) -> String? {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["file-label"] as? String
    }

    /// The file path a tile's `file-data` URL points at, without a trailing slash.
    static func path(ofTileData data: [String: Any]) -> String? {
        guard let text = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String else { return nil }
        let path: String
        if let url = URL(string: text), url.isFileURL {
            path = url.path
        } else if text.hasPrefix("/") {
            path = text
        } else {
            return nil
        }
        return normalised(path)
    }

    /// One spelling per place: no trailing slash, and /private/tmp is /tmp's.
    static func normalised(_ path: String) -> String {
        var path = PathText.normalised(path)
        for alias in ["/tmp", "/var", "/etc"] where PathText.isWithin(path, "/private" + alias) {
            path = String(path.dropFirst("/private".count))
        }
        return path
    }

    /// Whether two property lists hold the same values, deeply.
    public static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b as AnyObject)
        default: return false
        }
    }

    /// `key → value` as a binary property list, for the journal. Absent keys
    /// are left out, so restoring one removes it again.
    static func archive(_ values: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    static func unarchive(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
