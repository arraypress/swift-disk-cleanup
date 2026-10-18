//
//  BigFilesTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Big files through stand-in mdfind and mdls in the fixture's bin: what is
//  left out (~/Library, what a rule owns, packages, protected places), how
//  "unused" is judged, the never-opened label, and Trash with undo.
//

import Foundation
import Testing
@testable import DiskCleanup

struct BigFilesTests {

    static let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!

    /// Spotlight's records by file name: modified, size, last used — the order mdls sorts them in.
    static let records = [
        "old.mov": ["2025-01-01 10:00:00 +0000", "3000000", "2025-01-02 10:00:00 +0000"],
        "recent.mov": ["2026-10-01 10:00:00 +0000", "2000000", "2026-10-10 10:00:00 +0000"],
        "never.iso": ["2025-02-01 10:00:00 +0000", "2000000", "(null)"],
        "fresh.iso": ["2026-10-17 10:00:00 +0000", "2000000", "(null)"],
        "reused.mov": ["2024-03-01 10:00:00 +0000", "2000000", "2026-10-12 10:00:00 +0000"],
    ]

    func make() throws -> Fixture {
        let fixture = try Fixture.make()
        try fixture.file("Movies/old.mov", bytes: 3_000_000)
        try fixture.file("Movies/recent.mov", bytes: 2_000_000)
        try fixture.file("Downloads/never.iso", bytes: 2_000_000)
        try fixture.file("Downloads/fresh.iso", bytes: 2_000_000)
        try fixture.file("Downloads/reused.mov", bytes: 2_000_000)
        try fixture.file("Library/Application Support/Thing/huge.bin", bytes: 2_000_000)
        try fixture.file("Developer/swift-old/.build/huge.o", bytes: 2_000_000)
        try fixture.file("Models/voice.aimodel/main.mlirb", bytes: 2_000_000)
        try fixture.file(".ssh/huge_key", bytes: 2_000_000)
        let found = ["Movies/old.mov", "Movies/recent.mov", "Downloads/never.iso", "Downloads/fresh.iso", "Downloads/reused.mov",
                     "Library/Application Support/Thing/huge.bin", "Developer/swift-old/.build/huge.o",
                     "Models/voice.aimodel/main.mlirb", ".ssh/huge_key"].map(fixture.path).joined(separator: "\n")
        try fixture.file("data/found.txt", contents: found + "\n")
        var cases = ""
        for (name, values) in BigFilesTests.records {
            cases += "    \(name)) printf '%s\\000%s\\000%s\\000' '\(values[0])' '\(values[1])' '\(values[2])' ;;\n"
        }
        let tools = [
            "mdfind": "echo \"$@\" > '\(fixture.path("data/mdfind-args.txt"))'\ncat '\(fixture.path("data/found.txt"))'",
            "mdls": "while [ $# -gt 0 ]; do case \"$1\" in -raw) shift ;; -nullMarker|-name) shift 2 ;; *) break ;; esac; done\n"
                + "for f in \"$@\"; do\n  case \"$(basename \"$f\")\" in\n\(cases)    *) printf '(null)\\000(null)\\000(null)\\000' ;;\n  esac\ndone",
        ]
        for (name, body) in tools {
            try fixture.file("bin/" + name, contents: "#!/bin/sh\n" + body + "\n")
            _ = CommandRunner.run("/bin/chmod", ["755", fixture.path("bin/" + name)], timeout: 10)
        }
        return fixture
    }

    func names(_ items: [Item]) -> [String] { items.map { PathText.lastComponent($0.path) } }

    @Test func onlyAPersonsOwnFilesAreListedBiggestFirst() throws {
        let fixture = try make()
        defer { fixture.remove() }
        let found = BigFiles.find(in: fixture.home.path, overBytes: 1_000_000, unusedDays: nil, catalogue: try Catalogue.builtIn(),
                                  context: fixture.context(), now: BigFilesTests.now)
        #expect(names(found.items).first == "old.mov")
        #expect(Set(names(found.items)) == ["old.mov", "recent.mov", "never.iso", "fresh.iso", "reused.mov", "huge_key"], "\(names(found.items))")
        // Downloads: review, to the Trash. Movies and ~/.ssh are protected: shown, never taken.
        let downloads = found.items.filter { $0.path.contains("/Downloads/") }
        #expect(downloads.count == 3 && downloads.allSatisfy { $0.tier == .review && $0.removal == .trash && $0.protected == nil })
        let held = found.items.filter { !$0.path.contains("/Downloads/") }
        #expect(held.count == 3 && held.allSatisfy { $0.tier == .report && $0.protected != nil })
        let args = try String(contentsOfFile: fixture.path("data/mdfind-args.txt"), encoding: .utf8)
        #expect(args.contains("-onlyin \(fixture.home.path) kMDItemFSSize > 1000000"))
        let never = try #require(found.items.first { $0.path.hasSuffix("never.iso") })
        #expect(never.evidence["lastUsed"] == "never opened (by Spotlight's record)")
        #expect(never.evidence["modified"]?.hasPrefix("2025-02-01") == true)
    }

    @Test func unusedGoesByLastUseOrElseByChange() throws {
        let fixture = try make()
        defer { fixture.remove() }
        let found = BigFiles.find(in: fixture.home.path, overBytes: 1_000_000, unusedDays: 180, catalogue: try Catalogue.builtIn(),
                                  context: fixture.context(), now: BigFilesTests.now)
        #expect(Set(names(found.items)) == ["old.mov", "never.iso", "huge_key"], "\(names(found.items))")
    }

    @Test func chosenFilesGoToTheTrashAndComeBack() throws {
        let fixture = try make()
        defer { fixture.remove() }
        let context = fixture.context()
        let found = BigFiles.find(in: fixture.home.path, overBytes: 1_000_000, unusedDays: nil, catalogue: try Catalogue.builtIn(),
                                  context: context, now: BigFilesTests.now)
        let never = try #require(found.items.first { $0.path.hasSuffix("never.iso") })
        let old = try #require(found.items.first { $0.path.hasSuffix("old.mov") })
        #expect(BigFiles.select(found.items, ids: [], all: false).take.isEmpty)
        // Every one with --review: still never what is protected.
        #expect(Set(BigFiles.select(found.items, ids: [], all: true).take.map(\.path)) == Set(found.items.filter { $0.protected == nil }.map(\.path)))
        #expect(BigFiles.select(found.items, ids: [old.id], all: false).held.map(\.0.id) == [old.id])
        let take = BigFiles.select(found.items, ids: [never.id], all: false).take
        #expect(take.map(\.id) == [never.id])
        let outcomes = Remover.remove(take, catalogue: try Catalogue.builtIn(), context: context, batch: "b1")
        #expect(outcomes.map(\.result) == [.trashed])
        #expect(!fixture.exists("Downloads/never.iso") && fixture.exists("Downloads/fresh.iso"))
        _ = try Restorer.undo("b1", journal: context.journal)
        #expect(fixture.exists("Downloads/never.iso"))
    }

    @Test func packagesAndTheLastDoorAreAskable() throws {
        #expect(BigFiles.insidePackage("/Users/x/Music/Music/Music Library.musiclibrary/Library.musicdb"))
        #expect(BigFiles.insidePackage("/Users/x/Movies/TV/TV Library.tvlibrary/db"))
        #expect(BigFiles.insidePackage("/Users/x/Pictures/Photos Library.photoslibrary/originals/A/1.heic"))
        #expect(!BigFiles.insidePackage("/Users/x/Music/song.mp3"))
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        let song = fixture.path("Music/song.mp3")
        #expect(Remover.refusal(for: song, catalogue: catalogue, context: fixture.context())?.contains("protected") == true)
        #expect(Remover.refusal(for: song, catalogue: catalogue, context: fixture.context(), allowing: ["~/Music"]) == nil)
        #expect(Remover.refusal(for: fixture.path("Music"), catalogue: catalogue, context: fixture.context(), allowing: ["~/Music"]) != nil)
        #expect(Remover.refusal(for: fixture.path("Downloads/a.bin"), catalogue: catalogue, context: fixture.context()) == nil)
    }

    @Test func mdlsOutputIsReadInSortedOrderAndMisalignmentRefused() {
        let output = Data("2025-01-01 10:00:00 +0000\u{0}42\u{0}(null)\u{0}2026-01-01 10:00:00 +0000\u{0}7\u{0}2026-02-01 10:00:00 +0000\u{0}".utf8)
        let files = SpotlightText.files(output, paths: ["/a", "/b"])
        #expect(files?.map(\.size) == [42, 7])
        #expect(files?[0].lastUsed == nil && files?[0].modified != nil && files?[1].lastUsed != nil)
        #expect(SpotlightText.files(output, paths: ["/a", "/b", "/c"]) == nil)
        #expect(SpotlightText.date("(null)") == nil)
    }
}
