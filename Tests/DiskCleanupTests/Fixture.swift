//
//  Fixture.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  A fake home folder with one of everything: build folders beside their
//  markers (and one without), Xcode leftovers, Core AI builds, orphaned and
//  owned caches, a container, real installers made with hdiutil, pkgbuild
//  and zip, and a stand-in `uv` in <home>/bin. Every test that cleans works
//  on its own copy under /private/tmp — never the user's home, and never
//  /var/folders, which the cleaner itself refuses to touch.
//

import Foundation
@testable import DiskCleanup

/// LaunchServices and Spotlight, answered from a list.
struct FixtureLookup: ApplicationLookup {
    var installed: Set<String> = []
    var silent: Set<String> = []
    func launchServices(_ bundleID: String) -> AppAnswer {
        if silent.contains(bundleID) { return .noAnswer("timed out") }
        return installed.contains(bundleID) ? .installed([InstalledApp(bundleID: bundleID, path: "/x.app", version: "1", build: nil, name: nil)]) : .notInstalled
    }
    func spotlight(_ bundleID: String) -> AppAnswer { launchServices(bundleID) }
    func runningBundleIDs() -> Set<String> { [] }
}

struct Fixture {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    static let currentBuild = "26A428"

    static func make() throws -> Fixture {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-tests-\(UUID().uuidString.prefix(8))")
        let fixture = Fixture(root: root)
        try fixture.build()
        return fixture
    }

    func remove() {
        // A locked folder would stop removeItem; unlock everything first.
        _ = CommandRunner.run("/bin/chmod", ["-R", "u+rwx", root.path], timeout: 30)
        try? FileManager.default.removeItem(at: root)
    }

    func context(lookup: FixtureLookup = FixtureLookup()) -> CleanupContext {
        var context = CleanupContext.live(home: home)
        context.lookup = lookup
        context.osBuild = Fixture.currentBuild
        context.osVersion = "27.0"
        context.projectRoots = [home.appendingPathComponent("Developer")]
        return context
    }

    func path(_ relative: String) -> String { home.path + "/" + relative }

    /// A file of `bytes` bytes.
    func file(_ relative: String, bytes: Int = 4096, contents: String? = nil) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = contents.map { Data($0.utf8) } ?? Data(repeating: 0x41, count: bytes)
        try data.write(to: url)
    }

    func folder(_ relative: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    /// Sets a tree's modification times `days` ago, deepest first.
    func age(_ relative: String, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        let base = home.appendingPathComponent(relative)
        var paths = [base.path]
        if let walker = FileManager.default.enumerator(atPath: base.path) {
            for case let sub as String in walker { paths.append(base.path + "/" + sub) }
        }
        for path in paths.sorted(by: { $0.count > $1.count }) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }
    }

    private func build() throws {
        // Build folders.
        try file("Developer/swift-old/Package.swift", contents: "// swift-tools-version: 6.2")
        try file("Developer/swift-old/.build/debug/thing.o", bytes: 64_000)
        try age("Developer/swift-old/.build", days: 40)
        try file("Developer/swift-recent/Package.swift", contents: "// swift-tools-version: 6.2")
        try file("Developer/swift-recent/.build/debug/thing.o", bytes: 8000)
        try file("Developer/web/package.json", contents: "{}")
        try file("Developer/web/node_modules/left-pad/index.js", bytes: 2000)
        try age("Developer/web/node_modules", days: 20)
        try file("Developer/nomarker/.build/thing.o")
        try age("Developer/nomarker/.build", days: 40)
        try file("Developer/rust/Cargo.toml", contents: "[package]")
        try file("Developer/rust/target/CACHEDIR.TAG", contents: CacheDirTag.signature + "\n")
        try file("Developer/rust/target/debug/app", bytes: 9000)
        try age("Developer/rust/target", days: 40)
        try file("Developer/Tool.app/Contents/Resources/proj/package.json", contents: "{}")
        try file("Developer/Tool.app/Contents/Resources/proj/node_modules/x.js")
        // Xcode.
        try file("Library/Developer/Xcode/DerivedData/App-abcdef/Build/out.o", bytes: 20_000)
        try age("Library/Developer/Xcode/DerivedData/App-abcdef", days: 10)
        try file("Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)/Symbols/dyld", bytes: 30_000)
        try file("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 18.1 (22B83)/Symbols/dyld", bytes: 30_000)
        try file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist")
        // Core AI.
        try file("Library/Caches/coreai-cache/25A100/imagine/model.bin", bytes: 50_000)
        try file("Library/Caches/coreai-cache/\(Fixture.currentBuild)/imagine/model.bin", bytes: 50_000)
        try file("Library/Caches/coreai-cache/sync/25A100/a.lock")
        // Caches: owned, orphaned, Apple's, recent, locked.
        try file("Library/Caches/org.swift.swiftpm/repositories/x", bytes: 10_000)
        try age("Library/Caches/org.swift.swiftpm", days: 60)
        try file("Library/Caches/com.example.gone/data", bytes: 12_000)
        try age("Library/Caches/com.example.gone", days: 90)
        try file("Library/Caches/com.example.fresh/data", bytes: 1000)
        try file("Library/Caches/com.apple.something/data", bytes: 1000)
        try age("Library/Caches/com.apple.something", days: 90)
        try file("Library/Caches/com.installed.app/data", bytes: 1000)
        try age("Library/Caches/com.installed.app", days: 90)
        try file("Library/Caches/net.silent.app/data", bytes: 1000)
        try age("Library/Caches/net.silent.app", days: 90)
        try file("Library/Caches/plainname/data", bytes: 1000)
        try age("Library/Caches/plainname", days: 90)
        try file("Library/Caches/locked.cache/data", bytes: 1000)
        try age("Library/Caches/locked.cache", days: 90)
        _ = CommandRunner.run("/bin/chmod", ["000", path("Library/Caches/locked.cache")], timeout: 10)
        // A container whose owner is in its metadata, not its name.
        try folder("Library/Containers/ABC-container/Data/Library")
        try file("Library/Containers/ABC-container/Data/Library/blob", bytes: 7000)
        let metadata = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "com.example.containergone"], format: .xml, options: 0)
        try metadata.write(to: home.appendingPathComponent("Library/Containers/ABC-container/.com.apple.containermanagerd.metadata.plist"))
        try age("Library/Containers/ABC-container", days: 90)
        // Package caches and the stand-in uv.
        try file(".cache/uv/archive/x", bytes: 30_000)
        try age(".cache/uv", days: 5)
        try file("bin/uv", contents: "#!/bin/sh\necho \"$@\" > \"$(dirname \"$0\")/../uv-ran\"\nrm -rf \"$(dirname \"$0\")/../.cache/uv/archive\"\n")
        _ = CommandRunner.run("/bin/chmod", ["+x", path("bin/uv")], timeout: 10)
        // Never touched.
        try file(".ssh/id_ed25519", contents: "not a real key")
        try file("Library/Logs/old.log", bytes: 2000)
        try age("Library/Logs/old.log", days: 30)
        try file(".Trash/already-here.txt", contents: "x")
    }
}

/// Real installers, made once: an app at several versions in DMGs, a pkg, a
/// zip, an encrypted image, and the installed copies they are judged against.
enum InstallerFixtures {

    struct Built: Sendable {
        let root: URL
        let downloads: URL
        let applications: URL
    }

    static func app(_ name: String, id: String, version: String, in folder: URL) throws {
        let contents = folder.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleVersion": version,
            "CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleExecutable": name,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\n".utf8).write(to: contents.appendingPathComponent("MacOS/\(name)"))
    }

    static func build() throws -> Built {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-installers-\(UUID().uuidString.prefix(8))")
        let downloads = root.appendingPathComponent("Downloads")
        let applications = root.appendingPathComponent("Applications")
        let staging = root.appendingPathComponent(".staging")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try app("Same", id: "dev.diskmaid.fixture.same", version: "1.0", in: applications)
        try app("Older", id: "dev.diskmaid.fixture.older", version: "1.0", in: applications)
        try app("Packaged", id: "dev.diskmaid.fixture.packaged", version: "2.0", in: applications)
        try app("Zipped", id: "dev.diskmaid.fixture.zipped", version: "3.1", in: applications)

        func image(_ name: String, app appName: String, id: String, version: String, encrypted: Bool = false) throws {
            let source = staging.appendingPathComponent(name)
            try app(appName, id: id, version: version, in: source)
            var arguments = ["create", "-quiet", "-srcfolder", source.path, "-volname", appName, "-format", "UDZO"]
            if encrypted { arguments += ["-encryption", "AES-128", "-stdinpass"] }
            arguments.append(downloads.appendingPathComponent(name + ".dmg").path)
            let output = CommandRunner.run("/usr/bin/hdiutil", arguments, timeout: 120, input: encrypted ? Data("fixture".utf8) : nil)
            guard output?.succeeded == true else { throw CocoaError(.fileWriteUnknown) }
        }
        try image("dead", app: "Same", id: "dev.diskmaid.fixture.same", version: "1.0")
        try image("pending", app: "Older", id: "dev.diskmaid.fixture.older", version: "2.0")
        try image("unknown", app: "Nobody", id: "dev.diskmaid.fixture.nobody", version: "1.0")
        try image("encrypted", app: "Same", id: "dev.diskmaid.fixture.same", version: "1.0", encrypted: true)

        let pkgSource = staging.appendingPathComponent("pkg")
        try app("Packaged", id: "dev.diskmaid.fixture.packaged", version: "1.5", in: pkgSource)
        let pkg = CommandRunner.run("/usr/bin/pkgbuild", [
            "--quiet", "--root", pkgSource.path, "--identifier", "dev.diskmaid.fixture.pkg", "--version", "1.5",
            "--install-location", "/Applications", downloads.appendingPathComponent("packaged.pkg").path,
        ], timeout: 120)
        guard pkg?.succeeded == true else { throw CocoaError(.fileWriteUnknown) }

        let zipSource = staging.appendingPathComponent("zip")
        try app("Zipped", id: "dev.diskmaid.fixture.zipped", version: "3.1", in: zipSource)
        let zip = CommandRunner.run("/usr/bin/zip", ["-qr", downloads.appendingPathComponent("zipped.zip").path, "Zipped.app"],
                                    timeout: 60, directory: zipSource.path)
        guard zip?.succeeded == true else { throw CocoaError(.fileWriteUnknown) }
        try Data("not an app".utf8).write(to: staging.appendingPathComponent("photo.jpg"))
        let photos = CommandRunner.run("/usr/bin/zip", ["-q", downloads.appendingPathComponent("photos.zip").path, "photo.jpg"],
                                       timeout: 60, directory: staging.path)
        guard photos?.succeeded == true else { throw CocoaError(.fileWriteUnknown) }
        try? FileManager.default.removeItem(at: staging)
        return Built(root: root, downloads: downloads, applications: applications)
    }
}
