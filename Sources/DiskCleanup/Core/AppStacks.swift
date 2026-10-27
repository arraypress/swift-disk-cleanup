//
//  AppStacks.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Every app in the app folders, and what each is built with — Electron,
//  Chromium Embedded, Flutter, Qt, Java, Catalyst, an iPhone app, or
//  native — read from the files inside it (StackRules), with its size, the
//  size of the runtime it carries, the processors it is built for and when
//  it was last opened (one Spotlight query for all of them). Read-only:
//  nothing is opened or run.
//

import Foundation

/// What the installed apps are built with.
public enum AppStacks {

    /// The app folders looked in when none are given: /Applications (with
    /// its subfolders) and ~/Applications. System apps are left out.
    public static func defaultFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// Every app under `folders`, biggest first.
    ///
    /// - Parameters:
    ///   - folders: Where to look, two levels deep.
    ///   - mdls: Spotlight's metadata tool, for when each app was last opened.
    /// - Returns: One report per app bundle.
    public static func scan(_ folders: [URL], mdls: String = "/usr/bin/mdls") -> [AppStackReport] {
        var seen: Set<String> = []
        var reports: [AppStackReport] = []
        var realPaths: [String] = []
        for folder in folders {
            for path in AppIndex.bundles(in: folder.path, depth: 2) {
                // /Applications/Safari.app is a link into the system's sealed
                // volume: measured as a link it is 0 bytes. The app it points
                // at is read and measured, and counted once however reached.
                let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                guard seen.insert(real).inserted else { continue }
                var made = report(appAt: real)
                made.path = path
                reports.append(made)
                realPaths.append(real)
            }
        }
        // Last opened: one Spotlight query for every app.
        if PathProbe.isFile(mdls), !realPaths.isEmpty {
            let opened = Dictionary(BigFiles.read(realPaths, mdls: mdls).map { ($0.path, $0.lastUsed) }, uniquingKeysWith: { a, _ in a })
            for index in reports.indices { reports[index].lastOpened = opened[realPaths[index]] ?? nil }
        }
        return reports.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
    }

    /// One app's report.
    public static func report(appAt path: String) -> AppStackReport {
        let contents = read(path)
        let decided = StackRules.stack(of: contents)
        let info = AppIndex.read(appAt: path)
        var runtime: Int64?
        var electron: String?
        if let evidence = decided.evidence, decided.stack != .native, decided.stack != .catalyst {
            let runtimePath = path + "/" + evidence.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if decided.stack != .iosApp { runtime = Sizer.measure(runtimePath).bytes }
            if decided.stack == .electron {
                electron = frameworkVersion(runtimePath).flatMap(StackRules.electronVersion)
            }
        }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let architecture = decided.stack == .iosApp ? .appleSilicon : StackRules.architecture(slices(path))
        return AppStackReport(name: StackRules.cleanName(info?.name ?? name), bundleID: info?.bundleID, path: path, version: info?.version,
                              stack: decided.stack, evidence: decided.evidence, bytes: Sizer.measure(path).bytes,
                              runtimeBytes: runtime, electronVersion: electron, architecture: architecture)
    }

    /// What the rules need from a bundle.
    static func read(_ path: String) -> StackRules.Contents {
        var contents = StackRules.Contents()
        contents.frameworks = PathProbe.list(path + "/Contents/Frameworks").names
        contents.monoBundle = PathProbe.isDirectory(path + "/Contents/MonoBundle")
        contents.wrapper = PathProbe.isDirectory(path + "/Wrapper")
        if PathProbe.isDirectory(path + "/Contents/runtime") {
            contents.javaRuntime = "Contents/runtime"
        } else if let jdk = PathProbe.list(path + "/Contents/PlugIns").names.first(where: { $0.hasSuffix(".jdk") || $0.hasSuffix(".jre") }) {
            contents.javaRuntime = "Contents/PlugIns/" + jdk
        } else if PathProbe.isDirectory(path + "/Contents/Java") {
            contents.javaRuntime = "Contents/Java"
        }
        if let data = PathProbe.read(path + "/Contents/Info.plist"), let plist = PlistValues.dictionary(data) {
            contents.catalyst = StackRules.isCatalyst(deviceFamily: plist["UIDeviceFamily"] as? [Int])
        }
        return contents
    }

    /// The architectures of an app's main binary, from its first 4 KB.
    static func slices(_ path: String) -> [String]? {
        guard let data = PathProbe.read(path + "/Contents/Info.plist"), let plist = PlistValues.dictionary(data),
              let executable = plist["CFBundleExecutable"] as? String else { return nil }
        return PathProbe.read(path + "/Contents/MacOS/" + executable, limit: 4096).flatMap(MachOText.architectures)
    }

    /// A framework's `CFBundleVersion`, wherever its Info.plist sits.
    static func frameworkVersion(_ framework: String) -> String? {
        for plist in ["/Versions/A/Resources/Info.plist", "/Resources/Info.plist"] {
            if let data = PathProbe.read(framework + plist), let values = PlistValues.dictionary(data),
               let version = values["CFBundleVersion"] as? String {
                return version
            }
        }
        return nil
    }
}
