//
//  SystemText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Reading what diskutil, tmutil and sysctl print, and saying in a sentence
//  what each figure is. Pure: the reader runs the tools.
//

import Foundation

enum SystemText {

    /// `APFSContainerReference` from `diskutil info -plist /`.
    static func container(fromInfo data: Data) -> String? {
        PlistValues.dictionary(data)?["APFSContainerReference"] as? String
    }

    /// The volumes of `container` from `diskutil apfs list -plist`.
    static func volumes(fromList data: Data, container: String) -> [APFSVolumeInfo]? {
        guard let containers = PlistValues.dictionary(data)?["Containers"] as? [[String: Any]],
              let match = containers.first(where: { $0["ContainerReference"] as? String == container }),
              let volumes = match["Volumes"] as? [[String: Any]] else { return nil }
        return volumes.map { volume in
            APFSVolumeInfo(name: volume["Name"] as? String ?? "?", roles: volume["Roles"] as? [String] ?? [],
                           usedBytes: (volume["CapacityInUse"] as? NSNumber)?.int64Value ?? 0,
                           device: volume["DeviceIdentifier"] as? String ?? "")
        }
    }

    /// Snapshot names from `diskutil apfs listSnapshots -plist`.
    static func snapshotNames(fromList data: Data) -> [String]? {
        guard let snapshots = PlistValues.dictionary(data)?["Snapshots"] as? [[String: Any]] else { return nil }
        return snapshots.compactMap { $0["SnapshotName"] as? String }
    }

    /// A snapshot's date from its name: `…2026-10-18-101010…`.
    static func snapshot(_ name: String) -> LocalSnapshot {
        var date: Date?
        if let match = name.firstMatch(of: /(\d{4}-\d{2}-\d{2}-\d{6})/) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            date = formatter.date(from: String(match.1))
        }
        return LocalSnapshot(name: name, date: date, isSystem: TmutilText.isSystemOwned(name))
    }

    /// `total = 2048.00M` from `sysctl vm.swapusage`, in bytes.
    static func swapTotal(_ text: String) -> Int64? {
        guard let match = text.firstMatch(of: /total = ([0-9.]+)([KMG])/), let value = Double(match.1) else { return nil }
        let unit: Double = match.2 == "K" ? 1024 : match.2 == "M" ? 1_048_576 : 1_073_741_824
        return Int64(value * unit)
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// Every figure with a sentence of what it means, in reading order.
    static func lines(_ space: SystemSpace) -> [SystemLine] {
        var lines: [SystemLine] = []
        if let total = space.totalBytes {
            lines.append(SystemLine(key: "total", label: "Disk", bytes: total, meaning: "The startup disk, shared by every volume listed below."))
        }
        if let used = space.usedBytes {
            lines.append(SystemLine(key: "used", label: "Used", bytes: used, meaning: "Everything on it now, every volume together: your files and apps, and what makes up System Data."))
        }
        if let free = space.freeBytes {
            lines.append(SystemLine(key: "free", label: "Free", bytes: free, meaning: "Space nothing is using: what a disk-almost-full warning counts."))
        }
        if let important = space.importantFreeBytes {
            lines.append(SystemLine(key: "importantFree", label: "Available", bytes: important,
                                    meaning: "Free space plus what macOS would clear itself for something important; Finder's figure."))
        }
        if let purgeable = space.purgeableBytes {
            lines.append(SystemLine(key: "purgeable", label: "Purgeable", bytes: purgeable,
                                    meaning: "Space macOS counts as used but frees on demand — its own caches and local snapshots. Nothing to do."))
        }
        if let health = space.health {
            lines.append(SystemLine(key: "health", label: "Drive health", bytes: nil, meaning: DiskHealthText.meaning(health)))
        }
        switch space.snapshots {
        case nil:
            lines.append(SystemLine(key: "snapshots", label: "Snapshots", bytes: nil, meaning: "Not known: tmutil and diskutil did not answer."))
        case let snapshots? where snapshots.isEmpty:
            lines.append(SystemLine(key: "snapshots", label: "Snapshots", bytes: nil, meaning: "No local snapshots, so none of System Data is old versions of files."))
        case let snapshots?:
            let system = snapshots.filter(\.isSystem).count
            var meaning = "\(snapshots.count) local snapshot\(snapshots.count == 1 ? "" : "s") holding earlier versions of changed files; macOS does not say how much each holds, and Time Machine's go by themselves within a day or when space runs short."
            if system > 0 { meaning += " \(system) belong\(system == 1 ? "s" : "") to an OS update." }
            lines.append(SystemLine(key: "snapshots", label: "Snapshots", bytes: nil, meaning: meaning))
            let formatter = ISO8601DateFormatter()
            for snapshot in snapshots {
                lines.append(SystemLine(key: "snapshot", label: "  " + snapshot.name, bytes: nil,
                                        meaning: (snapshot.date.map { "Taken \(formatter.string(from: $0)). " } ?? "") + "Size not reported by macOS."))
            }
        }
        if let swap = space.swapBytes {
            lines.append(SystemLine(key: "swap", label: "Swap", bytes: swap,
                                    meaning: swap == 0 ? "No swap in use: memory has not overflowed to disk." : "Memory overflowed to disk; it shrinks after a restart or when memory frees up."))
        }
        if let sleep = space.sleepImageBytes {
            lines.append(SystemLine(key: "sleepImage", label: "Sleep image", bytes: sleep,
                                    meaning: "A copy of memory kept for waking from deep sleep; macOS sizes and keeps it, so leave it."))
        }
        for volume in space.volumes {
            let role = volume.roles.first ?? ""
            lines.append(SystemLine(key: "volume", label: "Volume \(volume.name)" + (role.isEmpty ? "" : " (\(role))"), bytes: volume.usedBytes,
                                    meaning: roleMeaning(role)))
        }
        if let apparent = space.scannedApparentBytes, let bytes = space.scannedBytes {
            let shared = max(0, apparent - bytes)
            lines.append(SystemLine(key: "scanned", label: "Scanned", bytes: bytes,
                                    meaning: "What diskmaid's scan found, on disk: \(size(apparent)) counting every APFS clone in full, so \(size(shared)) is shared by clones and freeing one copy gives none of it back."))
        }
        return lines
    }

    static func roleMeaning(_ role: String) -> String {
        switch role {
        case "System": return "macOS itself, sealed and read-only; counted apart from your data."
        case "Data": return "Your files, apps and settings, and most of System Data: caches, logs, snapshots."
        case "Preboot": return "What the Mac reads before macOS starts: boot files for each installed macOS and the cryptexes that update it."
        case "Recovery": return "macOS Recovery, for repairs and reinstalls."
        case "VM": return "Swap and the sleep image."
        case "Update": return "Staging for macOS updates; empties once one is installed."
        default: return "A volume macOS uses for itself."
        }
    }
}
