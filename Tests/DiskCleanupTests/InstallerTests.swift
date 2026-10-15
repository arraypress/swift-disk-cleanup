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

    /// An `Install macOS ….app` says which macOS it installs through the data
    /// it carries, so a release whose name no table knows still reads.
    @Test func macOSInstallersReadTheirOwnVersion() throws {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-macos-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        func installer(_ name: String, softwareUpdate version: String) throws -> String {
            let app = root.appendingPathComponent("Install macOS \(name).app")
            let support = app.appendingPathComponent("Contents/SharedSupport")
            let source = root.appendingPathComponent(".staging-\(name)/com_apple_MobileAsset_MacSoftwareUpdate")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let xml: [String: Any] = ["Assets": [["OSVersion": version, "Build": "99A1"]]]
            try PropertyListSerialization.data(fromPropertyList: xml, format: .xml, options: 0)
                .write(to: source.appendingPathComponent("com_apple_MobileAsset_MacSoftwareUpdate.xml"))
            let made = CommandRunner.run("/usr/bin/hdiutil", [
                "create", "-quiet", "-srcfolder", source.deletingLastPathComponent().path, "-volname", "Shared Support",
                "-format", "UDZO", support.appendingPathComponent("SharedSupport.dmg").path,
            ], timeout: 120)
            #expect(made?.succeeded == true)
            return app.path
        }
        let future = try installer("Faraway", softwareUpdate: "99.1")
        let past = try installer("Yesteryear", softwareUpdate: "11.7")
        let classic = root.appendingPathComponent("Install macOS Elsewhere.app")
        try FileManager.default.createDirectory(at: classic.appendingPathComponent("Contents/SharedSupport"),
                                                withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["System Image Info": ["version": "10.15.7"]],
                                           format: .xml, options: 0)
            .write(to: classic.appendingPathComponent("Contents/SharedSupport/InstallInfo.plist"))

        #expect(InstallerReader.macOSInstallerVersion(future) == "99.1")
        #expect(InstallerReader.macOSInstallerVersion(past) == "11.7")
        #expect(InstallerReader.macOSInstallerVersion(classic.path) == "10.15.7")
        // With no data inside, the name still answers for a known release.
        let named = root.appendingPathComponent("Install macOS Sonoma.app")
        try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
        #expect(InstallerReader.macOSInstallerVersion(named.path) == "14")

        let context = CleanupContext.live(home: root)
        let index = AppIndex.build(folders: [])
        #expect(InstallerReader.inspect(future, context: context, index: index)?.verdict == .pendingUpdate)
        #expect(InstallerReader.inspect(past, context: context, index: index)?.verdict == .dead)
        let mounts = CommandRunner.run("/usr/bin/hdiutil", ["info"], timeout: 30)?.text ?? ""
        #expect(!mounts.contains("diskmaid-mount"))
    }
}
