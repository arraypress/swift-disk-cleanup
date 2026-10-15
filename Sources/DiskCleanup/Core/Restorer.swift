//
//  Restorer.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// `undo`: puts journalled items back where they came from.
public enum Restorer {

    /// Restores the last batch (`target` nil), a batch, or one entry. Nothing
    /// is ever overwritten: if something now sits at the original path, the
    /// entry stays in the Trash and says so.
    public static func undo(_ target: String?, journal: URL) throws(DiskCleanupError) -> [RestoreOutcome] {
        var entries = try JournalStore.load(journal)
        let chosen = try JournalStore.select(entries, target: target)
        var outcomes: [RestoreOutcome] = []
        for entry in chosen {
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            if entry.restoredAt != nil {
                outcomes.append(RestoreOutcome(entry: entry.id, original: entry.original, result: .alreadyRestored))
                continue
            }
            guard PathProbe.exists(entry.trashed) else {
                outcomes.append(RestoreOutcome(entry: entry.id, original: entry.original, result: .gone,
                                               reason: "not in the Trash any more (emptied, or moved out)"))
                continue
            }
            guard !PathProbe.exists(entry.original) else {
                outcomes.append(RestoreOutcome(entry: entry.id, original: entry.original, result: .occupied,
                                               reason: "something is at the original path; left in the Trash at \(entry.trashed)"))
                continue
            }
            do {
                let parent = URL(fileURLWithPath: entry.original).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try FileManager.default.moveItem(atPath: entry.trashed, toPath: entry.original)
                entries[index].restoredAt = Date()
                outcomes.append(RestoreOutcome(entry: entry.id, original: entry.original, result: .restored))
            } catch {
                outcomes.append(RestoreOutcome(entry: entry.id, original: entry.original, result: .failed,
                                               reason: error.localizedDescription))
            }
        }
        try JournalStore.save(entries, to: journal)
        return outcomes
    }
}
