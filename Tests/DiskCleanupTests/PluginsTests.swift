//
//  PluginsTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The plugin inventory on a fixture (/Library under <home>/root), with
//  Mach-O headers made by hand: formats, vendors, architectures, and
//  removal offered only with proof a plugin cannot load.
//

import Foundation
import Testing
@testable import DiskCleanup

struct PluginsTests {

    static func thin(_ cpu: UInt32) -> Data {
        var data = Data()
        for value in [UInt32(0xFEED_FACF), cpu, 0, 0] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    static func fat(_ cpus: [UInt32]) -> Data {
        var data = Data()
        for value in [UInt32(0xCAFE_BABE), UInt32(cpus.count)] { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        for cpu in cpus {
            for value in [cpu, 0, 0, 0, 0] { withUnsafeBytes(of: UInt32(value).bigEndian) { data.append(contentsOf: $0) } }
        }
        return data
    }

    static let arm64: UInt32 = 0x0100_000C, x86: UInt32 = 0x0100_0007

    func bundle(_ fixture: Fixture, _ relative: String, id: String, binary: Data?) throws {
        let name = ((relative as NSString).lastPathComponent as NSString).deletingPathExtension
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0"]
        if binary != nil { info["CFBundleExecutable"] = name }
        try fixture.file(relative + "/Contents/Info.plist",
                         contents: String(decoding: try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0), as: UTF8.self))
        if let binary {
            try FileManager.default.createDirectory(atPath: fixture.path(relative + "/Contents/MacOS"), withIntermediateDirectories: true)
            try binary.write(to: URL(fileURLWithPath: fixture.path(relative + "/Contents/MacOS/" + name)))
        }
    }

    func make() throws -> Fixture {
        let fixture = try Fixture.make()
        try bundle(fixture, "root/Library/Audio/Plug-Ins/Components/Good.component", id: "com.goodaudio.good", binary: PluginsTests.fat([PluginsTests.x86, PluginsTests.arm64]))
        try bundle(fixture, "root/Library/Audio/Plug-Ins/VST/Old.vst", id: "com.oldaudio.old", binary: PluginsTests.thin(PluginsTests.x86))
        try bundle(fixture, "Library/Audio/Plug-Ins/VST3/Mine.vst3", id: "com.oldaudio.mine", binary: PluginsTests.fat([PluginsTests.x86]))
        try bundle(fixture, "root/Library/Application Support/Avid/Audio/Plug-Ins/Thing.aaxplugin", id: "com.goodaudio.thing", binary: PluginsTests.thin(PluginsTests.arm64))
        try bundle(fixture, "root/Library/Internet Plug-Ins/Flash Player.plugin", id: "com.macromedia.flash", binary: nil)
        try bundle(fixture, "root/Library/QuickLook/Preview.qlgenerator", id: "com.someone.ql", binary: PluginsTests.thin(PluginsTests.arm64))
        try bundle(fixture, "root/Library/PreferencePanes/Pane.prefPane", id: "com.someone.pane", binary: PluginsTests.thin(PluginsTests.arm64))
        try fixture.file("Library/Safari/Extensions/Old.safariextz", bytes: 2_000)
        return fixture
    }

    func entry(_ entries: [PluginEntry], _ name: String) throws -> PluginEntry {
        try #require(entries.first { $0.name == name }, "\(name)")
    }

    @Test func everyPluginIsReadByVendorAndFormat() throws {
        let fixture = try make()
        defer { fixture.remove() }
        let found = Plugins.inventory(catalogue: try Catalogue.builtIn(), context: fixture.context(), appleSilicon: true)
        #expect(Set(found.entries.map(\.format)) == ["AU", "VST", "VST3", "AAX", "Internet Plug-in", "Quick Look", "Preference Pane", "Safari Extension"])
        let good = try entry(found.entries, "Good"), flash = try entry(found.entries, "Flash Player")
        let old = try #require(found.entries.first { $0.path.hasSuffix("Old.vst") })
        #expect(good.architectures == ["x86_64", "arm64"] && good.vendor == "com.goodaudio")
        #expect(old.architectures == ["x86_64"] && flash.architectures == nil)
        #expect(found.entries.map(\.vendor) == found.entries.map(\.vendor).sorted())
    }

    @Test func onlyWhatProvablyCannotLoadMayGo() throws {
        let fixture = try make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        let bare = Plugins.inventory(catalogue: catalogue, context: fixture.context(), appleSilicon: true)
        func cannot(_ entries: [PluginEntry]) -> Set<String> { Set(entries.filter { $0.cannotLoad != nil }.map { PathText.lastComponent($0.path) }) }
        #expect(cannot(bare.entries) == ["Old.vst", "Mine.vst3", "Thing.aaxplugin", "Flash Player.plugin", "Old.safariextz"])
        #expect(bare.items.count == 5 && bare.items.allSatisfy { $0.tier == .review })
        // Rosetta loads x86_64 plugins in an x86_64 host; an Intel Mac loads them natively.
        try fixture.file("root/Library/Apple/usr/libexec/oah/libRosettaRuntime", bytes: 10)
        let rosetta = Plugins.inventory(catalogue: catalogue, context: fixture.context(), appleSilicon: true)
        #expect(rosetta.rosetta && cannot(rosetta.entries) == ["Thing.aaxplugin", "Flash Player.plugin", "Old.safariextz"])
        try FileManager.default.removeItem(atPath: fixture.path("root/Library/Apple/usr/libexec/oah/libRosettaRuntime"))
        let intel = Plugins.inventory(catalogue: catalogue, context: fixture.context(), appleSilicon: false)
        #expect(cannot(intel.entries) == ["Thing.aaxplugin", "Flash Player.plugin", "Old.safariextz"])
        // Pro Tools present: AAX loads.
        try InstallerFixtures.app("Pro Tools", id: "com.avid.ProTools", version: "2026.1", in: fixture.home.appendingPathComponent("Applications"))
        let avid = Plugins.inventory(catalogue: catalogue, context: fixture.context(), appleSilicon: false)
        #expect(cannot(avid.entries) == ["Flash Player.plugin", "Old.safariextz"])
    }

    @Test func yoursGoToTheTrashAndRootsToTheSudoLine() throws {
        let fixture = try make()
        defer { fixture.remove() }
        _ = CommandRunner.run("/bin/chmod", ["555", fixture.path("root/Library/Audio/Plug-Ins/VST")], timeout: 10)
        let context = fixture.context()
        let found = Plugins.inventory(catalogue: try Catalogue.builtIn(), context: context, appleSilicon: true)
        let mine = try #require(found.items.first { $0.path.hasSuffix("Mine.vst3") })
        let old = try #require(found.items.first { $0.path.hasSuffix("Old.vst") })
        #expect(mine.removal == .trash && old.removal == .sudo)
        #expect(Plugins.select(found.items, ids: [], all: false).take.isEmpty)
        let take = Plugins.select(found.items, ids: [mine.id, old.id], all: false).take
        #expect(HandBack.line(take, among: take) == "sudo rm -rf '\(old.path)'")
        let outcomes = Remover.remove(take, catalogue: try Catalogue.builtIn(), context: context, batch: "p1")
        #expect(Set(outcomes.map(\.result)) == [.trashed, .skipped])
        #expect(!fixture.exists("Library/Audio/Plug-Ins/VST3/Mine.vst3") && fixture.exists("root/Library/Audio/Plug-Ins/VST/Old.vst"))
        _ = try Restorer.undo("p1", journal: context.journal, context: context)
        #expect(fixture.exists("Library/Audio/Plug-Ins/VST3/Mine.vst3"))
    }

    @Test func machOHeadersSayTheirCPUs() {
        #expect(MachOText.architectures(PluginsTests.thin(PluginsTests.arm64)) == ["arm64"])
        #expect(MachOText.architectures(PluginsTests.fat([PluginsTests.x86, PluginsTests.arm64])) == ["x86_64", "arm64"])
        #expect(MachOText.architectures(Data("#!/bin/sh\n".utf8)) == nil)
        #expect(MachOText.architectures(Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 9])) == nil)
    }
}
