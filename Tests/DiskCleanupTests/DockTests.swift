//
//  DockTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The Dock's icon arrays edited as property lists, and an uninstall that
//  takes an app's icon out and an undo that puts the exact arrays back —
//  all against a Dock held in memory, never this Mac's.
//

import Foundation
import os
import Testing
@testable import DiskCleanup

/// The Dock's preferences in memory: writes stored (unless `sticks` is off),
/// restarts counted.
final class FixtureDock: DockPreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]
    private var restarts = 0
    /// When off, writes report success and change nothing — a Dock that put
    /// its own icons back.
    var sticks = true

    init(_ values: [String: Any]) { self.values = values }

    func value(_ key: String) -> Any? { lock.withLock { values[key] } }
    func set(_ key: String, _ value: Any?) -> Bool {
        lock.withLock { if sticks { values[key] = value } }
        return true
    }
    func restart() -> Bool { lock.withLock { restarts += 1 }; return true }
    var restartCount: Int { lock.withLock { restarts } }
}

struct DockTests {

    /// A Dock tile as the Dock writes one.
    static func tile(_ label: String, id: String?, url: String, guid: Int) -> [String: Any] {
        var data: [String: Any] = [
            "file-label": label, "file-type": 41, "dock-extra": false, "book": Data([0x62, 0x6f, 0x6f, 0x6b, UInt8(guid % 256)]),
            "file-data": ["_CFURLString": url, "_CFURLStringType": 15],
        ]
        if let id { data["bundle-identifier"] = id }
        return ["GUID": guid, "tile-type": "file-tile", "tile-data": data]
    }

    static var spacer: [String: Any] { ["GUID": 9, "tile-type": "spacer-tile", "tile-data": [String: Any]()] }

    @Test func tilesMatchByBundleIDOrByTheAppsPathAndTheRestStayInOrder() {
        let tiles: [Any] = [
            Self.tile("Mail", id: "com.apple.mail", url: "file:///System/Applications/Mail.app/", guid: 1),
            Self.tile("Mosaic", id: "DEV.Mosaic.App", url: "file:///Applications/Mosaic.app/", guid: 2),
            Self.spacer,
            Self.tile("Mosaic copy", id: nil, url: "file:///private/tmp/x/Mosaic%20Copy.app/", guid: 3),
            Self.tile("Notes", id: "com.apple.Notes", url: "file:///System/Applications/Notes.app/", guid: 4),
        ]
        let found = DockTiles.matching(tiles, bundleIDs: ["dev.mosaic.app"], apps: ["/tmp/x/Mosaic Copy.app"])
        #expect(found == [1, 3])
        let kept = DockTiles.removing(tiles, at: found)
        #expect(kept.count == 3)
        #expect(DockTiles.same(kept[0], tiles[0]) && DockTiles.same(kept[1], tiles[2]) && DockTiles.same(kept[2], tiles[4]))
        #expect(DockTiles.matching(tiles, bundleIDs: ["dev.mosaic"], apps: ["/Applications/Mosaic"]).isEmpty)
        #expect(DockTiles.label(tiles[1]) == "Mosaic")
    }

    func dockedMosaic(_ fixture: Fixture) throws -> (FixtureDock, [Any], [Any], CleanupContext) {
        try InstallerFixtures.app("Mosaic", id: "dev.mosaic.app", version: "1.0", in: fixture.home.appendingPathComponent("Applications"))
        let persistent: [Any] = [
            Self.tile("Mail", id: "com.apple.mail", url: "file:///System/Applications/Mail.app/", guid: 1),
            Self.tile("Mosaic", id: "dev.mosaic.app", url: "file://\(fixture.path("Applications/Mosaic.app"))/", guid: 2),
            Self.tile("Notes", id: "com.apple.Notes", url: "file:///System/Applications/Notes.app/", guid: 3),
        ]
        let recent: [Any] = [Self.tile("Mosaic", id: nil, url: "file://\(fixture.path("Applications/Mosaic.app"))/", guid: 7)]
        let dock = FixtureDock(["persistent-apps": persistent, "recent-apps": recent, "tilesize": 48])
        var context = fixture.context()
        context.records = FixtureRecords()
        context.dock = dock
        return (dock, persistent, recent, context)
    }

    @Test func uninstallTakesTheDockIconAndUndoPutsTheExactArraysBack() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (dock, persistent, recent, context) = try dockedMosaic(fixture)
        let catalogue = try Catalogue.builtIn()
        let plan = try Uninstaller.plan("Mosaic", catalogue: catalogue, context: context)
        let icon = try #require(plan.items.first { $0.removal == .dock })
        #expect(icon.evidence["match"] == "exact" && icon.tier == .safe && icon.evidence["dockTiles"] == "2")
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        #expect(taking.contains { $0.id == icon.id })

        let outcomes = try Uninstaller.remove(taking, plan: plan, quit: false, catalogue: catalogue, context: context, batch: "d1")
        #expect(outcomes.first { $0.id == icon.id }?.result == .edited, "\(outcomes)")
        let after = try #require(dock.value("persistent-apps") as? [Any])
        #expect(after.count == 2 && DockTiles.matching(after, bundleIDs: ["dev.mosaic.app"], apps: []).isEmpty)
        #expect(DockTiles.same(after[0], persistent[0]) && DockTiles.same(after[1], persistent[2]))
        #expect((dock.value("recent-apps") as? [Any])?.isEmpty == true)
        #expect(dock.value("tilesize") as? Int == 48)
        #expect(dock.restartCount == 1)
        let entry = try #require(try JournalStore.load(context.journal).first { $0.rule == DockEdit.rule })
        #expect(entry.batch == "d1" && entry.backup != nil)

        let restored = try Restorer.undo("d1", journal: context.journal, context: context)
        #expect(restored.allSatisfy { $0.result == .restored }, "\(restored)")
        #expect(DockTiles.same(dock.value("persistent-apps"), persistent))
        #expect(DockTiles.same(dock.value("recent-apps"), recent))
        // Exactly: the same XML (which sorts keys) as the original, byte for byte.
        func xml(_ value: Any?) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: try #require(value), format: .xml, options: 0)
        }
        #expect(try xml(dock.value("persistent-apps")) == xml(persistent))
        #expect(try xml(dock.value("recent-apps")) == xml(recent))
        #expect(dock.restartCount == 2)
        #expect(try JournalStore.load(context.journal).first { $0.rule == DockEdit.rule }?.restoredAt != nil)
    }

    @Test func undoLeavesADockThatChangedSinceAlone() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (dock, _, _, context) = try dockedMosaic(fixture)
        let catalogue = try Catalogue.builtIn()
        let plan = try Uninstaller.plan("Mosaic", catalogue: catalogue, context: context)
        let icon = try #require(plan.items.first { $0.removal == .dock })
        _ = Remover.remove([icon], catalogue: catalogue, context: context, batch: "d2")
        var changed = try #require(dock.value("persistent-apps") as? [Any])
        changed.append(Self.tile("Safari", id: "com.apple.Safari", url: "file:///Applications/Safari.app/", guid: 11))
        _ = dock.set("persistent-apps", changed)

        let restored = try Restorer.undo("d2", journal: context.journal, context: context)
        #expect(restored.first?.result == .occupied, "\(restored)")
        #expect(DockTiles.same(dock.value("persistent-apps"), changed))
        #expect(dock.restartCount == 1)
    }

    @Test func nothingIsWrittenWhenTheJournalCannotBe() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        var (dock, persistent, _, context) = try dockedMosaic(fixture)
        defer { _ = dock }
        let catalogue = try Catalogue.builtIn()
        let plan = try Uninstaller.plan("Mosaic", catalogue: catalogue, context: context)
        let icon = try #require(plan.items.first { $0.removal == .dock })
        try fixture.file("not-a-folder", bytes: 10)
        context.journal = URL(fileURLWithPath: fixture.path("not-a-folder/journal.json"))
        let outcome = try #require(Remover.remove([icon], catalogue: catalogue, context: context, batch: "d3").first)
        #expect(outcome.result == .failed, "\(outcome)")
        #expect(DockTiles.same(dock.value("persistent-apps"), persistent))
        #expect(dock.restartCount == 0)
    }

    @Test func aDockThatPutsTheIconBackIsAFailureNotASuccess() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (dock, _, _, context) = try dockedMosaic(fixture)
        let catalogue = try Catalogue.builtIn()
        let plan = try Uninstaller.plan("Mosaic", catalogue: catalogue, context: context)
        let icon = try #require(plan.items.first { $0.removal == .dock })
        dock.sticks = false
        let outcome = try #require(Remover.remove([icon], catalogue: catalogue, context: context, batch: "d4").first)
        #expect(outcome.result == .failed, "\(outcome)")
    }

    @Test func noDockIconNoDockItemAndTheCatalogueCannotNameOne() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let (dock, _, _, context) = try dockedMosaic(fixture)
        _ = dock.set("persistent-apps", [Self.tile("Mail", id: "com.apple.mail", url: "file:///System/Applications/Mail.app/", guid: 1)])
        _ = dock.set("recent-apps", nil)
        let plan = try Uninstaller.plan("Mosaic", catalogue: try Catalogue.builtIn(), context: context)
        #expect(!plan.items.contains { $0.removal == .dock })

        let base = try Catalogue.builtIn()
        let rule = try #require(base.rules.first { $0.id == "user-logs" })
        let json = try JSONEncoder().encode(rule)
        var dictionary = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        dictionary["removal"] = "dock"
        let dockRule = try JSONDecoder().decode(Rule.self, from: try JSONSerialization.data(withJSONObject: dictionary))
        let catalogue = Catalogue(version: base.version, protect: base.protect, protectNames: base.protectNames, rules: [dockRule])
        #expect(CatalogueCheck.problems(catalogue, home: fixture.home.path).contains { $0.contains("Dock") })
    }
}
