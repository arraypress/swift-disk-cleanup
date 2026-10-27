//
//  ChatMedia.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  WhatsApp keeps each chat's media under Message/Media and lists every file
//  in ChatStorage.sqlite (ZWAMEDIAITEM). A file no row names is one WhatsApp
//  has lost track of — a deleted chat's media, or a download that looped (one
//  chat once held 72,000 clones of three files). The database is opened
//  read-only and only read; missing, locked or shaped differently means "not
//  checked", never "nothing unlisted". It is read through
//  swift-sqlite-reader, waiting up to two seconds for WhatsApp's lock.
//

import Darwin
import Foundation
import SQLiteReader

enum ChatMedia {

    /// Media files under Message/Media that the database does not list.
    struct Unlisted: Equatable {
        var files = 0
        /// Allocated bytes, less blocks shared with a listed file as a clone.
        var bytes: Int64 = 0
        /// Files the database does list.
        var listed = 0
    }

    /// The columns that name a file, relative to `Message/`.
    static let pathColumns = ["ZMEDIALOCALPATH", "ZTHUMBNAILLOCALPATH", "ZXMPPTHUMBPATH"]

    /// What WhatsApp's `container` holds in Message/Media that its database
    /// does not list, or why that could not be told.
    static func whatsAppUnlisted(container: String) -> Result<Unlisted, Reason> {
        let media = container + "/Message/Media"
        let database = container + "/ChatStorage.sqlite"
        guard PathProbe.isDirectory(media) else { return .failure(Reason("no Message/Media")) }
        guard PathProbe.isFile(database) else { return .failure(Reason("no ChatStorage.sqlite")) }
        let listed: Set<String>
        switch listedPaths(database) {
        case .success(let paths): listed = paths
        case .failure(let reason): return .failure(reason)
        }

        var listedFiles: [(path: String, allocated: Int64)] = []
        var unlistedFiles: [(path: String, allocated: Int64)] = []
        guard let walker = FileManager.default.enumerator(atPath: media) else { return .failure(Reason("Message/Media unreadable")) }
        for case let relative as String in walker {
            let path = media + "/" + relative
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_flags & UInt32(SF_DATALESS) == 0 else { continue }
            let allocated = Int64(info.st_blocks) * 512
            if listed.contains("Media/" + relative) {
                listedFiles.append((path, allocated))
            } else {
                unlistedFiles.append((path, allocated))
            }
        }
        // Listed files first, so an unlisted clone of one adds only its own blocks.
        var tally = Sizer.CloneTally()
        for file in listedFiles { _ = tally.add(file.path, allocated: file.allocated) }
        var result = Unlisted(listed: listedFiles.count)
        for file in unlistedFiles {
            result.files += 1
            result.bytes += tally.add(file.path, allocated: file.allocated)
        }
        return .success(result)
    }

    /// Every path the media table names, or why it could not be read.
    static func listedPaths(_ database: String) -> Result<Set<String>, Reason> {
        let store: SQLiteReader
        do {
            store = try SQLiteReader(path: URL(fileURLWithPath: database), opening: .readOnly, busyTimeout: 2)
        } catch {
            return .failure(openingFailure(error))
        }
        let columns = ((try? store.rows("SELECT name FROM pragma_table_info('ZWAMEDIAITEM')")) ?? []).compactMap { $0[0].decodedString }
        guard columns.contains("ZMEDIALOCALPATH") else { return .failure(Reason("ChatStorage.sqlite is not the shape expected")) }
        var paths = Set<String>()
        for column in pathColumns where columns.contains(column) {
            guard let rows = try? store.rows("SELECT \(column) FROM ZWAMEDIAITEM WHERE \(column) IS NOT NULL") else {
                return .failure(Reason("ChatStorage.sqlite could not be read (WhatsApp may have it locked)"))
            }
            paths.formUnion(rows.compactMap { $0[0].decodedString })
        }
        return .success(paths)
    }

    /// Why a store did not open: a file that opens but is no database reads
    /// as the wrong shape, as SQLite's own lazy open once reported it;
    /// anything else would not open.
    private static func openingFailure(_ error: SQLiteReaderError) -> Reason {
        if case .unreadable(_, let reason) = error,
           ["not a database", "malformed", "file is encrypted"].contains(where: reason.lowercased().contains) {
            return Reason("ChatStorage.sqlite is not the shape expected")
        }
        return Reason("ChatStorage.sqlite would not open")
    }

    struct Reason: Error, Equatable {
        let text: String
        init(_ text: String) { self.text = text }
    }
}
