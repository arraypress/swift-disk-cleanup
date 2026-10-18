//
//  HistoryStore.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Every scan's sizes, one JSON file each in
//  ~/Library/Application Support/diskmaid/history (a place the catalogue
//  protects), the oldest dropped past a cap. A file that will not read is
//  skipped, never fatal: history is a convenience, not a record.
//

import Foundation

public enum HistoryStore {

    /// How many scans are kept.
    public static let cap = 60

    public static func folder(_ context: CleanupContext) -> URL {
        context.home.appendingPathComponent("Library/Application Support/diskmaid/history", isDirectory: true)
    }

    /// Saves `report` as made at `at`, then drops the oldest past `cap`.
    @discardableResult
    public static func save(_ report: ScanReport, at: Date, context: CleanupContext, cap: Int = HistoryStore.cap) throws -> URL {
        let folder = folder(context)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = folder.appendingPathComponent(name(at) + ".json")
        try encoder.encode(HistoryCompare.entry(report, at: at)).write(to: url, options: .atomic)
        let files = scanFiles(folder)
        for old in files.dropLast(max(cap, 1)) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    /// Every readable saved scan, oldest first.
    public static func load(_ context: CleanupContext) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return scanFiles(folder(context)).compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? decoder.decode(HistoryEntry.self, from: $0) }
        }.sorted { $0.at < $1.at }
    }

    /// The newest saved scan made at or before `date`, or — when history is
    /// shorter than that — the oldest there is, flagged as such.
    public static func closest(_ entries: [HistoryEntry], atOrBefore date: Date) -> (entry: HistoryEntry, exact: Bool)? {
        if let match = entries.last(where: { $0.at <= date }) { return (match, true) }
        return entries.first.map { ($0, false) }
    }

    /// What changed between a saved scan and `report`.
    public static func changes(since entry: HistoryEntry, to report: ScanReport, at: Date) -> ScanChanges {
        HistoryCompare.compare(entry, HistoryCompare.entry(report, at: at))
    }

    /// `2026-10-18T21-50-03Z`: sorts by time, safe in a file name.
    static func name(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter.string(from: date)
    }

    /// The saved scans, oldest first: only files named by date, so a stray
    /// file is never mistaken for the newest scan when pruning.
    static func scanFiles(_ folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d{3}Z\.json/) != nil }
            .sorted().map { folder.appendingPathComponent($0) }
    }
}
