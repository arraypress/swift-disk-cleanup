//
//  InstallerJudge.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Dead means the same or a newer version is installed — nothing else. A
//  newer installer is a pending update. No answer, or no installed copy found,
//  is "unknown": an installer for an app that was never installed may be the
//  only copy someone has.
//

import Foundation

enum InstallerJudge {

    /// The verdict for an installer that names an app.
    static func judge(_ info: InstallerInfo, answer: AppAnswer) -> InstallerInfo {
        var info = info
        switch answer {
        case .noAnswer(let why):
            info.verdict = .unknown
            info.reason = "no answer about \(info.bundleID ?? "the app"): \(why)"
        case .notInstalled:
            info.verdict = .unknown
            info.reason = "no installed copy found"
        case .installed(let apps):
            guard let version = info.version else {
                info.verdict = .unknown
                info.reason = "the installer carries no version"
                return info
            }
            let best = apps.max { a, b in
                (VersionOrder.compare(a.version ?? "", b.version ?? "") ?? .orderedSame) == .orderedAscending
            }
            guard let best, let installed = best.version else {
                info.verdict = .unknown
                info.reason = "the installed copy has no version"
                return info
            }
            info.installedPath = best.path
            info.installedVersion = installed
            guard let order = VersionOrder.compare(installed, version) else {
                info.verdict = .unknown
                info.reason = "versions \(installed) and \(version) cannot be compared"
                return info
            }
            switch order {
            case .orderedAscending:
                info.verdict = .pendingUpdate
                info.reason = "installer \(version) is newer than installed \(installed)"
            case .orderedDescending:
                info.verdict = .dead
                info.reason = "installed \(installed) is newer than installer \(version)"
            case .orderedSame:
                if let build = info.build, let installedBuild = best.build,
                   VersionOrder.compare(installedBuild, build) == .orderedAscending {
                    info.verdict = .pendingUpdate
                    info.reason = "same version, but installer build \(build) is newer than \(installedBuild)"
                } else {
                    info.verdict = .dead
                    info.reason = "installed \(installed) is the same version"
                }
            }
        }
        return info
    }

    /// The verdict for a package with no app inside, from its receipts:
    /// `installed[id]` is the recorded version, or `nil` for no receipt.
    static func judgeReceipts(_ info: InstallerInfo, packages: [PackageRef],
                              installed: [String: String?]) -> InstallerInfo {
        var info = info
        guard !packages.isEmpty else {
            info.verdict = .unreadable
            info.reason = "names neither an app nor a package receipt"
            return info
        }
        var newer: [String] = []
        for package in packages {
            guard let recorded = installed[package.id], let recorded else {
                info.verdict = .unknown
                info.reason = "no receipt for \(package.id)"
                return info
            }
            guard let version = package.version, let order = VersionOrder.compare(recorded, version) else {
                info.verdict = .unknown
                info.reason = "cannot compare \(package.id)'s versions"
                return info
            }
            if order == .orderedAscending { newer.append(package.id) }
            info.installedVersion = recorded
        }
        if newer.isEmpty {
            info.verdict = .dead
            info.reason = "every receipt is installed at the same or a newer version"
        } else {
            info.verdict = .pendingUpdate
            info.reason = "newer than installed: \(newer.joined(separator: ", "))"
        }
        return info
    }

    /// A macOS installer app is dead once this Mac runs that version or later.
    static func judgeMacOS(_ info: InstallerInfo, osVersion: String?) -> InstallerInfo {
        var info = info
        guard let version = info.version, let osVersion,
              let order = VersionOrder.compare(osVersion, version) else {
            info.verdict = .unknown
            info.reason = "cannot compare with the running macOS"
            return info
        }
        info.installedVersion = osVersion
        if order == .orderedAscending {
            info.verdict = .pendingUpdate
            info.reason = "installs macOS \(version), newer than this Mac's \(osVersion)"
        } else {
            info.verdict = .dead
            info.reason = "this Mac already runs macOS \(osVersion)"
        }
        return info
    }
}
