//
//  InstallerTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Real installers, built with hdiutil, pkgbuild and zip, judged against
//  real app bundles. One test so they are built once.
//

import Foundation
import Testing
@testable import DiskCleanup

struct InstallerTests {

    @Test func everyInstallerCase() throws {
        let built = try InstallerFixtures.build()
        defer { try? FileManager.default.removeItem(at: built.root) }
        var context = CleanupContext.live(home: built.root)
        context.lookup = FixtureLookup()
        context.applicationFolders = [built.applications]
        let index = AppIndex.build(folders: context.applicationFolders)
        func verdict(_ name: String) -> InstallerInfo? {
            InstallerReader.inspect(built.downloads.appendingPathComponent(name).path, context: context, index: index)
        }
        let dead = try #require(verdict("dead.dmg"))
        #expect(dead.verdict == .dead)
        #expect(dead.bundleID == "dev.diskmaid.fixture.same")
        #expect(dead.installedVersion == "1.0")
        #expect(try #require(verdict("pending.dmg")).verdict == .pendingUpdate)
        #expect(try #require(verdict("unknown.dmg")).verdict == .unknown)
        #expect(try #require(verdict("encrypted.dmg")).verdict == .encrypted)
        let pkg = try #require(verdict("packaged.pkg"))
        #expect(pkg.verdict == .dead)
        #expect(pkg.version == "1.5")
        #expect(pkg.installedVersion == "2.0")
        #expect(try #require(verdict("zipped.zip")).verdict == .dead)
        // A zip with no app in it is not an installer at all.
        #expect(verdict("photos.zip") == nil)
        // Every image was detached again.
        let mounts = CommandRunner.run("/usr/bin/hdiutil", ["info"], timeout: 30)?.text ?? ""
        #expect(!mounts.contains("diskmaid-mount"))

        // Through the scanner: only the dead ones are cleanable.
        let report = Scanner.scan(catalogue: try Catalogue.builtIn(), context: context,
                                  options: ScanScope(categories: [.installers], installerFolders: [built.downloads]))
        let cleanable = report.items.filter { $0.protected == nil }.map { PathText.lastComponent($0.path) }.sorted()
        #expect(cleanable == ["dead.dmg", "packaged.pkg", "zipped.zip"])
        #expect(report.items.count == 6)
    }
}
