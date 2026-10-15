//
//  RemovalTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import DiskCleanup

struct RemovalTests {

    func scan(_ fixture: Fixture, _ categories: Set<CleanupCategory>) throws -> (ScanReport, CleanupContext, Catalogue) {
        let catalogue = try Catalogue.builtIn()
        let context = fixture.context()
        return (Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: categories)), context, catalogue)
    }

    @Test func cacheIsDeletedLeftoverIsTrashedAndUndone() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (report, context, catalogue) = try scan(fixture, [.xcode, .leftovers])
        let derived = try #require(report.items.first { $0.rule == "xcode-derived-data" })
        let leftover = try #require(report.items.first { $0.path == fixture.path("Library/Caches/com.example.gone") })
        let outcomes = Remover.remove([derived, leftover], catalogue: catalogue, context: context, batch: "b1")
        #expect(outcomes.map(\.result) == [.deleted, .trashed])
        #expect(!FileManager.default.fileExists(atPath: derived.path))
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        // Into the fixture's own Trash, never the real one, and journalled.
        let landed = try #require(outcomes[1].to)
        #expect(landed.hasPrefix(fixture.path(".Trash")))
        let journal = try JournalStore.load(context.journal)
        #expect(journal.count == 1)
        #expect(journal[0].original == leftover.path)
        // Undo puts it back; a second undo has nothing left to do.
        let restored = try Restorer.undo(nil, journal: context.journal)
        #expect(restored.map(\.result) == [.restored])
        #expect(FileManager.default.fileExists(atPath: leftover.path + "/data"))
        #expect(throws: DiskCleanupError.self) { try Restorer.undo(nil, journal: context.journal) }
        #expect(try Restorer.undo("b1", journal: context.journal).map(\.result) == [.alreadyRestored])
    }

    @Test func undoNeverOverwrites() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (report, context, catalogue) = try scan(fixture, [.leftovers])
        let leftover = try #require(report.items.first { $0.path == fixture.path("Library/Caches/com.example.gone") })
        _ = Remover.remove([leftover], catalogue: catalogue, context: context, batch: "b2")
        try fixture.file("Library/Caches/com.example.gone/new", contents: "came back")
        #expect(try Restorer.undo("b2", journal: context.journal).map(\.result) == [.occupied])
        #expect(try String(contentsOfFile: leftover.path + "/new", encoding: .utf8) == "came back")
    }

    @Test func anythingChangedSinceMeasuringIsSkipped() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (report, context, catalogue) = try scan(fixture, [.xcode])
        let derived = try #require(report.items.first { $0.rule == "xcode-derived-data" })
        try fixture.file("Library/Developer/Xcode/DerivedData/App-abcdef/Build/new.o", bytes: 40_000)
        let outcome = try #require(Remover.remove([derived], catalogue: catalogue, context: context).first)
        #expect(outcome.result == .skipped)
        #expect(outcome.reason?.contains("since it was measured") == true)
        #expect(FileManager.default.fileExists(atPath: derived.path))
    }

    @Test func protectedAndReportItemsNeverGo() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        let context = fixture.context()
        // A hand-made item aimed at ~/.ssh — as if a catalogue bug had produced it.
        let ssh = Item(id: "evil-00000000", rule: "evil", category: .userCaches, path: fixture.path(".ssh"), bytes: 1,
                       tier: .safe, removal: .delete, regenerable: true, owner: nil, newest: nil, visibility: .visible,
                       protected: nil, evidence: [:], note: nil, identity: nil)
        let report = Item(id: "evil-00000001", rule: "evil", category: .userCaches, path: fixture.path("Library/Logs/old.log"),
                          bytes: 1, tier: .report, removal: .delete, regenerable: true, owner: nil, newest: nil,
                          visibility: .visible, protected: nil, evidence: [:], note: nil, identity: nil)
        let outcomes = Remover.remove([ssh, report], catalogue: catalogue, context: context)
        #expect(outcomes.map(\.result) == [.skipped, .skipped])
        #expect(FileManager.default.fileExists(atPath: fixture.path(".ssh/id_ed25519")))
        #expect(FileManager.default.fileExists(atPath: fixture.path("Library/Logs/old.log")))
    }

    @Test func ownersCommandRunsFromTheFixtureBinOnly() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (report, context, catalogue) = try scan(fixture, [.packageCaches])
        let uv = try #require(report.items.first { $0.rule == "uv-cache" })
        #expect(uv.removal == .command(["uv", "cache", "prune"]))
        let outcome = try #require(Remover.remove([uv], catalogue: catalogue, context: context).first)
        #expect(outcome.result == .commanded)
        #expect(try String(contentsOfFile: fixture.path("uv-ran"), encoding: .utf8) == "cache prune\n")
        #expect((outcome.bytes ?? 0) >= 30_000)
        // brew is not in <home>/bin, so the fixture never sees the real Homebrew.
        #expect(!report.items.contains { $0.rule == "homebrew-cleanup" })
    }

    @Test func aMissingToolFailsCleanly() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file(".npm/_cacache/x", bytes: 1000)
        try fixture.age(".npm/_cacache", days: 3)
        let (report, context, catalogue) = try scan(fixture, [.packageCaches])
        let npm = try #require(report.items.first { $0.rule == "npm-cache" })
        let outcome = try #require(Remover.remove([npm], catalogue: catalogue, context: context).first)
        #expect(outcome.result == .failed)
        #expect(outcome.reason?.contains("not installed") == true)
        #expect(FileManager.default.fileExists(atPath: fixture.path(".npm/_cacache/x")))
    }
}
