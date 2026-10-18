//
//  SystemReader.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The facts behind "System Data": the volume's figures from Foundation,
//  the container's volumes from diskutil, snapshots from tmutil and
//  diskutil, swap from sysctl, the sleep image from its file. Reads only.
//  A fixture home finds these tools only in <home>/bin.
//

import Darwin
import Foundation

public enum SystemReader {

    /// What the Mac says about its own space. `scan`, when given, adds the
    /// clone gap of what diskmaid found.
    public static func read(context: CleanupContext, scan: ScanReport? = nil) -> SystemSpace {
        var space = SystemSpace()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? context.home.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity {
            space.totalBytes = Int64(total)
            if let free = values.volumeAvailableCapacity {
                space.freeBytes = Int64(free)
                space.usedBytes = Int64(total) - Int64(free)
            }
            space.importantFreeBytes = values.volumeAvailableCapacityForImportantUsage
        }
        var fs = statfs()
        if space.freeBytes == nil, statfs(context.home.path, &fs) == 0 {
            space.freeBytes = Int64(fs.f_bavail) * Int64(fs.f_bsize)
        }

        let diskutil = tool("diskutil", system: "/usr/sbin/diskutil", context: context)
        if let diskutil, let info = run(diskutil, ["info", "-plist", "/"]), let container = SystemText.container(fromInfo: info) {
            space.container = container
            if let list = run(diskutil, ["apfs", "list", "-plist"]) {
                space.volumes = SystemText.volumes(fromList: list, container: container) ?? []
            }
        }
        var names: [String]?
        if let tmutil = tool("tmutil", system: "/usr/bin/tmutil", context: context), let text = run(tmutil, ["listlocalsnapshots", "/"]) {
            names = TmutilText.snapshots(String(decoding: text, as: UTF8.self))
        }
        if let diskutil, let list = run(diskutil, ["apfs", "listSnapshots", "-plist", "/System/Volumes/Data"]),
           let more = SystemText.snapshotNames(fromList: list) {
            names = Array(Set((names ?? []) + more)).sorted()
        }
        space.snapshots = names.map { $0.map(SystemText.snapshot) }
        if let sysctl = tool("sysctl", system: "/usr/sbin/sysctl", context: context), let text = run(sysctl, ["vm.swapusage"]) {
            space.swapBytes = SystemText.swapTotal(String(decoding: text, as: UTF8.self))
        }
        let root = context.root.path == "/" ? "" : context.root.path
        var info = stat()
        if lstat(root + "/private/var/vm/sleepimage", &info) == 0 { space.sleepImageBytes = Int64(info.st_blocks) * 512 }
        if let scan {
            let measured = scan.items.filter { $0.path.hasPrefix("/") }
            space.scannedBytes = measured.reduce(0) { $0 + ($1.bytes ?? 0) }
            space.scannedApparentBytes = measured.reduce(0) { $0 + ($1.apparentBytes ?? $1.bytes ?? 0) }
        }
        return space
    }

    /// The figures with their meaning.
    public static func lines(_ space: SystemSpace) -> [SystemLine] { SystemText.lines(space) }

    /// A system tool: its own path, or for a fixture only `<home>/bin`.
    static func tool(_ name: String, system: String, context: CleanupContext) -> String? {
        let path = context.isFixture ? context.home.path + "/bin/" + name : system
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func run(_ tool: String, _ arguments: [String]) -> Data? {
        guard let output = CommandRunner.run(tool, arguments, timeout: 60), output.succeeded else { return nil }
        return output.stdout
    }
}
