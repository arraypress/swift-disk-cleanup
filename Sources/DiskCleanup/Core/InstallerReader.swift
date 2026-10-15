//
//  InstallerReader.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Reading what an installer would install, without installing it and
//  without showing anything:
//
//  - DMG: `hdiutil isencrypted` first (an encrypted image would ask for a
//    password), then `imageinfo` for a licence agreement (that would ask to
//    be accepted); only then attach read-only, hidden, never auto-opened, at a
//    private mount point — and always detach.
//  - PKG: `xar` reads Distribution and PackageInfo out of the archive; the
//    payload is never expanded.
//  - ZIP: `unzip -p` reads one Info.plist; a zip with no app is not an installer.
//

import Foundation

public enum InstallerReader {

    /// What kind of installer a path could be, by name — the reader then decides.
    public static func kind(of path: String) -> InstallerKind? {
        let name = PathText.lastComponent(path)
        let lower = name.lowercased()
        if lower.hasSuffix(".app") { return lower.hasPrefix("install macos") ? .macOSInstaller : nil }
        if lower.hasSuffix(".dmg") { return .dmg }
        if lower.hasSuffix(".pkg") || lower.hasSuffix(".mpkg") { return .pkg }
        if lower.hasSuffix(".zip") { return .zip }
        if lower.hasSuffix(".xip") { return .xip }
        return nil
    }

    /// Reads and judges one installer. `nil` when it turns out not to be one
    /// (a zip of photos).
    public static func inspect(_ path: String, context: CleanupContext, index: AppIndex) -> InstallerInfo? {
        guard let kind = kind(of: path) else { return nil }
        switch kind {
        case .dmg: return inspectDMG(path, context: context, index: index)
        case .pkg: return inspectPKG(path, context: context, index: index, kind: .pkg)
        case .zip:
            guard let bundle = readZIP(path) else { return nil }
            return judge(InstallerInfo(path: path, kind: .zip, verdict: .unknown, reason: ""), bundles: [bundle], context: context, index: index)
        case .xip:
            var info = InstallerInfo(path: path, kind: .xip, bundleID: "com.apple.dt.Xcode", name: "Xcode",
                                     version: ModelStoreNames.xcodeVersion(PathText.lastComponent(path)),
                                     verdict: .unknown, reason: "")
            guard info.version != nil else {
                info.reason = "no Xcode version in the file name"
                return info
            }
            return InstallerJudge.judge(info, answer: index.answer("com.apple.dt.Xcode", lookup: context.lookup))
        case .macOSInstaller:
            let name = PathText.lastComponent(path)
            let info = InstallerInfo(path: path, kind: .macOSInstaller, bundleID: AppIndex.read(appAt: path)?.bundleID,
                                     name: String(name.dropLast(4)),
                                     version: MacOSNames.version(ofInstaller: String(name.dropLast(4))),
                                     verdict: .unknown, reason: "")
            return InstallerJudge.judgeMacOS(info, osVersion: context.osVersion)
        }
    }

    // MARK: DMG

    static func inspectDMG(_ path: String, context: CleanupContext, index: AppIndex) -> InstallerInfo {
        var info = InstallerInfo(path: path, kind: .dmg, verdict: .unreadable, reason: "")
        guard let encrypted = CommandRunner.run("/usr/bin/hdiutil", ["isencrypted", path], timeout: 30),
              encrypted.succeeded, let isEncrypted = HdiutilOutput.isEncrypted(encrypted.text + encrypted.errorText) else {
            info.reason = "hdiutil could not read it"
            return info
        }
        if isEncrypted {
            info.verdict = .encrypted
            info.reason = "encrypted: opening it would ask for a password"
            return info
        }
        guard let imageInfo = CommandRunner.run("/usr/bin/hdiutil", ["imageinfo", "-plist", path], timeout: 30),
              imageInfo.succeeded, let licence = HdiutilOutput.hasLicenceAgreement(imageInfo.stdout) else {
            info.reason = "hdiutil could not say whether it has a licence agreement"
            return info
        }
        if licence {
            info.verdict = .licenceAgreement
            info.reason = "has a licence agreement: attaching it would ask for consent"
            return info
        }
        let mountRoot = FileManager.default.temporaryDirectory.appendingPathComponent("diskmaid-mount-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: mountRoot, withIntermediateDirectories: true)) != nil else {
            info.reason = "no private mount point"
            return info
        }
        defer { try? FileManager.default.removeItem(at: mountRoot) }
        let attach = CommandRunner.run("/usr/bin/hdiutil", [
            "attach", "-readonly", "-nobrowse", "-noautoopen", "-noverify", "-noautofsck",
            "-mountrandom", mountRoot.path, "-plist", path,
        ], timeout: 90)
        let mounts = attach.map { HdiutilOutput.mountPoints($0.stdout) } ?? []
        defer {
            for mount in mounts { detach(mount) }
            // A timed-out attach may still have mounted something under the root.
            for name in PathProbe.list(mountRoot.path).names { detach(mountRoot.path + "/" + name) }
        }
        guard let attach, attach.succeeded, !mounts.isEmpty else {
            info.reason = "it would not attach: \(attach?.errorText.suffix(200) ?? "hdiutil did not start")"
            return info
        }
        var bundles: [BundleInfo] = []
        var packages: [String] = []
        for mount in mounts {
            for name in PathProbe.list(mount).names where !name.hasPrefix(".") {
                let item = mount + "/" + name
                if name.hasSuffix(".app"), let app = AppIndex.read(appAt: item) {
                    bundles.append(BundleInfo(bundleID: app.bundleID, version: app.version, build: app.build, name: app.name))
                } else if name.hasSuffix(".pkg") || name.hasSuffix(".mpkg") {
                    packages.append(item)
                }
            }
        }
        if bundles.isEmpty, let package = packages.first {
            // An image that only carries a package: judge the package.
            var judged = inspectPKG(package, context: context, index: index, kind: .dmg)
            judged = InstallerInfo(path: path, kind: .dmg, bundleID: judged.bundleID, name: judged.name, version: judged.version,
                                   build: judged.build, packageIDs: judged.packageIDs, installedPath: judged.installedPath,
                                   installedVersion: judged.installedVersion, verdict: judged.verdict, reason: judged.reason)
            return judged
        }
        guard !bundles.isEmpty else {
            info.reason = "no app or package at the top of the image"
            return info
        }
        return judge(info, bundles: bundles, context: context, index: index)
    }

    static func detach(_ mount: String) {
        if CommandRunner.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"], timeout: 30)?.succeeded != true {
            _ = CommandRunner.run("/usr/bin/hdiutil", ["detach", mount, "-force", "-quiet"], timeout: 30)
        }
    }

    // MARK: PKG

    static func inspectPKG(_ path: String, context: CleanupContext, index: AppIndex, kind: InstallerKind) -> InstallerInfo {
        var info = InstallerInfo(path: path, kind: kind, verdict: .unreadable, reason: "")
        guard let contents = readPKG(path) else {
            info.reason = "xar could not read its Distribution or PackageInfo"
            return info
        }
        info.packageIDs = contents.packages.map(\.id)
        info.name = contents.title
        if !contents.bundles.isEmpty {
            return judge(info, bundles: contents.bundles, context: context, index: index)
        }
        var installed: [String: String?] = [:]
        for package in contents.packages {
            installed[package.id] = receiptVersion(package.id)
        }
        info.version = contents.packages.first?.version
        return InstallerJudge.judgeReceipts(info, packages: contents.packages, installed: installed)
    }

    /// Distribution and PackageInfo out of a flat package.
    public static func readPKG(_ path: String) -> PackageContents? {
        guard PathProbe.isFile(path),
              let listing = CommandRunner.run("/usr/bin/xar", ["-tf", path], timeout: 30), listing.succeeded else { return nil }
        let names = listing.text.split(whereSeparator: \.isNewline).map(String.init).filter { name in
            name == "Distribution" || name == "PackageInfo"
                || (name.hasSuffix("/PackageInfo") && PathText.components(name).count == 2)
        }
        guard !names.isEmpty else { return nil }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("diskmaid-xar-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let extract = CommandRunner.run("/usr/bin/xar", ["-xf", path, "-C", scratch.path] + names, timeout: 60),
              extract.succeeded else { return nil }
        let distribution = names.contains("Distribution") ? PathProbe.read(scratch.path + "/Distribution") : nil
        let infos = names.filter { $0 != "Distribution" }.compactMap { PathProbe.read(scratch.path + "/" + $0) }
        let contents = PackageXML.contents(distribution: distribution, packageInfos: infos)
        return contents.packages.isEmpty && contents.bundles.isEmpty ? nil : contents
    }

    /// The version `pkgutil` has on record for a receipt, or `nil` for none.
    static func receiptVersion(_ id: String) -> String? {
        guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }),
              let output = CommandRunner.run("/usr/sbin/pkgutil", ["--pkg-info-plist", id], timeout: 20),
              output.succeeded, let plist = PlistValues.dictionary(output.stdout) else { return nil }
        return plist["pkg-version"] as? String
    }

    // MARK: ZIP

    /// The Info.plist of the shallowest app in a zip, or `nil` when it holds none.
    public static func readZIP(_ path: String) -> BundleInfo? {
        guard let listing = CommandRunner.run("/usr/bin/unzip", ["-Z1", path], timeout: 30), listing.succeeded else { return nil }
        let entries = listing.text.split(whereSeparator: \.isNewline).map(String.init).filter { entry in
            !entry.hasPrefix("__MACOSX/") && entry.wholeMatch(of: /(?:[^\/]+\/)?[^\/]+\.app\/Contents\/Info\.plist/) != nil
        }
        guard let entry = entries.min(by: { $0.count < $1.count }) else { return nil }
        // unzip treats [ ] * ? in a name as a pattern; escape them so the name is literal.
        let literal = entry.reduce(into: "") { result, character in
            if "[]*?".contains(character) { result.append("\\") }
            result.append(character)
        }
        guard let data = CommandRunner.run("/usr/bin/unzip", ["-p", path, literal], timeout: 30), data.succeeded else { return nil }
        return PlistValues.bundleInfo(data.stdout)
    }

    // MARK: Judging

    /// Judges every app an installer carries: dead only if all are dead, a
    /// pending update if any is newer, unknown otherwise.
    static func judge(_ info: InstallerInfo, bundles: [BundleInfo], context: CleanupContext, index: AppIndex) -> InstallerInfo {
        var verdicts: [InstallerInfo] = []
        for bundle in bundles {
            var one = info
            one.bundleID = bundle.bundleID
            one.version = bundle.version
            one.build = bundle.build
            one.name = one.name ?? bundle.name
            verdicts.append(InstallerJudge.judge(one, answer: index.answer(bundle.bundleID, lookup: context.lookup)))
        }
        if let pending = verdicts.first(where: { $0.verdict == .pendingUpdate }) { return pending }
        if let unsure = verdicts.first(where: { $0.verdict != .dead }) { return unsure }
        return verdicts.first ?? info
    }
}
