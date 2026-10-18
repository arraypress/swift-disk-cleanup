//
//  UninstallMatch.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The pure half of uninstalling: reading what pkgutil and codesign print,
//  turning names into tokens a folder name can match, telling a bundle from
//  a shared folder, and writing the one sudo line a person runs.
//

import Foundation

enum UninstallMatch {

    /// A receipt from `pkgutil --pkg-info` and `--files` output.
    static func receipt(id: String, info: String, files: String) -> PackageReceipt {
        var fields: [String: String] = [:]
        for line in info.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let listed = files.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        return PackageReceipt(id: id, volume: fields["volume"] ?? "/", location: fields["location"] ?? "", files: listed)
    }

    /// Where a receipt's paths start, under `root` (`/`, or a fixture's).
    static func base(of receipt: PackageReceipt, root: String) -> String {
        let parts = PathText.components(receipt.volume) + PathText.components(receipt.location)
        let prefix = root == "/" ? "" : root
        return prefix + "/" + parts.joined(separator: "/")
    }

    /// Where macOS keeps its own receipts, SIP-restricted: they cannot be forgotten.
    static let systemReceipts = "/Library/Apple/System/Library/Receipts"

    /// Whether a receipt kept in `store` is macOS's to keep.
    static func isSystemHeld(_ store: String?) -> Bool {
        store.map { PathText.isWithin($0, systemReceipts) } ?? false
    }

    /// The `pkgid:` lines of `pkgutil --file-info`.
    static func owners(fromFileInfo text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("pkgid: ") ? String(line.dropFirst("pkgid: ".count)) : nil
        }
    }

    /// Every path a receipt lists, absolute on its volume (`/Library/…`).
    static func listedPaths(_ receipt: PackageReceipt) -> [String] {
        let base = PathText.components(receipt.location)
        return receipt.files.map { "/" + (base + PathText.components($0)).joined(separator: "/") }
    }

    /// `TeamIdentifier=ABCDE12345` from `codesign -dv`; `nil` when unsigned or ad hoc.
    static func teamID(fromCodesign text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("TeamIdentifier=") {
            let value = String(line.dropFirst("TeamIdentifier=".count))
            return isTeamID(value) ? value : nil
        }
        return nil
    }

    /// Ten upper-case letters and digits.
    static func isTeamID(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { ($0.isUppercase && $0.isASCII) || ($0.isNumber && $0.isASCII) }
    }

    /// Lower-case letters and digits only: `Valhalla DSP, LLC` → `valhalladspllc`.
    static func folded(_ name: String) -> String {
        String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// A vendor's own word without the trade it names: `com.valhalladsp` →
    /// `valhalla`, `com.native-instruments` → `nativeinstruments`.
    static func vendorStem(_ vendor: String) -> String {
        var word = folded(String(vendor.split(separator: ".").last ?? ""))
        for suffix in ["software", "studios", "studio", "audio", "sound", "music", "labs", "apps", "dsp", "inc", "llc", "ltd"]
        where word.hasSuffix(suffix) && word.count - suffix.count >= 5 {
            word = String(word.dropLast(suffix.count))
            break
        }
        return word
    }

    /// The words a folder name must contain to be a name match: each name of
    /// four letters or more, and the vendor's stem of five or more.
    static func tokens(names: [String], vendor: String?) -> [String] {
        var tokens = names.map(folded).filter { $0.count >= 4 }
        if let vendor {
            let stem = vendorStem(vendor)
            if stem.count >= 5 { tokens.append(stem) }
        }
        return Array(Set(tokens)).sorted()
    }

    /// The token a file or folder name contains, if any.
    static func matchedToken(_ name: String, tokens: [String]) -> String? {
        let name = folded(name)
        return tokens.first { name.contains($0) }
    }

    /// A folder that is one product whole: an app, a plug-in, a framework.
    static func isBundle(_ name: String) -> Bool {
        let bundles: Set<String> = ["app", "component", "vst", "vst3", "clap", "aaxplugin", "bundle", "plugin", "framework",
                                    "kext", "appex", "prefpane", "mdimporter", "qlgenerator", "saver", "driver", "dext", "xpc"]
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return bundles.contains(name[name.index(after: dot)...].lowercased())
    }

    /// The one line a person runs for what diskmaid will not do as itself:
    /// system launch jobs unloaded, root-owned paths removed, receipts forgotten.
    static func byHand(paths: [String], systemJobs: [String], receipts: [String]) -> String? {
        var steps: [String] = []
        if !paths.isEmpty { steps.append("sudo rm -rf " + paths.map(PathText.shellQuoted).joined(separator: " ")) }
        // A few receipts read best one by one; hundreds (Apple's sound content) as a loop.
        if receipts.count <= 3 {
            steps += receipts.map { "sudo pkgutil --forget " + PathText.shellQuoted($0) }
        } else {
            steps.append("for id in " + receipts.map(PathText.shellQuoted).joined(separator: " ") + "; do sudo pkgutil --forget \"$id\"; done")
        }
        let unload = systemJobs.map { "sudo launchctl bootout system/" + PathText.shellQuoted($0) }.joined(separator: "; ")
        guard !steps.isEmpty || !unload.isEmpty else { return nil }
        // Unloading may say "not loaded"; that must not stop the removal after it.
        let rest = steps.joined(separator: " && ")
        if unload.isEmpty { return rest }
        return rest.isEmpty ? unload : unload + "; " + rest
    }
}
