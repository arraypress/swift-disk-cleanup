//
//  HistoryTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Saved scans and what changed between two: only categories both scans
//  covered, items by id, biggest change first; the store capped, closest
//  at-or-before found, unreadable files skipped.
//

import Foundation
import Testing
@testable import DiskCleanup

struct HistoryTests {

    func item(_ id: String, _ category: String, _ bytes: Int64?) -> HistoryItem {
        HistoryItem(id: id, path: "/x/\(id)", rule: "r", category: category, bytes: bytes)
    }

    @Test func onlySharedCategoriesCompareAndTheBiggestChangeComesFirst() {
        let day: TimeInterval = 86_400
        let before = HistoryEntry(at: Date(timeIntervalSince1970: 0), categories: ["xcode": 140, "build-folders": 50], items: [
            item("grows", "xcode", 100), item("goes", "xcode", 40), item("unmeasured", "xcode", nil),
            item("other-category", "build-folders", 50), item("same", "xcode", 7), item("refused-now", "xcode", 30),
        ])
        let after = HistoryEntry(at: Date(timeIntervalSince1970: 7 * day), categories: ["xcode": 377], items: [
            item("grows", "xcode", 300), item("arrives", "xcode", 70), item("unmeasured", "xcode", nil), item("same", "xcode", 7),
            // Still there, just not measurable this time: not "gone".
            item("refused-now", "xcode", nil),
        ])
        let changes = HistoryCompare.compare(before, after)
        #expect(changes.items.map(\.id) == ["grows", "arrives", "goes"])
        #expect(changes.items.map(\.status) == ["grew", "new", "gone"])
        #expect(changes.items.map(\.deltaBytes) == [200, 70, -40])
        #expect(changes.grewBytes == 270 && changes.shrankBytes == 40 && changes.netBytes == 230)
        // build-folders was not scanned the second time: its item is not "gone".
        #expect(changes.categories.map(\.id) == ["xcode"] && changes.categories[0].deltaBytes == 237)
    }

    @Test func theStoreKeepsTheNewestAndFindsTheClosest() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let context = fixture.context()
        let report = ScanReport(categories: [], items: [], notVisible: [], notes: [], seconds: 0)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<5 {
            try HistoryStore.save(report, at: base.addingTimeInterval(Double(day) * 86_400), context: context, cap: 3)
        }
        try Data("not json".utf8).write(to: HistoryStore.folder(context).appendingPathComponent("zz-broken.json"))
        try Data("{}".utf8).write(to: HistoryStore.folder(context).appendingPathComponent("notes.txt"))
        let entries = HistoryStore.load(context)
        #expect(entries.map(\.at) == (2..<5).map { base.addingTimeInterval(Double($0) * 86_400) })
        let closest = try #require(HistoryStore.closest(entries, atOrBefore: base.addingTimeInterval(3.5 * 86_400)))
        #expect(closest.entry.at == base.addingTimeInterval(3 * 86_400) && closest.exact)
        let older = try #require(HistoryStore.closest(entries, atOrBefore: base))
        #expect(older.entry.at == base.addingTimeInterval(2 * 86_400) && !older.exact)
        #expect(HistoryStore.closest([], atOrBefore: base) == nil)
        // A stray file is never taken for the newest scan when pruning.
        try HistoryStore.save(report, at: base.addingTimeInterval(5 * 86_400), context: context, cap: 3)
        #expect(HistoryStore.load(context).count == 3)
        #expect(FileManager.default.fileExists(atPath: HistoryStore.folder(context).appendingPathComponent("zz-broken.json").path))
    }

    @Test func aRealScanRoundTripsThroughTheStore() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let context = fixture.context()
        let first = Scanner.scan(catalogue: try Catalogue.builtIn(), context: context, options: ScanScope(categories: [.buildFolders]))
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        try HistoryStore.save(first, at: saved, context: context)
        try fixture.file("Developer/swift-old/.build/debug/more.o", bytes: 400_000)
        let second = Scanner.scan(catalogue: try Catalogue.builtIn(), context: context, options: ScanScope(categories: [.buildFolders]))
        let entry = try #require(HistoryStore.load(context).first)
        let changes = HistoryStore.changes(since: entry, to: second, at: Date())
        let grew = try #require(changes.items.first)
        #expect(grew.path == fixture.path("Developer/swift-old/.build") && grew.status == "grew" && grew.deltaBytes >= 400_000)
        #expect(changes.grewBytes >= 400_000)
    }
}
