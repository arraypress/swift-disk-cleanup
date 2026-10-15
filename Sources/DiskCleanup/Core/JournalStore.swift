//
//  JournalStore.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The undo journal: one JSON file of every move to the Trash, written after
//  each move so a crash mid-clean still leaves a record of what went.
//

import Foundation

public enum JournalStore {

    /// Every entry, oldest first. A missing journal is empty; an unreadable
    /// one is an error, never quietly empty.
    public static func load(_ url: URL) throws(DiskCleanupError) -> [JournalEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([JournalEntry].self, from: data)
        } catch {
            throw .journal("cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ entries: [JournalEntry], to url: URL) throws(DiskCleanupError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
            throw .journal("cannot write \(url.path): \(error.localizedDescription)")
        }
    }

    static func append(_ entry: JournalEntry, to url: URL) throws(DiskCleanupError) {
        var entries = try load(url)
        entries.append(entry)
        try save(entries, to: url)
    }

    /// The entries an undo target names: `nil` is the last batch, otherwise a
    /// batch id or a single entry id.
    public static func select(_ entries: [JournalEntry], target: String?) throws(DiskCleanupError) -> [JournalEntry] {
        guard let target else {
            guard let batch = entries.last(where: { $0.restoredAt == nil })?.batch else {
                throw .journalEntryNotFound("the last batch")
            }
            return entries.filter { $0.batch == batch }
        }
        let chosen = entries.filter { $0.batch == target || $0.id == target }
        guard !chosen.isEmpty else { throw .journalEntryNotFound(target) }
        return chosen
    }
}
