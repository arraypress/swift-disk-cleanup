//
//  ChatMediaTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  A WhatsApp container in miniature: a database that lists one recording
//  and its thumbnail, five unlisted clones of the recording (what a looping
//  download leaves) and one unlisted file of its own.
//

import Darwin
import Foundation
import Testing
@testable import DiskCleanup

struct ChatMediaTests {

    static let container = "Library/Group Containers/group.net.whatsapp.WhatsApp.shared"

    /// Builds the container under `home` with `schema` as the media table.
    static func make(in home: String,
                     schema: String = "CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMEDIALOCALPATH VARCHAR, ZXMPPTHUMBPATH VARCHAR);") throws {
        let root = home + "/" + container
        let chat = root + "/Message/Media/267645198848181@lid/6/2"
        try FileManager.default.createDirectory(atPath: chat, withIntermediateDirectories: true)
        try Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 13) }).write(to: URL(fileURLWithPath: chat + "/kept.mp3"))
        try Data(repeating: 3, count: 2_000).write(to: URL(fileURLWithPath: chat + "/kept.thumb"))
        for index in 0..<5 {
            #expect(clonefile(chat + "/kept.mp3", chat + "/copy-\(index).mp3", 0) == 0)
        }
        try Data(repeating: 9, count: 200_000).write(to: URL(fileURLWithPath: chat + "/stray.zip"))
        var sql = schema
        if schema.contains("ZMEDIALOCALPATH") {
            sql += " INSERT INTO ZWAMEDIAITEM (ZMEDIALOCALPATH, ZXMPPTHUMBPATH) VALUES ('Media/267645198848181@lid/6/2/kept.mp3', 'Media/267645198848181@lid/6/2/kept.thumb');"
            sql += " INSERT INTO ZWAMEDIAITEM (ZMEDIALOCALPATH) VALUES (NULL);"
        }
        let output = CommandRunner.run("/usr/bin/sqlite3", [root + "/ChatStorage.sqlite", sql], timeout: 30)
        #expect(output?.succeeded == true)
    }

    func home() -> String { "/private/tmp/diskmaid-chat-\(UUID().uuidString.prefix(8))" }

    @Test func unlistedMediaIsCountedWithoutItsClones() throws {
        let home = home()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try ChatMediaTests.make(in: home)
        let unlisted = try ChatMedia.whatsAppUnlisted(container: home + "/" + ChatMediaTests.container).get()
        #expect(unlisted.listed == 2)
        #expect(unlisted.files == 6)
        // Five clones of a listed file add nothing; the stray zip adds itself.
        #expect(unlisted.bytes >= 200_000 && unlisted.bytes < 270_000, "\(unlisted.bytes)")
    }

    @Test func aMissingOrStrangeDatabaseIsNotChecked() throws {
        let strange = home()
        defer { try? FileManager.default.removeItem(atPath: strange) }
        try ChatMediaTests.make(in: strange, schema: "CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZPATH VARCHAR);")
        let container = strange + "/" + ChatMediaTests.container
        #expect(throws: ChatMedia.Reason.self) { try ChatMedia.whatsAppUnlisted(container: container).get() }
        try FileManager.default.removeItem(atPath: container + "/ChatStorage.sqlite")
        #expect(throws: ChatMedia.Reason.self) { try ChatMedia.whatsAppUnlisted(container: container).get() }
    }

    @Test func theChatStoreSaysWhatItsDatabaseLost() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try ChatMediaTests.make(in: fixture.home.path)
        let report = Scanner.scan(catalogue: try Catalogue.builtIn(), context: fixture.context(),
                                  options: ScanScope(categories: [.reportOnly]))
        let store = try #require(report.items.first { $0.path == fixture.path(ChatMediaTests.container) })
        #expect(store.tier == .report)
        #expect(store.evidence["unlistedMediaFiles"] == "6")
        #expect(store.evidence["listedMedia"] == "2")
        #expect(report.notes.contains { $0.hasPrefix("WhatsApp: 6 media file(s)") }, "\(report.notes)")
        // Two of the rule's globs match this container (`group.net…` and `*.net…`): one item, one note.
        #expect(report.items.filter { $0.path == fixture.path(ChatMediaTests.container) }.count == 1)
        #expect(report.notes.filter { $0.hasPrefix("WhatsApp:") }.count == 1, "\(report.notes)")
    }
}
