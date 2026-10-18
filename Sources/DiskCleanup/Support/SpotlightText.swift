//
//  SpotlightText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  What `mdls -raw` prints for several files: every value, NUL-separated,
//  file after file, each file's attributes in the order of their names
//  sorted — whatever order they were asked in.
//

import Foundation

/// One file as Spotlight records it.
struct SpotlightFile: Equatable {
    let path: String
    let size: Int64?
    let lastUsed: Date?
    let modified: Date?
}

enum SpotlightText {

    static let names = ["kMDItemContentModificationDate", "kMDItemFSSize", "kMDItemLastUsedDate"]

    /// The files' records, or `nil` when the output does not line up with
    /// the files asked about (one vanished between query and read).
    static func files(_ output: Data, paths: [String]) -> [SpotlightFile]? {
        let values = output.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        let trimmed = values.last == "" ? Array(values.dropLast()) : values
        guard trimmed.count == paths.count * names.count else { return nil }
        let order = names.sorted()
        return paths.enumerated().map { index, path in
            var record: [String: String] = [:]
            for (offset, name) in order.enumerated() { record[name] = trimmed[index * names.count + offset] }
            return SpotlightFile(path: path, size: record["kMDItemFSSize"].flatMap { Int64($0) },
                                 lastUsed: date(record["kMDItemLastUsedDate"]), modified: date(record["kMDItemContentModificationDate"]))
        }
    }

    /// `2026-10-15 15:39:01 +0000`; `(null)` is no date.
    static func date(_ text: String?) -> Date? {
        guard let text, text != "(null)" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }
}
