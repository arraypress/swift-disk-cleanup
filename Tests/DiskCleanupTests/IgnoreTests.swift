//
//  IgnoreTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The ignore list: what an entry names, that an ignored item is still found
//  but totalled apart and never taken — by a category, by its id, by an
//  uninstall, or by the remover itself — and that an unreadable list is an
//  error, never an empty one.
//

import Foundation
import Testing
@testable import DiskCleanup

struct IgnoreTests {

    @Test func anEntryIsAPathARuleOrAnItem() throws {
        let catalogue = try Catalogue.builtIn()
        let home = "/Users/example"
        let path = try IgnoreList.entry(for: "/Users/example/Library/Caches/Foo/", catalogue: catalogue, home: home)
        #expect(path.kind == .path && path.value == "~/Library/Caches/Foo")
        #expect(try IgnoreList.entry(for: "~/Downloads", catalogue: catalogue, home: home).value == "~/Downloads")
        #expect(try IgnoreList.entry(for: "/opt/stuff", catalogue: catalogue, home: home).value == "/opt/stuff")
        #expect(try IgnoreList.entry(for: "user-logs", catalogue: catalogue, home: home).kind == .rule)
        #expect(try IgnoreList.entry(for: "uninstall", catalogue: catalogue, home: home).kind == .rule)
        #expect(try IgnoreList.entry(for: "hf-hub-1a2b3c4d", catalogue: catalogue, home: home).kind == .item)
        #expect(throws: DiskCleanupError.self) { try IgnoreList.entry(for: "not-a-rule", catalogue: catalogue, home: home) }
        #expect(throws: DiskCleanupError.self) { try IgnoreList.entry(for: "~/../etc", catalogue: catalogue, home: home) }

        let list = IgnoreList().adding(path).list
        #expect(!list.adding(path).added)
        #expect(list.removing(path).removed && list.removing(path).list.entries.isEmpty)
    }

    @Test func aPathHoldsWhatIsInItAndWhatHoldsIt() {
        let home = "/Users/example"
        let list = IgnoreList(entries: [IgnoreEntry(kind: .path, value: "~/Library/Caches/Foo/keep")])
        func item(_ path: String, rule: String = "user-caches") -> Item {
            Item(id: ItemID.make(rule: rule, path: path), rule: rule, category: .userCaches, path: path, bytes: 1, tier: .safe,
                 removal: .delete, regenerable: true, owner: nil, newest: nil, visibility: .visible, protected: nil,
                 evidence: [:], note: nil, identity: nil)
        }
        #expect(list.reason(for: item(home + "/Library/Caches/Foo"), home: home) == "ignored (by you): ~/Library/Caches/Foo/keep")
        #expect(list.reason(for: item(home + "/Library/Caches/Foo/keep/inner"), home: home) != nil)
        #expect(list.reason(for: item(home + "/Library/Caches/Foo/keeper"), home: home) == nil)
        #expect(list.reason(for: item(home + "/Library/Caches/Bar"), home: home) == nil)
        let byRule = IgnoreList(entries: [IgnoreEntry(kind: .rule, value: "user-logs")])
        #expect(byRule.reason(for: item(home + "/Library/Logs/x", rule: "user-logs"), home: home) != nil)
        #expect(byRule.reason(for: item(home + "/Library/Logs/x"), home: home) == nil)
        let one = item(home + "/Library/Caches/Bar")
        #expect(IgnoreList(entries: [IgnoreEntry(kind: .item, value: one.id)]).reason(for: one, home: home) != nil)
    }

    @Test func anIgnoredItemIsFoundTotalledApartAndNeverTaken() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        var context = fixture.context()
        let open = Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: [.xcode]))
        let derived = try #require(open.items.first { $0.path.hasSuffix("DerivedData/App-abcdef") })
        let before = try #require(open.categories.first)
        #expect(derived.ignored == nil && before.ignoredBytes == 0)

        context.ignore = IgnoreList(entries: [IgnoreEntry(kind: .path, value: "~/Library/Developer/Xcode/DerivedData")])
        let report = Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: [.xcode]))
        let held = try #require(report.items.first { $0.id == derived.id })
        #expect(held.ignored == "ignored (by you): ~/Library/Developer/Xcode/DerivedData")
        let totals = try #require(report.categories.first)
        #expect(totals.ignoredBytes == (derived.bytes ?? -1))
        #expect(totals.bytes == before.bytes)
        #expect(totals.safeBytes + totals.ignoredBytes == before.safeBytes)

        // Not by its category, not by its id, and not by the remover itself.
        let wanted = try Planner.targets(["xcode", derived.id])
        let picked = try Planner.select(wanted, from: report, includeReview: true, olderThanDays: nil, now: context.now)
        #expect(!picked.take.contains { $0.id == derived.id })
        #expect(picked.held.contains { $0.item.id == derived.id && $0.reason.hasPrefix("ignored (by you)") })
        let outcome = try #require(Remover.remove([derived], catalogue: catalogue, context: context).first)
        #expect(outcome.result == .skipped && outcome.reason?.hasPrefix("ignored (by you)") == true)
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/App-abcdef"))
    }

    @Test func anUninstallOffersNothingIgnored() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try InstallerFixtures.app("Mosaic", id: "dev.mosaic.app", version: "1.0", in: fixture.home.appendingPathComponent("Applications"))
        try fixture.file("Library/Preferences/dev.mosaic.app.plist", bytes: 500)
        var context = fixture.context()
        context.records = FixtureRecords()
        context.ignore = IgnoreList(entries: [IgnoreEntry(kind: .path, value: "~/Library/Preferences/dev.mosaic.app.plist")])
        let plan = try Uninstaller.plan("Mosaic", catalogue: try Catalogue.builtIn(), context: context)
        let prefs = try #require(plan.items.first { $0.path.hasSuffix("dev.mosaic.app.plist") })
        #expect(prefs.ignored != nil)
        let picked = Uninstaller.select(plan, ids: [prefs.id], includeReview: false)
        #expect(!picked.take.contains { $0.id == prefs.id })
        #expect(picked.held.contains { $0.0.id == prefs.id })
        #expect(picked.take.contains { $0.path.hasSuffix("Mosaic.app") })
    }

    @Test func anUnreadableListIsAnErrorAndAMissingOneIsEmpty() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let url = URL(fileURLWithPath: fixture.path(".config/arraypress/diskmaid/ignore.json"))
        #expect(try IgnoreStore.load(url).entries.isEmpty)
        let list = IgnoreList(entries: [IgnoreEntry(kind: .rule, value: "user-logs", added: Date(timeIntervalSince1970: 1_800_000_000))])
        try IgnoreStore.save(list, to: url)
        #expect(try IgnoreStore.load(url) == list)
        try Data("{ not json".utf8).write(to: url)
        #expect(throws: DiskCleanupError.self) { try IgnoreStore.load(url) }
    }
}
