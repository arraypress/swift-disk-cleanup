//
//  CompiledModelNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Core AI keeps each model it compiles at
//  `coreai-cache/<build>/<program>/<hash>`, where the hash is the hex of the
//  source asset's `main.hash`. A copy whose asset is gone from the disk can
//  never be loaded again: nothing will ask for that hash.
//

import Foundation

enum CompiledModelNames {

    /// Whether a cache folder's name is an asset hash: 64 hex digits, either case.
    static func isAssetHash(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy(\.isHexDigit)
    }

    /// The cache's name for an asset whose `main.hash` holds `data`, lower-cased for matching.
    static func hash(_ data: Data) -> String? {
        data.isEmpty ? nil : data.map { String(format: "%02x", $0) }.joined()
    }

    /// Folders never walked looking for models: version control, dependencies, build
    /// output, and the compiled copies themselves.
    static let skipped: Set<String> = [".git", "node_modules", ".build", ".swiftpm", ".venv", "DerivedData", "coreai-cache",
                                       ".Trash", "Photos Library.photoslibrary"]
}
