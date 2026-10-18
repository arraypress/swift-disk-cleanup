//
//  UninstallTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Uninstalls in a fixture home: receipts, signatures, launchd and quitting
//  answered by FixtureRecords, apps from the fixture's Applications, and
//  /Library read from <home>/root — never this Mac's own.
//

import Foundation
import os
import Testing
@testable import DiskCleanup

/// pkgutil, codesign and launchctl, answered from tables; quits and bootouts recorded.
final class FixtureRecords: InstallRecords {
    let receipts: [String: PackageReceipt]
    let teams: [String: String]
    private let calls = OSAllocatedUnfairLock(initialState: (quits: [String](), bootouts: [String]()))

    init(receipts: [PackageReceipt] = [], teams: [String: String] = [:]) {
        self.receipts = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        self.teams = teams
    }

    var quits: [String] { calls.withLock { $0.quits } }
    var bootouts: [String] { calls.withLock { $0.bootouts } }

    func packageIDs() -> [String]? { receipts.keys.sorted() }
    func receipt(_ id: String) -> PackageReceipt? { receipts[id] }
    func teamID(appAt path: String) -> String? { teams[PathText.lastComponent(path)] }
    func quit(_ bundleID: String) -> Bool { calls.withLock { $0.quits.append(bundleID) }; return false }
    func bootout(label: String) -> Bool { calls.withLock { $0.bootouts.append(label) }; return true }
}

struct UninstallTests {

    func context(_ fixture: Fixture, records: FixtureRecords, lookup: FixtureLookup = FixtureLookup()) -> CleanupContext {
        var context = fixture.context(lookup: lookup)
        context.records = records
        return context
    }

    func plan(_ target: String, _ fixture: Fixture, records: FixtureRecords, lookup: FixtureLookup = FixtureLookup()) throws -> UninstallPlan {
        try Uninstaller.plan(target, catalogue: try Catalogue.builtIn(), context: context(fixture, records: records, lookup: lookup))
    }

    func match(_ plan: UninstallPlan, _ relative: String, in fixture: Fixture) -> String? {
        plan.items.first { $0.path == fixture.path(relative) }?.evidence["match"]
    }

    func app(_ name: String, id: String, in fixture: Fixture) throws {
        try InstallerFixtures.app(name, id: id, version: "1.0", in: fixture.home.appendingPathComponent("Applications"))
    }

    /// A plug-in bundle with its own Info.plist.
    func plugIn(_ relative: String, id: String, in fixture: Fixture) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        try fixture.file(relative + "/Contents/Info.plist", contents: String(decoding: plist, as: UTF8.self))
    }

    func launchAgent(_ relative: String, label: String, program: String, in fixture: Fixture) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Label": label, "Program": program], format: .xml, options: 0)
        try fixture.file(relative, contents: String(decoding: plist, as: UTF8.self))
    }

    // MARK: An installed app

    @Test func anInstalledAppTakesItsOwnAndUndoPutsItBack() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try app("Mosaic", id: "dev.mosaic.app", in: fixture)
        try fixture.file("Library/Containers/dev.mosaic.app/Data/state.db", bytes: 8_000)
        try fixture.file("Library/Preferences/dev.mosaic.app.plist", bytes: 500)
        try fixture.file("Library/Caches/dev.mosaic.app/blob", bytes: 9_000)
        try fixture.file("Library/Caches/dev.someone.else/blob", bytes: 9_000)
        try launchAgent("Library/LaunchAgents/dev.mosaic.helper.plist", label: "dev.mosaic.helper",
                        program: fixture.path("Applications/Mosaic.app/Contents/MacOS/helper"), in: fixture)
        try fixture.file("Library/Group Containers/ABCDE12345.dev.mosaic.shared/x", bytes: 1_000)
        try fixture.file("Library/Application Support/Mosaic/library.json", bytes: 1_000)
        let records = FixtureRecords(teams: ["Mosaic.app": "ABCDE12345"])

        let plan = try plan("Mosaic", fixture, records: records)
        #expect(plan.identity.bundleIDs == ["dev.mosaic.app"])
        #expect(plan.identity.teamIDs == ["ABCDE12345"])
        #expect(match(plan, "Applications/Mosaic.app", in: fixture) == "exact")
        #expect(match(plan, "Library/Containers/dev.mosaic.app", in: fixture) == "exact")
        #expect(match(plan, "Library/Preferences/dev.mosaic.app.plist", in: fixture) == "exact")
        #expect(match(plan, "Library/Caches/dev.mosaic.app", in: fixture) == "exact")
        #expect(match(plan, "Library/LaunchAgents/dev.mosaic.helper.plist", in: fixture) == "exact")
        #expect(match(plan, "Library/Group Containers/ABCDE12345.dev.mosaic.shared", in: fixture) == "likely")
        #expect(match(plan, "Library/Application Support/Mosaic", in: fixture) == "review")
        #expect(match(plan, "Library/Caches/dev.someone.else", in: fixture) == nil)
        #expect(plan.items.allSatisfy { $0.protected == nil && $0.removal == .trash }, "\(plan.items.map { ($0.path, $0.protected) })")

        let catalogue = try Catalogue.builtIn()
        let context = context(fixture, records: records)
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        #expect(taking.count == 6)
        let outcomes = try Uninstaller.remove(taking, plan: plan, quit: false, catalogue: catalogue, context: context, batch: "u1")
        #expect(outcomes.allSatisfy { $0.result == .trashed }, "\(outcomes)")
        #expect(records.bootouts == ["dev.mosaic.helper"])
        #expect(!fixture.exists("Applications/Mosaic.app"))
        #expect(!fixture.exists("Library/Preferences/dev.mosaic.app.plist"))
        #expect(fixture.exists("Library/Application Support/Mosaic"))   // review: only when asked
        #expect(fixture.exists("Library/Caches/dev.someone.else"))

        let restored = try Restorer.undo("u1", journal: context.journal)
        #expect(restored.count == 6 && restored.allSatisfy { $0.result == .restored }, "\(restored)")
        #expect(fixture.exists("Applications/Mosaic.app"))
        #expect(fixture.exists("Library/Preferences/dev.mosaic.app.plist"))
        #expect(fixture.exists("Library/Group Containers/ABCDE12345.dev.mosaic.shared/x"))
    }

    // MARK: A gone app, found by its receipts

    static func valhalla(_ fixture: Fixture) throws -> FixtureRecords {
        let tests = UninstallTests()
        try tests.plugIn("root/Library/Audio/Plug-Ins/Components/ValhallaRoom.component", id: "com.valhalladsp.ValhallaRoom", in: fixture)
        try tests.plugIn("root/Library/Audio/Plug-Ins/VST/ValhallaRoom.vst", id: "com.valhalladsp.ValhallaRoom", in: fixture)
        try tests.plugIn("root/Library/Audio/Plug-Ins/VST3/ValhallaRoom.vst3", id: "com.valhalladsp.ValhallaRoom", in: fixture)
        try tests.plugIn("root/Library/Application Support/Avid/Audio/Plug-Ins/ValhallaRoom.aaxplugin", id: "com.valhalladsp.ValhallaRoom", in: fixture)
        try tests.plugIn("root/Library/Application Support/Avid/Audio/Plug-Ins/Other.aaxplugin", id: "com.other.Other", in: fixture)
        try tests.plugIn("root/Library/Audio/Plug-Ins/Components/Serum.component", id: "com.xfer.serum", in: fixture)
        try tests.plugIn("root/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3", id: "com.valhalladsp.Supermassive", in: fixture)
        try fixture.file("root/Library/Audio/Presets/Valhalla DSP, LLC/ValhallaRoom/Big Hall.vpreset", bytes: 300)
        try fixture.file("Library/Preferences/ValhallaRoom.settings", bytes: 300)
        func bundle(_ name: String) -> [String] { [name, name + "/Contents", name + "/Contents/Info.plist"] }
        let avid = ["Library", "Library/Application Support", "Library/Application Support/Avid", "Library/Application Support/Avid/Audio",
                    "Library/Application Support/Avid/Audio/Plug-Ins"]
        return FixtureRecords(receipts: [
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.au", volume: "/", location: "Library/Audio/Plug-Ins/Components/",
                           files: bundle("ValhallaRoom.component")),
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.vst", volume: "/", location: "Library/Audio/Plug-Ins/VST",
                           files: bundle("ValhallaRoom.vst")),
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.vst3", volume: "/", location: "Library/Audio/Plug-Ins/VST3",
                           files: bundle("ValhallaRoom.vst3")),
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.aax", volume: "/", location: "",
                           files: avid + bundle("Library/Application Support/Avid/Audio/Plug-Ins/ValhallaRoom.aaxplugin")),
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.presets", volume: "/", location: "Library/Audio/Presets",
                           files: ["Valhalla DSP, LLC", "Valhalla DSP, LLC/ValhallaRoom", "Valhalla DSP, LLC/ValhallaRoom/Big Hall.vpreset"]),
            PackageReceipt(id: "com.xfer.serum.AU", volume: "/", location: "Library/Audio/Plug-Ins/Components", files: bundle("Serum.component")),
        ])
    }

    @Test func aGoneAppIsFoundByItsReceipts() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let records = try UninstallTests.valhalla(fixture)
        let plan = try plan("com.valhalladsp", fixture, records: records)
        #expect(plan.identity.receipts.count == 5 && !plan.identity.receipts.contains("com.xfer.serum.AU"))
        #expect(match(plan, "root/Library/Audio/Plug-Ins/Components/ValhallaRoom.component", in: fixture) == "exact")
        #expect(match(plan, "root/Library/Audio/Plug-Ins/VST/ValhallaRoom.vst", in: fixture) == "exact")
        #expect(match(plan, "root/Library/Audio/Plug-Ins/VST3/ValhallaRoom.vst3", in: fixture) == "exact")
        #expect(match(plan, "root/Library/Application Support/Avid/Audio/Plug-Ins/ValhallaRoom.aaxplugin", in: fixture) == "exact")
        #expect(match(plan, "root/Library/Audio/Presets/Valhalla DSP, LLC", in: fixture) == "exact")
        #expect(match(plan, "root/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3", in: fixture) == "likely")
        #expect(match(plan, "Library/Preferences/ValhallaRoom.settings", in: fixture) == "review")
        // The shared parents a receipt lists are never items, nor what else is in them.
        for shared in ["root/Library/Application Support/Avid", "root/Library/Application Support/Avid/Audio/Plug-Ins",
                       "root/Library/Application Support/Avid/Audio/Plug-Ins/Other.aaxplugin",
                       "root/Library/Audio/Plug-Ins/Components/Serum.component", "root/Library", "root/Library/Audio/Presets"] {
            #expect(match(plan, shared, in: fixture) == nil, "\(shared)")
        }
        // Everything a receipt owns is taken, so each receipt is forgotten — by a person, with sudo.
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        let line = try #require(Uninstaller.byHand(taking, plan: plan))
        #expect(line.contains("sudo pkgutil --forget 'com.valhalladsp.ValhallaRoom.pkg.au'"))
        #expect(!line.contains("serum"))
        #expect(!line.contains("rm -rf"))   // all of it is this user's in a fixture
    }

    @Test func rootOwnedPathsJoinTheSudoLine() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let records = try UninstallTests.valhalla(fixture)
        // A folder this user may not write: what is in it needs root.
        _ = CommandRunner.run("/bin/chmod", ["555", fixture.path("root/Library/Audio/Plug-Ins/Components")], timeout: 10)
        let plan = try plan("com.valhalladsp", fixture, records: records)
        let component = try #require(plan.items.first { $0.path.hasSuffix("ValhallaRoom.component") })
        #expect(component.removal == .sudo)
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        let line = try #require(Uninstaller.byHand(taking, plan: plan))
        #expect(line.hasPrefix("sudo rm -rf '\(component.path)' && sudo pkgutil --forget"), "\(line)")
        let outcomes = try Uninstaller.remove(taking, plan: plan, quit: false, catalogue: try Catalogue.builtIn(),
                                              context: context(fixture, records: records))
        #expect(outcomes.first { $0.path == component.path }?.result == .skipped)
        #expect(fixture.exists("root/Library/Audio/Plug-Ins/Components/ValhallaRoom.component"))
        #expect(!fixture.exists("root/Library/Audio/Plug-Ins/VST3/ValhallaRoom.vst3"))
    }

    @Test func onlyWhatIsInsideAnAllowedPlaceMayGo() throws {
        let catalogue = try Catalogue.builtIn()
        let home = "/Users/example"
        func reason(_ path: String, _ allowing: [String] = Uninstaller.allowedInside) -> String? {
            PathSafety.reason(for: path, catalogue: catalogue, home: home, allowing: allowing)
        }
        #expect(reason("/Library/LaunchDaemons/net.example.daemon.plist") == nil)
        #expect(reason("/Library/LaunchDaemons/net.example.daemon.plist", []) != nil)
        #expect(reason("/Library/LaunchDaemons") != nil)
        #expect(reason(home + "/Library/Preferences/net.example.app.plist") == nil)
        #expect(reason(home + "/Library/Preferences") != nil)
        #expect(reason(home + "/Library/Keychains/login.keychain-db") != nil)
        #expect(reason(home + "/Library/Preferences/com.agilebits.onepassword.plist") != nil)
        #expect(reason("/System/Library/LaunchDaemons/x.plist") != nil)
    }

    // MARK: Shared, Apple, running, symlinks

    @Test func whatAnotherInstalledAppSharesIsOnlyReview() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try app("Paint", id: "dev.acmesoft.paint", in: fixture)
        try fixture.file("Library/Group Containers/group.dev.acmesoft.shared/x", bytes: 1_000)
        try fixture.file("Library/Application Support/AcmeSoft/settings.json", bytes: 1_000)
        let alone = try plan("dev.acmesoft.paint", fixture, records: FixtureRecords())
        #expect(match(alone, "Library/Group Containers/group.dev.acmesoft.shared", in: fixture) == "likely")

        try app("Draw", id: "dev.acmesoft.draw", in: fixture)
        let plan = try plan("dev.acmesoft.paint", fixture, records: FixtureRecords())
        let group = try #require(plan.items.first { $0.path == fixture.path("Library/Group Containers/group.dev.acmesoft.shared") })
        #expect(group.evidence["match"] == "review" && group.tier == .review)
        #expect(group.evidence["sharedWith"] == "Draw")
        let folder = try #require(plan.items.first { $0.path == fixture.path("Library/Application Support/AcmeSoft") })
        #expect(folder.evidence["sharedWith"] == "Draw")
        #expect(match(plan, "Applications/Draw.app", in: fixture) == nil)
        #expect(!Uninstaller.select(plan, ids: [], includeReview: false).take.contains { $0.path == group.path })
        // Named, a review item goes too — with the rest, not instead of it.
        let named = Uninstaller.select(plan, ids: [group.id], includeReview: false).take
        #expect(named.contains { $0.path == group.path } && named.contains { $0.path.hasSuffix("Paint.app") })
    }

    @Test func appleIsNeverAVendorAndSystemAppsAreRefused() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        #expect(throws: DiskCleanupError.self) { try plan("com.apple", fixture, records: FixtureRecords()) }
        try InstallerFixtures.app("Chess", id: "com.apple.Chess", version: "3", in: fixture.home.appendingPathComponent("root/System/Applications"))
        #expect(throws: DiskCleanupError.self) {
            try plan(fixture.path("root/System/Applications/Chess.app"), fixture, records: FixtureRecords())
        }
        try plugIn("root/Library/Audio/Plug-Ins/Components/AUNewPitch.component", id: "com.apple.audio.units.NewPitch", in: fixture)
        try fixture.file("Library/Group Containers/group.com.apple.notes/x", bytes: 1_000)
        try fixture.file("Library/Preferences/com.apple.garageband10.plist", bytes: 500)
        let plan = try plan("com.apple.garageband10", fixture, records: FixtureRecords())
        #expect(plan.identity.vendor == nil)
        #expect(plan.items.map(\.path) == [fixture.path("Library/Preferences/com.apple.garageband10.plist")])
    }

    @Test func aRunningAppIsNotRemovedWithoutQuit() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try app("Mosaic", id: "dev.mosaic.app", in: fixture)
        let records = FixtureRecords()
        let lookup = FixtureLookup(running: ["dev.mosaic.app"])
        let plan = try plan("dev.mosaic.app", fixture, records: records, lookup: lookup)
        #expect(plan.running == ["dev.mosaic.app"])
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        let catalogue = try Catalogue.builtIn()
        let context = context(fixture, records: records, lookup: lookup)
        #expect(throws: DiskCleanupError.appRunning(["dev.mosaic.app"])) {
            try Uninstaller.remove(taking, plan: plan, quit: false, catalogue: catalogue, context: context)
        }
        #expect(records.quits.isEmpty)
        // --quit asks; an app that will not quit still stops it.
        #expect(throws: DiskCleanupError.appRunning(["dev.mosaic.app"])) {
            try Uninstaller.remove(taking, plan: plan, quit: true, catalogue: catalogue, context: context)
        }
        #expect(records.quits == ["dev.mosaic.app"])
        #expect(fixture.exists("Applications/Mosaic.app"))
    }

    @Test func symlinksAreNotFollowedOutOfWhereTheyMatched() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        // A receipt's folder that is a symlink to somewhere else entirely.
        try fixture.file("Outside/ValhallaRoom/Big Hall.vpreset", bytes: 300)
        try fixture.folder("root/Library/Audio/Presets")
        try FileManager.default.createSymbolicLink(atPath: fixture.path("root/Library/Audio/Presets/Valhalla DSP, LLC"),
                                                   withDestinationPath: fixture.path("Outside"))
        let records = FixtureRecords(receipts: [
            PackageReceipt(id: "com.valhalladsp.ValhallaRoom.pkg.presets", volume: "/", location: "Library/Audio/Presets",
                           files: ["Valhalla DSP, LLC/ValhallaRoom", "Valhalla DSP, LLC/ValhallaRoom/Big Hall.vpreset"]),
        ])
        let plan = try plan("com.valhalladsp", fixture, records: records)
        #expect(!plan.items.contains { $0.path.contains("/Outside") || $0.path.contains("Valhalla DSP, LLC/") }, "\(plan.items.map(\.path))")
    }
}
