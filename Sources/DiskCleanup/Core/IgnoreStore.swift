//
//  IgnoreStore.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The ignore list on disk: one JSON file. A missing file is an empty list;
//  one that cannot be read is an error, never quietly empty — a cleaner
//  that forgot what it was told to leave alone must not run.
//

import Foundation

public enum IgnoreStore {

    public static func load(_ url: URL) throws(DiskCleanupError) -> IgnoreList {
        guard FileManager.default.fileExists(atPath: url.path) else { return IgnoreList() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(IgnoreList.self, from: Data(contentsOf: url))
        } catch {
            throw .ignoreList("cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ list: IgnoreList, to url: URL) throws(DiskCleanupError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(list).write(to: url, options: .atomic)
        } catch {
            throw .ignoreList("cannot write \(url.path): \(error.localizedDescription)")
        }
    }
}
