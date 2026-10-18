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
