//
//  SupportTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import DiskCleanup

struct SupportTests {

    @Test func versionsCompareTheWayPeopleWriteThem() {
        #expect(VersionOrder.compare("1.10", "1.9") == .orderedDescending)
        #expect(VersionOrder.compare("2.0", "2") == .orderedSame)
        #expect(VersionOrder.compare("2.0.1", "2.0") == .orderedDescending)
        #expect(VersionOrder.compare("3.1b2", "3.1.1") == .orderedAscending)
        #expect(VersionOrder.compare("15.0 (24A335)", "15.0 (24A336)") == .orderedAscending)
        #expect(VersionOrder.compare("beta", "1.0") == nil)
    }

    @Test func globsMatchOneComponentAndSkipDotFiles() {
        #expect(Glob.matches("*", "com.example"))
        #expect(!Glob.matches("*", ".DS_Store"))
        #expect(Glob.matches("*.savedState", "com.x.savedState"))
        #expect(Glob.matchesPath("/u/Library/Caches/*", "/u/Library/Caches/x"))
        #expect(!Glob.matchesPath("/u/Library/Caches/*", "/u/Library/Caches/x/y"))
        let split = Glob.split("/u/Library/Developer/Xcode/*DeviceSupport/*")
        #expect(split.base == "/u/Library/Developer/Xcode")
        #expect(split.rest == ["*DeviceSupport", "*"])
    }

    @Test func pathSafetyRefusesTheDangerousPlaces() throws {
        let catalogue = try Catalogue.builtIn()
        let home = "/Users/example"
        for path in ["/System/Library", "/private/var/folders/ab/x", "/var/folders/x", "/Users/example",
                     "/Users", "/", "/Users/example/.ssh/id_rsa", "/Users/example/Library/Keychains/login.keychain-db",
                     "/Users/example/Library/LaunchAgents/x.plist", "/Users/example/Library/Group Containers/x",
                     "/Users/example/Library/Caches/com.1password.x", "/Users/example/Library/Caches/../Keychains",
                     "/Library/LaunchDaemons/x.plist", "relative/path"] {
            #expect(PathSafety.reason(for: path, catalogue: catalogue, home: home) != nil, "\(path)")
        }
        for path in ["/Users/example/Library/Caches/com.example", "/Users/example/Developer/x/.build",
                     "/private/tmp/diskmaid-tests/x"] {
            #expect(PathSafety.reason(for: path, catalogue: catalogue, home: home) == nil, "\(path)")
        }
    }

    @Test func deviceSupportKeepsTheNewestVersion() {
        let names = ["17.0 (21A329)", "iPhone17,1 18.1 (22B83)", "iPhone16,2 18.1 (22B83)", "16.4", "Unknown"]
        let kept = DeviceSupportNames.kept(names, keep: 1)
        #expect(kept == ["iPhone17,1 18.1 (22B83)", "iPhone16,2 18.1 (22B83)", "Unknown"])
        #expect(DeviceSupportNames.version("iPhone17,1 18.1 (22B83)")?.version == "18.1")
        #expect(DeviceSupportNames.version("18.1 (22B83)")?.build == "22B83")
    }

    @Test func osBuildsAreRecognised() {
        #expect(OSBuild.isBuild("26A428"))
        #expect(OSBuild.isBuild("25A5279m"))
        #expect(!OSBuild.isBuild("sync"))
        #expect(!OSBuild.isBuild("27.0"))
        let parsed = OSBuild.parse("Version 27.0 (Build 26A428)")
        #expect(parsed.version == "27.0")
        #expect(parsed.build == "26A428")
    }

    @Test func brewDryRunTotalIsRead() {
        let text = """
        Would remove: /opt/homebrew/x (1,707 files, 34.6MB)
        ==> This operation would free approximately 237.5MB of disk space.
        """
        #expect(BrewOutput.wouldFree(text) == Int64(237.5 * 1024 * 1024))
        #expect(BrewOutput.wouldFree("") == 0)
        #expect(BrewOutput.wouldFree("Would remove: x") == nil)
    }

    @Test func simctlJSONIsRead() throws {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"11111111-2222-3333-4444-555555555555","name":"iPhone 15","state":"Shutdown","isAvailable":false,"dataPath":"/u/Library/Developer/CoreSimulator/Devices/11111111-2222-3333-4444-555555555555/data"},{"udid":"rm -rf /","name":"evil","isAvailable":false}]}}"#
        let parsed = try #require(SimctlJSON.devices(Data(devices.utf8)))
        #expect(parsed.count == 1)
        #expect(parsed[0].isAvailable == false)
        #expect(parsed[0].folder == "/u/Library/Developer/CoreSimulator/Devices/11111111-2222-3333-4444-555555555555")
        let runtimes = #"{"A":{"identifier":"3330A13E-974B-4777-B4A5-F6D19DA0706B","runtimeIdentifier":"r.iOS-27-0","build":"24A5390f","sizeBytes":8047485793,"deletable":true},"B":{"identifier":"EA286DDE-86EB-4BAB-AF03-061B21B49E80","runtimeIdentifier":"r.iOS-27-0","build":"24A434","sizeBytes":8067000161,"deletable":true},"C":{"identifier":"EA286DDE-86EB-4BAB-AF03-061B21B49E81","runtimeIdentifier":"r.iOS-26-0","build":"23A1","deletable":true}}"#
        let images = try #require(SimctlJSON.runtimes(Data(runtimes.utf8)))
        #expect(images.count == 3)
        #expect(SimctlJSON.shared(images) == ["3330A13E-974B-4777-B4A5-F6D19DA0706B", "EA286DDE-86EB-4BAB-AF03-061B21B49E80"])
    }

    @Test func snapshotsKeepTheSystemsOwn() {
        let names = TmutilText.snapshots("Snapshots for volume group containing disk /:\ncom.apple.os.update-ABC\ncom.apple.TimeMachine.2026-10-01-120000.local\n")
        #expect(names.count == 2)
        #expect(TmutilText.isSystemOwned(names[0]))
        #expect(!TmutilText.isSystemOwned(names[1]))
    }

    @Test func commandTemplatesNeverRunWithAHole() {
        #expect(CommandTemplate.fill(["xcrun", "simctl", "delete", "{udid}"], from: ["udid": "X"]) == ["xcrun", "simctl", "delete", "X"])
        #expect(CommandTemplate.fill(["xcrun", "simctl", "delete", "{udid}"], from: [:]) == nil)
        #expect(CommandTemplate.fill(["brew", "cleanup"], from: [:]) == ["brew", "cleanup"])
    }

    @Test func bundleIDsAndVendors() {
        #expect(BundleIDs.looksLikeBundleID("com.example.app"))
        #expect(!BundleIDs.looksLikeBundleID("plainname"))
        #expect(!BundleIDs.looksLikeBundleID("com.example"))
        #expect(!BundleIDs.looksLikeBundleID("com..x"))
        #expect(BundleIDs.isApple("com.apple.Safari"))
        #expect(BundleIDs.isRelated("com.google.Keystone", to: ["com.google.chrome"], vendors: ["com.google"]))
        #expect(!BundleIDs.isRelated("com.example.gone", to: ["com.google.chrome"], vendors: ["com.google"]))
        #expect(BundleIDs.groupBase("ABCDE12345.com.x.shared") == "com.x.shared")
        #expect(BundleIDs.groupBase("group.net.whatsapp.WhatsApp.shared") == "net.whatsapp.WhatsApp.shared")
    }

    @Test func modelStoreNames() {
        #expect(ModelStoreNames.huggingFace("models--black-forest-labs--FLUX.2")?.repo == "black-forest-labs/FLUX.2")
        #expect(ModelStoreNames.huggingFace("version.txt") == nil)
        #expect(ModelStoreNames.ollamaModel("/o/manifests/registry.ollama.ai/library/llama3/8b", manifests: "/o/manifests") == "llama3:8b")
        #expect(ModelStoreNames.ollamaBytes(Data(#"{"config":{"size":10},"layers":[{"size":100},{"size":5}]}"#.utf8)) == 115)
        #expect(ModelStoreNames.xcodeVersion("Xcode_16.2.xip") == "16.2")
        #expect(MacOSNames.version(ofInstaller: "Install macOS Big Sur") == "11")
        #expect(MacOSNames.version(ofInstaller: "Install macOS Sonoma") == "14")
        #expect(MacOSNames.version(ofInstaller: "Install macOS Something New") == nil)
    }

    @Test func packageInfoIsRead() {
        let info = Data("""
        <pkg-info identifier="dev.x.pkg" version="1.0"><payload/>
        <bundle path="./Probe.app" id="dev.x.probe" CFBundleShortVersionString="1.2" CFBundleVersion="12"/>
        <bundle path="./Probe.app/Contents/Frameworks/K.framework" id="dev.x.kit" CFBundleShortVersionString="9"/>
        <bundle-version><bundle id="dev.x.probe"/></bundle-version></pkg-info>
        """.utf8)
        let distribution = Data("""
        <installer-gui-script><title>Probe Suite</title><pkg-ref id="dev.x.pkg" version="1.0">#x.pkg</pkg-ref><pkg-ref id="dev.x.pkg"/></installer-gui-script>
        """.utf8)
        let contents = PackageXML.contents(distribution: distribution, packageInfos: [info])
        #expect(contents.title == "Probe Suite")
        #expect(contents.packages == [PackageRef(id: "dev.x.pkg", version: "1.0")])
        #expect(contents.bundles == [BundleInfo(bundleID: "dev.x.probe", version: "1.2", build: "12", name: "Probe")])
    }

    @Test func hdiutilOutputIsRead() {
        #expect(HdiutilOutput.isEncrypted("encrypted: YES") == true)
        #expect(HdiutilOutput.isEncrypted("blocksize: 512\nencrypted: NO") == false)
        #expect(HdiutilOutput.isEncrypted("garbage") == nil)
        let info = try? PropertyListSerialization.data(fromPropertyList: ["Properties": ["Software License Agreement": true]], format: .xml, options: 0)
        #expect(HdiutilOutput.hasLicenceAgreement(info ?? Data()) == true)
        #expect(HdiutilOutput.hasLicenceAgreement(Data()) == nil)
    }

    @Test func itemIDsAreStable() {
        let a = ItemID.make(rule: "xcode-derived-data", path: "/u/x")
        #expect(a == ItemID.make(rule: "xcode-derived-data", path: "/u/x"))
        #expect(a != ItemID.make(rule: "xcode-derived-data", path: "/u/y"))
        #expect(ItemID.isItemID(a))
        #expect(ItemID.rule(of: a) == "xcode-derived-data")
        #expect(!ItemID.isItemID("xcode"))
    }

    @Test func installerJudgement() {
        let base = InstallerInfo(path: "/d/x.dmg", kind: .dmg, bundleID: "a.b.c", version: "2.0", verdict: .unknown, reason: "")
        func app(_ version: String, build: String? = nil) -> AppAnswer {
            .installed([InstalledApp(bundleID: "a.b.c", path: "/A.app", version: version, build: build, name: nil)])
        }
        #expect(InstallerJudge.judge(base, answer: app("2.0")).verdict == .dead)
        #expect(InstallerJudge.judge(base, answer: app("2.1")).verdict == .dead)
        #expect(InstallerJudge.judge(base, answer: app("1.9")).verdict == .pendingUpdate)
        #expect(InstallerJudge.judge(base, answer: .notInstalled).verdict == .unknown)
        #expect(InstallerJudge.judge(base, answer: .noAnswer("timed out")).verdict == .unknown)
        var built = base
        built.build = "200"
        #expect(InstallerJudge.judge(built, answer: app("2.0", build: "199")).verdict == .pendingUpdate)
        let receipts = InstallerJudge.judgeReceipts(base, packages: [PackageRef(id: "p", version: "1.0")], installed: ["p": "1.0"])
        #expect(receipts.verdict == .dead)
        let missing = InstallerJudge.judgeReceipts(base, packages: [PackageRef(id: "p", version: "1.0")], installed: ["p": nil])
        #expect(missing.verdict == .unknown)
        var mac = InstallerInfo(path: "/A/Install macOS Sonoma.app", kind: .macOSInstaller, version: "14", verdict: .unknown, reason: "")
        #expect(InstallerJudge.judgeMacOS(mac, osVersion: "27.0").verdict == .dead)
        mac.version = nil
        #expect(InstallerJudge.judgeMacOS(mac, osVersion: "27.0").verdict == .unknown)
    }

    @Test func claimsKeepTheEarlierRule() {
        func item(_ id: String, _ path: String) -> Item {
            Item(id: id, rule: id, category: .userCaches, path: path, bytes: 1, tier: .safe, removal: .delete,
                 regenerable: true, owner: nil, newest: nil, visibility: .visible, protected: nil, evidence: [:], note: nil, identity: nil)
        }
        let resolved = Claims.resolve([
            item("swiftpm", "/u/Library/Caches/org.swift.swiftpm"),
            item("coreai", "/u/Library/Caches/coreai-cache/26A428/imagine"),
            item("sweep-a", "/u/Library/Caches/org.swift.swiftpm"),
            item("sweep-b", "/u/Library/Caches/coreai-cache"),
            item("sweep-c", "/u/Library/Caches/com.other"),
            item("snapshot", "snapshot:com.apple.TimeMachine.x"),
        ])
        #expect(resolved.kept.map(\.id) == ["swiftpm", "coreai", "sweep-c", "snapshot"])
        #expect(resolved.dropped["sweep-b"] == "coreai")
    }

    @Test func selectionTakesOnlyWhatMayGo() throws {
        let now = Date()
        func item(_ id: String, tier: Tier, protected: String? = nil, days: Double = 30, category: CleanupCategory = .xcode) -> Item {
            Item(id: id, rule: "r", category: category, path: "/u/\(id)", bytes: 1, tier: tier, removal: .delete,
                 regenerable: true, owner: nil, newest: now.addingTimeInterval(-days * 86_400), visibility: .visible,
                 protected: protected, evidence: [:], note: nil, identity: nil)
        }
        let items = [item("r-0000000a", tier: .safe), item("r-0000000b", tier: .review), item("r-0000000c", tier: .report),
                     item("r-0000000d", tier: .safe, protected: "recent"), item("r-0000000e", tier: .safe, days: 2),
                     item("r-0000000f", tier: .safe, category: .userCaches)]
        let byCategory = Selection.pick(items, categories: [.xcode], ids: [], includeReview: false, olderThanDays: nil, now: now)
        #expect(byCategory.take.map(\.id) == ["r-0000000a", "r-0000000e"])
        let older = Selection.pick(items, categories: [.xcode], ids: [], includeReview: false, olderThanDays: 7, now: now)
        #expect(older.take.map(\.id) == ["r-0000000a"])
        let withReview = Selection.pick(items, categories: [.xcode], ids: [], includeReview: true, olderThanDays: nil, now: now)
        #expect(withReview.take.count == 3)
        let named = Selection.pick(items, categories: [], ids: ["r-0000000b", "r-0000000c", "r-0000000d"], includeReview: false, olderThanDays: nil, now: now)
        #expect(named.take.map(\.id) == ["r-0000000b"])
        #expect(named.held.count == 2)
        var partial = item("r-00000010", tier: .safe)
        partial.visibility = .partial
        var idOnly = item("r-00000011", tier: .review)
        idOnly.byIDOnly = true
        let guarded = Selection.pick([partial, idOnly], categories: [.xcode], ids: [], includeReview: true, olderThanDays: nil, now: now)
        #expect(guarded.take.isEmpty)
        #expect(Selection.pick([idOnly], categories: [], ids: ["r-00000011"], includeReview: false, olderThanDays: nil, now: now).take.count == 1)
        let parsed = try Selection.parse(["xcode", "r-0000000b"])
        #expect(parsed.categories == [.xcode])
        #expect(parsed.ids == ["r-0000000b"])
        #expect(throws: DiskCleanupError.self) { try Selection.parse(["nonsense"]) }
    }

    @Test func sizesAreAllocatedAndHardLinksCountOnce() throws {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-size-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: root.appendingPathComponent("a"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("a"), to: root.appendingPathComponent("b"))
        try Data(repeating: 1, count: 1).write(to: root.appendingPathComponent("tiny"))
        let measured = Sizer.measure(root.path)
        #expect(measured.files == 2)
        // One 100 KB file (allocated in whole blocks) and one block for the tiny file.
        #expect(measured.bytes >= 100_000 && measured.bytes < 140_000, "\(measured.bytes)")
        #expect(measured.visibility == .visible)
        #expect(Sizer.measure(root.path + "/nothing").visibility == .absent)
    }

    @Test func refusedFoldersAreNotVisibleNotEmpty() throws {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-lock-\(UUID().uuidString.prefix(8))")
        defer {
            _ = CommandRunner.run("/bin/chmod", ["-R", "u+rwx", root.path], timeout: 10)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("open/locked"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5000).write(to: root.appendingPathComponent("open/locked/x"))
        _ = CommandRunner.run("/bin/chmod", ["000", root.appendingPathComponent("open/locked").path], timeout: 10)
        #expect(Sizer.measure(root.appendingPathComponent("open").path).visibility == .partial)
        #expect(Sizer.measure(root.appendingPathComponent("open/locked").path).visibility == .notVisible)
        #expect(PathProbe.visibility(root.appendingPathComponent("open/locked").path) == .notVisible)
    }
}
