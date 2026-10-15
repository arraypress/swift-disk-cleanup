//
//  ScanTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import DiskCleanup

struct ScanTests {

    func scan(_ fixture: Fixture, _ categories: Set<CleanupCategory> = [], lookup: FixtureLookup = FixtureLookup(),
              includeRecent: Bool = false) throws -> ScanReport {
        Scanner.scan(catalogue: try Catalogue.builtIn(), context: fixture.context(lookup: lookup),
                     options: ScanScope(categories: categories, includeRecent: includeRecent))
    }

    func item(_ report: ScanReport, _ relative: String, in fixture: Fixture) -> Item? {
        report.items.first { $0.path == fixture.path(relative) }
    }

    @Test func buildFoldersOnlyBesideTheirMarker() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture, [.buildFolders])
        let old = try #require(item(report, "Developer/swift-old/.build", in: fixture))
        #expect(old.rule == "build-swift")
        #expect(old.tier == .safe)
        #expect(old.protected == nil)
        #expect(old.evidence["marker"] == "Package.swift")
        #expect((old.bytes ?? 0) >= 64_000)
        let recent = try #require(item(report, "Developer/swift-recent/.build", in: fixture))
        #expect(recent.protected?.contains("touched") == true)
        #expect(item(report, "Developer/web/node_modules", in: fixture)?.rule == "build-node")
        #expect(item(report, "Developer/rust/target", in: fixture)?.evidence["cachedirTag"] == "yes")
        // No marker, no item; and nothing inside an app bundle.
        #expect(item(report, "Developer/nomarker/.build", in: fixture) == nil)
        #expect(!report.items.contains { $0.path.contains("Tool.app") })
        // The recency guard lifts with the flag.
        let lifted = try scan(fixture, [.buildFolders], includeRecent: true)
        #expect(item(lifted, "Developer/swift-recent/.build", in: fixture)?.protected == nil)
    }

    @Test func gitTrackedBuildFoldersAreProtected() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        guard let git = GitCheck.executable else { return }
        let project = fixture.path("Developer/rust")
        for arguments in [["init", "-q"], ["add", "-f", "target/debug/app"],
                          ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"]] {
            _ = CommandRunner.run(git, ["-C", project] + arguments, timeout: 30)
        }
        try fixture.age("Developer/rust/target", days: 40)
        let report = try scan(fixture, [.buildFolders])
        let target = try #require(item(report, "Developer/rust/target", in: fixture))
        #expect(target.protected == "holds files git tracks")
    }

    @Test func xcodeAndCoreAI() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture, [.xcode, .mlCaches])
        #expect(item(report, "Library/Developer/Xcode/DerivedData/App-abcdef", in: fixture)?.tier == .safe)
        let old = try #require(item(report, "Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)", in: fixture))
        #expect(old.protected == nil)
        let newest = try #require(item(report, "Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 18.1 (22B83)", in: fixture))
        #expect(newest.protected?.contains("newest") == true)
        #expect(item(report, "Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive", in: fixture)?.tier == .report)
        let stale = try #require(item(report, "Library/Caches/coreai-cache/25A100", in: fixture))
        #expect(stale.tier == .safe)
        let current = try #require(item(report, "Library/Caches/coreai-cache/\(Fixture.currentBuild)/imagine", in: fixture))
        #expect(current.tier == .review)
        #expect(current.owner == "imagine")
        #expect(item(report, "Library/Caches/coreai-cache/sync/25A100", in: fixture)?.tier == .safe)
        // The fixture home has no xcrun in <home>/bin: simulators are absent, not run for real.
        #expect(!report.items.contains { $0.rule == "simulator-devices" || $0.rule == "simulator-runtimes" })
    }

    @Test func leftoversNeedEveryCheckToPass() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let lookup = FixtureLookup(installed: ["com.installed.app"], silent: ["net.silent.app"])
        let report = try scan(fixture, [.leftovers], lookup: lookup)
        let gone = try #require(item(report, "Library/Caches/com.example.gone", in: fixture))
        #expect(gone.tier == .review)
        #expect(gone.removal == .trash)
        #expect(gone.protected == nil)
        #expect(gone.evidence["bundleID"] == "com.example.gone")
        // Too young: shown, held.
        #expect(item(report, "Library/Caches/com.example.fresh", in: fixture)?.protected?.contains("touched") == true)
        // A tool's cache with no app is owned by its rule, not orphaned.
        #expect(item(report, "Library/Caches/org.swift.swiftpm", in: fixture) == nil)
        // Apple's own, an installed app, an unanswered lookup, a plain name: never leftovers.
        #expect(item(report, "Library/Caches/com.apple.something", in: fixture) == nil)
        #expect(item(report, "Library/Caches/com.installed.app", in: fixture) == nil)
        #expect(item(report, "Library/Caches/net.silent.app", in: fixture) == nil)
        #expect(report.notes.contains { $0.contains("did not answer") })
        #expect(item(report, "Library/Caches/plainname", in: fixture) == nil)
        // A container's owner comes from its metadata.
        let container = try #require(item(report, "Library/Containers/ABC-container", in: fixture))
        #expect(container.evidence["bundleID"] == "com.example.containergone")
    }

    @Test func installedAppInAnAppFolderIsNotALeftover() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try InstallerFixtures.app("Gone", id: "com.example.gone", version: "1", in: fixture.home.appendingPathComponent("Applications"))
        let report = try scan(fixture, [.leftovers])
        #expect(item(report, "Library/Caches/com.example.gone", in: fixture) == nil)
    }

    @Test func refusedFolderIsNotVisibleNeverZero() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture, [.userCaches])
        let locked = try #require(item(report, "Library/Caches/locked.cache", in: fixture))
        #expect(locked.visibility == .notVisible)
        #expect(locked.bytes == nil)
        let total = try #require(report.categories.first { $0.category == .userCaches })
        #expect(total.visibility == .partial)
        #expect(report.notVisible.contains(fixture.path("Library/Caches/locked.cache")))
    }

    @Test func overlapsAreCountedOnce() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let report = try scan(fixture)
        let paths = report.items.filter { $0.path.hasPrefix("/") }.map(\.path)
        for (index, path) in paths.enumerated() {
            for other in paths[(index + 1)...] {
                #expect(!PathText.overlaps(path, other), "\(path) and \(other)")
            }
        }
        // The sweep never claims what a specific rule names.
        #expect(item(report, "Library/Caches/org.swift.swiftpm", in: fixture)?.rule == "swiftpm-cache")
        #expect(item(report, "Library/Caches/com.example.gone", in: fixture)?.rule == "leftover-caches")
        #expect(item(report, "Library/Caches/com.apple.something", in: fixture)?.protected?.contains("com.apple") == true)
        #expect(!report.items.contains { $0.path.contains("/.ssh") })
        // A total is the sum of its items.
        for total in report.categories {
            let sum = report.items.filter { $0.category == total.category }.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            #expect(total.bytes == sum)
        }
    }
}
