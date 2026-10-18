//
//  BigFiles.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Big files a person made or fetched and may have forgotten, found by
//  Spotlight (`mdfind` on kMDItemFSSize, `mdls` for when each was last used
//  and modified). Left out: everything in ~/Library (Dropbox and iCloud
//  files there go everywhere when trashed), anything a catalogue rule owns
//  (it has its own judgement), anything inside a bundle or package, and
//  iCloud placeholders. Review tier, to the Trash with undo — except in a
//  protected place (Pictures, Music, Movies…), where a file is shown,
//  report only, and never removed by diskmaid.
//

import Foundation

public enum BigFiles {

    /// Rule name on the items; their category is internal only.
    public static let rule = "big-file"

    /// Files in `path` over `overBytes`, biggest first; with `unusedDays`,
    /// only those not used — or, never opened, not modified — for that long.
    public static func find(in path: String, overBytes: Int64, unusedDays: Int?, catalogue: Catalogue, context: CleanupContext,
                            now: Date = Date()) -> (items: [Item], notes: [String]) {
        guard let mdfind = CommandLocator.system("mdfind", at: "/usr/bin/mdfind", in: context),
              let mdls = CommandLocator.system("mdls", at: "/usr/bin/mdls", in: context),
              let found = CommandRunner.run(mdfind, ["-onlyin", path, "kMDItemFSSize > \(overBytes)"], timeout: 120), found.succeeded else {
            return ([], ["Spotlight did not answer, so big files could not be looked for"])
        }
        let library = context.home.path + "/Library"
        let categories = Set(CleanupCategory.allCases).subtracting([.installers])
        let owned = Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: categories, measure: false))
            .items.map(\.path).filter { $0.hasPrefix("/") }
        let paths = found.text.split(whereSeparator: \.isNewline).map(String.init).filter { file in
            !PathText.isWithin(file, library)
                && !owned.contains { PathText.isWithin(file, $0) }
                && !insidePackage(file)
                && PathProbe.isFile(file) && !Sizer.isDataless(file)
        }
        var records: [SpotlightFile] = []
        for start in stride(from: 0, to: paths.count, by: 100) {
            records += read(Array(paths[start..<min(start + 100, paths.count)]), mdls: mdls)
        }
        let cutoff = unusedDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        let formatter = ISO8601DateFormatter()
        var items: [Item] = []
        for record in records {
            if let cutoff, let touched = record.lastUsed ?? record.modified, touched > cutoff { continue }
            let measured = Sizer.measure(record.path)
            guard measured.visibility == .visible else { continue }
            var evidence = [
                "spotlightSize": String(record.size ?? measured.bytes),
                "lastUsed": record.lastUsed.map(formatter.string) ?? "never opened (by Spotlight's record)",
            ]
            if let modified = record.modified { evidence["modified"] = formatter.string(from: modified) }
            let protected = PathSafety.reason(for: record.path, catalogue: catalogue, home: context.home.path)
                .map { "\($0): diskmaid never removes from here — use Finder if you are sure" }
            items.append(Item(
                id: ItemID.make(rule: rule, path: record.path), rule: rule, category: .leftovers, path: record.path,
                bytes: measured.bytes, tier: protected == nil ? .review : .report, removal: .trash, regenerable: false, owner: nil,
                newest: record.modified ?? measured.newest, visibility: .visible, protected: protected, evidence: evidence,
                note: nil, identity: Sizer.identity(record.path, bytes: measured.bytes), apparentBytes: measured.apparentBytes
            ))
        }
        return (items.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }, [])
    }

    /// Packages macOS may not have registered: a file inside one is a part,
    /// and taking it breaks the whole (a model, a disk image, a project).
    static let packages: Set<String> = ["aimodel", "mlmodelc", "mlpackage", "xcarchive", "sparsebundle", "sparseimage",
                                        "photoslibrary", "logicx", "band", "fcpbundle", "rtfd", "playground", "xcodeproj"]

    /// Whether a folder above `path` is a package or bundle.
    static func insidePackage(_ path: String) -> Bool {
        var folder = PathText.parent(path)
        while folder != "/" {
            let name = PathText.lastComponent(folder)
            let ext = (name as NSString).pathExtension.lowercased()
            if UninstallMatch.isBundle(name) || packages.contains(ext) { return true }
            if !ext.isEmpty, (try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return true }
            folder = PathText.parent(folder)
        }
        return false
    }

    /// What to take: the named ones, or with `all` every one found; named
    /// ones that cannot go come back with why.
    public static func select(_ items: [Item], ids: Set<String>, all: Bool, now: Date = Date()) -> (take: [Item], held: [(Item, String)]) {
        let pick = Selection.pick(items, categories: all ? [.leftovers] : [], ids: ids, includeReview: all, olderThanDays: nil, now: now)
        return (pick.take, pick.held.map { ($0.0, $0.1) })
    }

    /// One `mdls` for a batch; one per file if the batch does not line up.
    static func read(_ paths: [String], mdls: String) -> [SpotlightFile] {
        let names = SpotlightText.names.flatMap { ["-name", $0] }
        if let output = CommandRunner.run(mdls, ["-raw", "-nullMarker", "(null)"] + names + paths, timeout: 120),
           let files = SpotlightText.files(output.stdout, paths: paths) {
            return files
        }
        return paths.compactMap { path in
            CommandRunner.run(mdls, ["-raw", "-nullMarker", "(null)"] + names + [path], timeout: 30)
                .flatMap { SpotlightText.files($0.stdout, paths: [path])?.first }
        }
    }
}
