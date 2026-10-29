//
//  ModelAssets.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The Core AI models on the disk, by the hash their compiled copies are
//  named after — so a compiled copy whose model is gone can be told apart
//  from one a tool still loads. Measured on a Mac after a day of exports:
//  92 GB of 213 GB in the cache belonged to models no longer on disk.
//

import Darwin
import Foundation

enum ModelAssets {

    /// Where models are kept: the app-support, cache and config folders, the
    /// project roots, Downloads, `/private/tmp`, this user's own temporary folder,
    /// `/Applications` and Homebrew's Cellar (a fixture's under its own root).
    /// Never Documents or Desktop: iCloud can sync them, and listing a folder it
    /// has offloaded makes macOS download it first — measured, a scan sat for
    /// minutes in a Whisper model under Documents. A model kept there has its
    /// compiled copy called orphaned: it is compiled again when next loaded.
    static func roots(_ context: CleanupContext) -> [String] {
        let home = context.home.path
        let root = context.root.path == "/" ? "" : context.root.path
        var roots = ["Library/Application Support", "Library/Caches", ".config", ".cache", "Downloads"]
            .map { home + "/" + $0 }
        roots += context.projectRoots.map(\.path)
        // Apps and Homebrew formulae can ship a model inside themselves.
        roots += root.isEmpty ? ["/private/tmp", NSTemporaryDirectory(), "/Applications", "/opt/homebrew/Cellar", "/usr/local/Cellar"]
                              : [root + "/private/tmp", root + "/Applications"]
        var seen = Set<String>()
        return roots.filter { seen.insert($0).inserted }
    }

    /// Every `.aimodel` under `roots`, keyed by its hash in lower case, valued by its path.
    /// A symlink is followed only when it is named `*.aimodel`; a folder in
    /// ``CompiledModelNames/skipped`` is never entered, nor one ``PathProbe``
    /// would not list (an iCloud placeholder is never made to download). No
    /// depth limit that would miss a model: a scratch export sat nine folders
    /// down in `/private/tmp`, and a walk cut at eight called its compiled copies
    /// orphaned. Entry types come from `readdir`, so only folders are stat'ed.
    static func hashes(under roots: [String]) -> [String: String] {
        var found: [String: String] = [:]
        var pending = roots
        while let folder = pending.popLast() {
            guard PathProbe.visibility(folder) == .visible, let directory = opendir(folder) else { continue }
            defer { closedir(directory) }
            while let entry = readdir(directory) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self) }
                guard name != ".", name != "..", !CompiledModelNames.skipped.contains(name) else { continue }
                let path = folder + "/" + name
                let type = entry.pointee.d_type
                if name.hasSuffix(".aimodel"), type == DT_DIR || type == DT_LNK {
                    // Both may be links: the asset (a bundle's shared encoder) and the file (a Hugging Face blob).
                    let file = URL(fileURLWithPath: path + "/main.hash").resolvingSymlinksInPath().path
                    if let data = PathProbe.read(file, limit: 4096), let hash = CompiledModelNames.hash(data) {
                        found[hash] = found[hash] ?? path
                    }
                } else if type == DT_DIR {
                    pending.append(path)
                }
            }
        }
        return found
    }
}
