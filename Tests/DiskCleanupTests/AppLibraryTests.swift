//
//  AppLibraryTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Root-owned sound libraries, read from <home>/root in a fixture: shown as
//  leftovers only when none of their apps is installed, and never removed —
//  only the sudo command is given back. And the two report-only Claude places.
//

import Foundation
import Testing
@testable import DiskCleanup

struct AppLibraryTests {

    static let libraries = [
        "root/Library/Application Support/Logic/Sampler Instruments/a.exs",
        "root/Library/Audio/Apple Loops/Apple/loop.caf",
        "root/Library/Application Support/Propellerhead Software/Reason/Factory Sound Bank.rx2",
    ]

    func scan(_ fixture: Fixture, lookup: FixtureLookup = FixtureLookup()) throws -> ScanReport {
        for library in AppLibraryTests.libraries { try fixture.file(library, bytes: 70_000) }
        return Scanner.scan(catalogue: try Catalogue.builtIn(), context: fixture.context(lookup: lookup),
                            options: ScanScope(categories: [.leftovers]))
    }

    func item(_ report: ScanReport, _ relative: String, in fixture: Fixture) -> Item? {
        report.items.first { $0.path == fixture.path(relative) }
    }

    @Test func librariesOfAppsThatAreGoneAreReviewLeftovers() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        // Some Apple app is always installed; it says nothing about Logic.
        try InstallerFixtures.app("Safari", id: "com.apple.Safari", version: "26.0", in: fixture.home.appendingPathComponent("Applications"))
        let report = try scan(fixture)
        let logic = try #require(item(report, "root/Library/Application Support/Logic", in: fixture))
        #expect(logic.rule == "logic-sound-library")
        #expect(logic.tier == .review)
        #expect(logic.removal == .sudo)
        #expect(logic.protected == nil)
        #expect(item(report, "root/Library/Audio/Apple Loops", in: fixture) != nil)
        #expect(item(report, "root/Library/Application Support/Propellerhead Software", in: fixture)?.rule == "reason-sound-library")
        // Nothing outside the fixture: the real /Library is never read.
        #expect(!report.items.contains { $0.path.hasPrefix("/Library/") })
    }

    @Test func anInstalledAppKeepsItsLibrary() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        // Reason in the app folder (its vendor keeps the banks); GarageBand known to LaunchServices.
        try InstallerFixtures.app("Reason 14", id: "se.propellerheads.reason", version: "14.0", in: fixture.home.appendingPathComponent("Applications"))
        let report = try scan(fixture, lookup: FixtureLookup(installed: ["com.apple.garageband10"]))
        #expect(item(report, "root/Library/Application Support/Propellerhead Software", in: fixture) == nil)
        #expect(item(report, "root/Library/Application Support/Logic", in: fixture) == nil)
        #expect(item(report, "root/Library/Audio/Apple Loops", in: fixture) == nil)
    }

    @Test func noAnswerKeepsItsLibrary() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture, lookup: FixtureLookup(silent: ["com.apple.logic10"]))
        #expect(item(report, "root/Library/Application Support/Logic", in: fixture) == nil)
        #expect(report.notes.contains { $0.hasPrefix("logic-sound-library: left alone") })
    }

    @Test func rootOwnedLibrariesAreHandedBackNotRemoved() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture)
        let logic = try #require(item(report, "root/Library/Application Support/Logic", in: fixture))
        let outcome = try #require(Remover.remove([logic], catalogue: try Catalogue.builtIn(), context: fixture.context()).first)
        #expect(outcome.result == .skipped)
        #expect(outcome.to == "sudo rm -rf '\(fixture.path("root/Library/Application Support/Logic"))'")
        #expect(FileManager.default.fileExists(atPath: fixture.path("root/Library/Application Support/Logic")))
        #expect(Removal.sudo.byHand("/Library/it's") == "sudo rm -rf '/Library/it'\\''s'")
    }

    @Test func claudePlacesAreReportOnly() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file("Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img", bytes: 70_000)
        try fixture.file(".claude/projects/-Users-x-Developer/session.jsonl", bytes: 5_000)
        let report = Scanner.scan(catalogue: try Catalogue.builtIn(), context: fixture.context(),
                                  options: ScanScope(categories: [.reportOnly]))
        let vm = try #require(item(report, "Library/Application Support/Claude/vm_bundles", in: fixture))
        let sessions = try #require(item(report, ".claude/projects", in: fixture))
        #expect(vm.tier == .report && sessions.tier == .report)
        #expect((vm.bytes ?? 0) >= 70_000)
    }
}

/// The sound library's installer receipts: forgotten after the files when
/// pkgutil can forget them (/var/db/receipts), only noted when macOS holds
/// them (SIP), and found by what they list — never by their names.
struct SoundLibraryReceiptTests {

    static let logic = "/Library/Application Support/Logic"
    static let loops = "/Library/Audio/Apple Loops"

    /// A content receipt the way Apple writes one: volume /, location /, every parent listed.
    static func receipt(_ id: String, _ files: [String]) -> PackageReceipt {
        var listed: [String] = []
        for file in files {
            var parts: [String] = []
            for part in PathText.components(file) {
                parts.append(part)
                let path = parts.joined(separator: "/")
                if !listed.contains(path) { listed.append(path) }
            }
        }
        return PackageReceipt(id: id, volume: "/", location: "/", files: listed)
    }

    static let three = [
        receipt("com.apple.pkg.MAContent10_AssetPack_0001", ["Library/Application Support/Logic/Sampler Instruments/a.exs"]),
        receipt("com.apple.pkg.MAContent10_AssetPack_0002", ["Library/Application Support/Logic/Sampler Instruments/b.exs",
                                                             "Library/Audio/Apple Loops/Apple/b.caf"]),
        receipt("com.apple.pkg.MAContent10_AssetPack_0003", ["Library/Audio/Apple Loops/Apple/c.caf"]),
    ]

    func scan(_ fixture: Fixture, records: FixtureRecords, lookup: FixtureLookup = FixtureLookup()) throws -> ScanReport {
        var context = fixture.context(lookup: lookup)
        context.records = records
        return Scanner.scan(catalogue: try Catalogue.builtIn(), context: context, options: ScanScope(categories: [.leftovers]))
    }

    func files(_ fixture: Fixture) throws {
        try fixture.file("root/Library/Application Support/Logic/Sampler Instruments/a.exs", bytes: 70_000)
        try fixture.file("root/Library/Audio/Apple Loops/Apple/c.caf", bytes: 70_000)
    }

    func library(_ report: ScanReport, _ fixture: Fixture) -> [Item] {
        report.items.filter { $0.rule == "logic-sound-library" }
    }

    @Test func filesAndForgettableReceiptsMakeOneLineForgettingAfterTheRemoval() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try files(fixture)
        let report = try scan(fixture, records: FixtureRecords(receipts: SoundLibraryReceiptTests.three))
        let items = library(report, fixture)
        #expect(items.count == 2)
        let line = try #require(HandBack.line(items, among: report.items))
        let root = fixture.path("root")
        #expect(line == "sudo rm -rf '\(root)/Library/Application Support/Logic' '\(root)/Library/Audio/Apple Loops'"
                + " && sudo pkgutil --forget 'com.apple.pkg.MAContent10_AssetPack_0001'"
                + " && sudo pkgutil --forget 'com.apple.pkg.MAContent10_AssetPack_0002'"
                + " && sudo pkgutil --forget 'com.apple.pkg.MAContent10_AssetPack_0003'", "\(line)")
        // Logic alone: the receipt that also owns Apple Loops stays, since Apple Loops does.
        let logic = try #require(items.first { $0.path.hasSuffix("/Logic") })
        let alone = try #require(HandBack.line([logic], among: report.items))
        #expect(alone.contains("AssetPack_0001") && !alone.contains("AssetPack_0002") && !alone.contains("AssetPack_0003"), "\(alone)")
    }

    @Test func aReceiptMacOSHoldsIsNeverForgottenOnlyNoted() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try files(fixture)
        let records = FixtureRecords(receipts: SoundLibraryReceiptTests.three, held: ["com.apple.pkg.MAContent10_AssetPack_0001"])
        let report = try scan(fixture, records: records)
        let line = try #require(HandBack.line(library(report, fixture), among: report.items))
        #expect(!line.contains("AssetPack_0001"), "\(line)")
        #expect(line.contains("--forget 'com.apple.pkg.MAContent10_AssetPack_0003'"))
        #expect(report.notes.contains("1 Apple content receipt remains; macOS protects them; Logic Pro, GarageBand or MainStage can download the sounds again from its Sound Library menu."), "\(report.notes)")
    }

    @Test func receiptsWhoseFilesAreGoneAreTheirOwnItemUnlessMacOSHoldsThem() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let gone = FixtureRecords(receipts: SoundLibraryReceiptTests.three, held: ["com.apple.pkg.MAContent10_AssetPack_0003"])
        let report = try scan(fixture, records: gone)
        let items = library(report, fixture)
        let receipts = try #require(items.first)
        #expect(items.count == 1)
        #expect(receipts.path == "pkgutil: receipts for content no longer on disk (logic-sound-library)")
        #expect(receipts.removal == .sudo && receipts.tier == .review && receipts.bytes == 0)
        #expect(HandBack.line([receipts], among: report.items)
                == "sudo pkgutil --forget 'com.apple.pkg.MAContent10_AssetPack_0001' && sudo pkgutil --forget 'com.apple.pkg.MAContent10_AssetPack_0002'")
        #expect(report.notes.contains { $0.hasPrefix("1 Apple content receipt remains") })

        // Every one held, as on this Mac: no item at all, only the note.
        let held = FixtureRecords(receipts: SoundLibraryReceiptTests.three, held: Set(SoundLibraryReceiptTests.three.map(\.id)))
        let quiet = try scan(fixture, records: held)
        #expect(library(quiet, fixture).isEmpty)
        #expect(quiet.notes.contains { $0.hasPrefix("3 Apple content receipts remain; macOS protects them") })
    }

    @Test func aReceiptThatAlsoOwnsFilesElsewhereIsLeftAlone() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try files(fixture)
        let wider = SoundLibraryReceiptTests.receipt("com.apple.pkg.LogicProX", ["Library/Application Support/Logic/Sampler Instruments/a.exs",
                                                                                 "Applications/Logic Pro X.app/Contents/Info.plist"])
        let report = try scan(fixture, records: FixtureRecords(receipts: [wider]))
        let line = try #require(HandBack.line(library(report, fixture), among: report.items))
        #expect(!line.contains("--forget"), "\(line)")
        #expect(report.notes.contains("logic-sound-library: 1 receipt(s) also own files outside it, so they are left alone"))
    }

    @Test func installedReasonKeepsItsBanksAndTheirReceipts() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file("root/Library/Application Support/Propellerhead Software/Reason/Factory Sound Bank.rx2", bytes: 70_000)
        let banks = SoundLibraryReceiptTests.receipt("se.propellerheads.Reason-14-FactorySoundBank",
                                                     ["Library/Application Support/Propellerhead Software/Reason/Factory Sound Bank.rx2"])
        let records = FixtureRecords(receipts: [banks])
        let gone = try scan(fixture, records: records)
        let item = try #require(gone.items.first { $0.rule == "reason-sound-library" })
        #expect(item.receipts == ["se.propellerheads.Reason-14-FactorySoundBank"])
        try InstallerFixtures.app("Reason 14", id: "se.propellerheads.reason", version: "14.0", in: fixture.home.appendingPathComponent("Applications"))
        let installed = try scan(fixture, records: records)
        #expect(!installed.items.contains { $0.rule == "reason-sound-library" })
    }

    // MARK: uninstall brings the library along

    func uninstall(_ fixture: Fixture, records: FixtureRecords) throws -> UninstallPlan {
        var context = fixture.context()
        context.records = records
        return try Uninstaller.plan("com.apple.garageband10", catalogue: try Catalogue.builtIn(), context: context)
    }

    @Test func uninstallingGarageBandAloneTakesTheLibrary() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try files(fixture)
        let plan = try uninstall(fixture, records: FixtureRecords(receipts: SoundLibraryReceiptTests.three))
        let library = plan.items.filter { $0.path.hasPrefix(fixture.path("root/Library")) }
        #expect(library.count == 2 && library.allSatisfy { $0.evidence["match"] == "likely" }, "\(plan.items.map { ($0.path, $0.evidence["match"]) })")
        let taking = Uninstaller.select(plan, ids: [], includeReview: false).take
        #expect(Uninstaller.byHand(taking, plan: plan)?.contains("--forget 'com.apple.pkg.MAContent10_AssetPack_0002'") == true)
    }

    @Test func uninstallingGarageBandLeavesWhatLogicStillUsesToReview() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try files(fixture)
        try InstallerFixtures.app("Logic Pro", id: "com.apple.logic10", version: "11.0", in: fixture.home.appendingPathComponent("Applications"))
        let plan = try uninstall(fixture, records: FixtureRecords(receipts: SoundLibraryReceiptTests.three))
        let library = plan.items.filter { $0.path.hasPrefix(fixture.path("root/Library")) }
        #expect(library.count == 2)
        #expect(library.allSatisfy { $0.evidence["match"] == "review" && $0.evidence["sharedWith"] == "Logic Pro" })
        #expect(library.allSatisfy { ($0.evidence["why"] ?? "").contains("also used by Logic Pro") })
        #expect(Uninstaller.select(plan, ids: [], includeReview: false).take.allSatisfy { !$0.path.hasPrefix(fixture.path("root")) })
    }
}
