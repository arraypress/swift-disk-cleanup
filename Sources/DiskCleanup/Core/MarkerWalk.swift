//
//  MarkerWalk.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Build folders are only build folders beside the file that makes them:
//  `.build` next to `Package.swift`, `target` next to `Cargo.toml`. One walk
//  of the project roots serves every marker rule. The walk never enters a
//  folder it found, a hidden folder, an app bundle, `Library`, a folder that
//  says it is a cache (CACHEDIR.TAG), or an iCloud placeholder; and it stops
//  `depth` folders down.
//

import Foundation

enum MarkerWalk {

    /// Folders never walked into: not projects, or someone else's tree.
    static let skipped: Set<String> = ["node_modules", "Library", "Applications", "Pods", "DerivedData"]

    /// Candidates per rule id, and the roots with their visibility.
    static func find(rules: [Rule], roots: [String], depth: Int) -> (byRule: [String: [Candidate]], roots: [(String, Visibility)]) {
        var byRule: [String: [Candidate]] = [:]
        var seenRoots: [(String, Visibility)] = []
        for root in roots {
            let visibility = PathProbe.visibility(root)
            seenRoots.append((root, visibility))
            guard visibility == .visible else { continue }
            visit(root, level: 0, depth: depth, rules: rules, byRule: &byRule, roots: &seenRoots)
        }
        return (byRule, seenRoots)
    }

    private static func visit(_ folder: String, level: Int, depth: Int, rules: [Rule],
                              byRule: inout [String: [Candidate]], roots: inout [(String, Visibility)]) {
        let listing = PathProbe.list(folder)
        if listing.visibility == .notVisible { roots.append((folder, .notVisible)) }
        let names = listing.names
        if level > 0, names.contains("CACHEDIR.TAG"),
           let tag = PathProbe.read(folder + "/CACHEDIR.TAG", limit: 64), CacheDirTag.isValid(tag) {
            return
        }
        var taken = Set<String>()
        for rule in rules {
            guard let marker = names.first(where: { name in
                rule.marker.contains { Glob.matches($0, name) } && PathProbe.isFile(folder + "/" + name)
            }) else { continue }
            for name in names where !taken.contains(name) && rule.paths.contains(where: { Glob.matches($0, name) }) {
                let path = folder + "/" + name
                guard PathProbe.isDirectory(path) else { continue }
                taken.insert(name)
                var candidate = Candidate(path: path, evidence: ["marker": marker, "project": folder])
                candidate.checkGit = true
                candidate.protected = protection(inside: path)
                if let tag = PathProbe.read(path + "/CACHEDIR.TAG", limit: 64), CacheDirTag.isValid(tag) {
                    candidate.evidence["cachedirTag"] = "yes"
                }
                byRule[rule.id, default: []].append(candidate)
            }
        }
        guard level < depth else { return }
        for name in names where !name.hasPrefix(".") && !taken.contains(name) && !skipped.contains(name)
            && !name.hasSuffix(".app") && !name.hasSuffix(".photoslibrary") {
            let path = folder + "/" + name
            guard PathProbe.isDirectory(path), !Sizer.isDataless(path) else { continue }
            visit(path, level: level + 1, depth: depth, rules: rules, byRule: &byRule, roots: &roots)
        }
    }

    /// Why a found build folder must stay, from what sits at its top.
    static func protection(inside path: String) -> String? {
        let components = PathText.components(path)
        if components.dropLast().contains(where: { $0.hasSuffix(".app") }) { return "inside an app bundle" }
        let names = PathProbe.list(path).names
        if names.contains(".git") { return "holds its own git repository" }
        if names.contains(where: { $0.hasSuffix("-keypair.json") }) { return "holds a keypair file" }
        return nil
    }
}
