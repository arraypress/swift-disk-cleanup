//
//  TrashBin.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The one place a user-made item leaves its folder: the Trash.
enum TrashBin {

    /// Moves `path` to the Trash and returns where it landed.
    ///
    /// The system Trash for a real home. For a fixture home, a `.Trash`
    /// folder inside it, with the same rename-on-collision the Finder does —
    /// so tests never put anything in the real Trash.
    static func move(_ path: String, folder: URL?) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard let folder else {
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            return (landed as URL?)?.path ?? ""
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target.path
    }
}
