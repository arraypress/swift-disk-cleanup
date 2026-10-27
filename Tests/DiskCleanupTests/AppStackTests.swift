//
//  AppStackTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  What apps are built with: the rules with no file, then a folder of
//  fixture apps — an Electron one with a vendor-suffixed version, Flutter,
//  an iPhone app in a Wrapper, a Java one and a plain native one — scanned
//  the way `diskmaid apps` scans /Applications. The apps are invented.
//

import Foundation
import Testing
@testable import DiskCleanup

struct AppStackTests {

    // MARK: - Rules

    @Test func theRuntimeDecidesNotTheHelpers() {
        let electron = StackRules.Contents(frameworks: ["Squirrel.framework", "Mantle.framework", "Electron Framework.framework",
                                                        "ReactiveObjC.framework"])
        #expect(StackRules.stack(of: electron).stack == .electron)
        #expect(StackRules.stack(of: electron).evidence == "Contents/Frameworks/Electron Framework.framework")
        #expect(StackRules.stack(of: .init(frameworks: ["Sparkle.framework"])).stack == .native, "an updater is not a runtime")
        #expect(StackRules.stack(of: .init(frameworks: ["Chromium Embedded Framework.framework"])).stack == .cef)
        #expect(StackRules.stack(of: .init(frameworks: ["FlutterMacOS.framework", "App.framework"])).stack == .flutter)
        #expect(StackRules.stack(of: .init(frameworks: ["libQt6Core.6.dylib"])).stack == .qt)
        #expect(StackRules.stack(of: .init(frameworks: ["hermes.framework"])).stack == .reactNative)
        #expect(StackRules.stack(of: .init(frameworks: ["UnityPlayer.dylib"])).stack == .unity)
    }

    @Test func bundleShapesDecideWhenNoRuntimeDoes() {
        #expect(StackRules.stack(of: .init(wrapper: true)).stack == .iosApp)
        #expect(StackRules.stack(of: .init(frameworks: ["Electron Framework.framework"], wrapper: true)).stack == .iosApp,
                "a wrapped iPhone app is what it is")
        #expect(StackRules.stack(of: .init(javaRuntime: "Contents/runtime")).stack == .java)
        #expect(StackRules.stack(of: .init(monoBundle: true)).stack == .dotnet)
        #expect(StackRules.stack(of: .init(catalyst: true)).stack == .catalyst)
        #expect(StackRules.stack(of: .init()).stack == .native)
        #expect(StackRules.stack(of: .init()).evidence == nil)
    }

    @Test func electronVersionsDropVendorSuffixes() {
        #expect(StackRules.electronVersion("42.11.1") == "42.11.1")
        #expect(StackRules.electronVersion("37.10.3-dropbox-75-20261021-204309.0") == "37.10.3")
        #expect(StackRules.electronVersion("beta") == nil)
        #expect(StackRules.electronVersion("42") == nil, "a lone number is not a version")
        #expect(StackRules.major("42.11.1") == 42)
    }

    @Test func namesLoseInvisibleMarks() {
        #expect(StackRules.cleanName("\u{200E}Chatter ") == "Chatter")
        #expect(StackRules.cleanName("Café Notes") == "Café Notes")
    }

    @Test func aLinkedAppIsMeasuredWhereItPoints() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/diskmaid-links-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let elsewhere = folder.appendingPathComponent("System")
        try Self.app("Browser", in: elsewhere)
        let apps = folder.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: apps.appendingPathComponent("Browser.app"),
                                                   withDestinationURL: elsewhere.appendingPathComponent("Browser.app"))
        let reports = AppStacks.scan([apps, elsewhere])
        #expect(reports.count == 1, "one app, reached twice")
        #expect((reports.first?.bytes ?? 0) >= 1000, "the app's size, not the link's")
        #expect(reports.first?.path.hasSuffix("Applications/Browser.app") == true, "shown where it was found")
    }

    @Test func slicesMakeAnArchitecture() {
        #expect(StackRules.architecture(["arm64"]) == .appleSilicon)
        #expect(StackRules.architecture(["x86_64", "arm64"]) == .universal)
        #expect(StackRules.architecture(["x86_64"]) == .intel)
        #expect(StackRules.architecture(["arm64e"]) == .appleSilicon)
        #expect(StackRules.architecture(["ppc"]) == .unknown)
        #expect(StackRules.architecture(nil) == .unknown)
    }

    /// A thin 64-bit Mach-O header for a CPU: magic, then the CPU type, little-endian.
    static func machO(_ cpu: UInt32) -> Data {
        var data = Data()
        for value in [UInt32(0xFEED_FACF), cpu] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return data + Data(repeating: 0, count: 24)
    }

    @Test func anAppsMainBinarySaysWhichProcessorsItRunsOn() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/diskmaid-arch-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, cpu) in [("Silicon", UInt32(0x0100_000C)), ("Legacy", UInt32(0x0100_0007))] {
            try Self.app(name, in: folder)
            let contents = folder.appendingPathComponent("\(name).app/Contents")
            var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: contents.appendingPathComponent("Info.plist")),
                                                                   format: nil) as! [String: Any]
            plist["CFBundleExecutable"] = name
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try Self.machO(cpu).write(to: contents.appendingPathComponent("MacOS/\(name)"))
        }
        try Self.app("Phone Game", in: folder, extra: ["Wrapper"])
        let reports = AppStacks.scan([folder], mdls: "/nonexistent/mdls")
        #expect(reports.first { $0.name == "Silicon" }?.architecture == .appleSilicon)
        #expect(reports.first { $0.name == "Legacy" }?.architecture == .intel)
        #expect(reports.first { $0.name == "Phone Game" }?.architecture == .appleSilicon, "an iPhone app runs natively")
        #expect(reports.allSatisfy { $0.lastOpened == nil }, "no Spotlight, no dates — never a guess")
    }

    @Test func catalystIsTheMacDeviceFamily() {
        #expect(StackRules.isCatalyst(deviceFamily: [2, 6]))
        #expect(!StackRules.isCatalyst(deviceFamily: [1, 2]))
        #expect(!StackRules.isCatalyst(deviceFamily: nil))
    }

    // MARK: - A folder of apps

    static func app(_ name: String, in folder: URL, frameworks: [String: Int] = [:], extra: [String] = [],
                    electron: String? = nil) throws {
        let contents = folder.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.\(name.lowercased())", "CFBundleShortVersionString": "1.2",
                                    "CFBundleName": name, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 1000).write(to: contents.appendingPathComponent("MacOS/\(name)"))
        for (framework, bytes) in frameworks {
            let url = contents.appendingPathComponent("Frameworks/\(framework)")
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Versions/A/Resources"), withIntermediateDirectories: true)
            try Data(repeating: 2, count: bytes).write(to: url.appendingPathComponent("Versions/A/binary"))
            if let electron, framework == "Electron Framework.framework" {
                try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": electron], format: .xml, options: 0)
                    .write(to: url.appendingPathComponent("Versions/A/Resources/Info.plist"))
            }
        }
        for path in extra {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("\(name).app/\(path)"), withIntermediateDirectories: true)
        }
    }

    @Test func aFolderOfAppsIsReadBiggestFirst() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/diskmaid-stacks-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.app("Chatter", in: folder, frameworks: ["Electron Framework.framework": 400_000, "Squirrel.framework": 10_000],
                     electron: "37.10.3-vendor-1")
        try Self.app("Painter", in: folder, frameworks: ["FlutterMacOS.framework": 200_000])
        try Self.app("Notes Plus", in: folder.appendingPathComponent("Utilities"))
        try Self.app("Phone Game", in: folder, extra: ["Wrapper"])
        try Self.app("Modeler", in: folder, extra: ["Contents/runtime"])

        let reports = AppStacks.scan([folder, folder])
        #expect(reports.count == 5, "each app once, a subfolder included, a folder named twice read once")
        #expect(reports.prefix(2).map(\.name) == ["Chatter", "Painter"], "biggest first, not by name")
        let chatter = try #require(reports.first { $0.name == "Chatter" })
        #expect(chatter.stack == .electron)
        #expect(chatter.electronVersion == "37.10.3")
        #expect((chatter.runtimeBytes ?? 0) >= 400_000 && (chatter.runtimeBytes ?? 0) < chatter.bytes)
        #expect(reports.first { $0.name == "Painter" }?.stack == .flutter)
        #expect(reports.first { $0.name == "Phone Game" }?.stack == .iosApp)
        #expect(reports.first { $0.name == "Modeler" }?.stack == .java)
        let native = try #require(reports.first { $0.name == "Notes Plus" })
        #expect(native.stack == .native && native.evidence == nil && native.runtimeBytes == nil)
        #expect(native.bundleID == "com.example.notes plus")
        #expect(native.version == "1.2")
    }
}
