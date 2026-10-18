//
//  SystemTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  "System Data" explained: what diskutil, tmutil and sysctl print, read
//  back; each figure's sentence; and the reader driven only by stand-in
//  tools in a fixture's bin — never this Mac's.
//

import Foundation
import Testing
@testable import DiskCleanup

struct SystemTests {

    static func plist(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    static var list: [String: Any] { ["Containers": [
        ["ContainerReference": "disk9", "Volumes": [["Name": "Other", "Roles": ["Data"], "CapacityInUse": 1, "DeviceIdentifier": "disk9s1"]]],
        ["ContainerReference": "disk3", "Volumes": [
            ["Name": "Macintosh HD", "Roles": ["System"], "CapacityInUse": 13_000_000_000, "DeviceIdentifier": "disk3s1"],
            ["Name": "Macintosh HD - Data", "Roles": ["Data"], "CapacityInUse": 376_000_000_000, "DeviceIdentifier": "disk3s5"],
            ["Name": "VM", "Roles": ["VM"], "CapacityInUse": 2_147_508_224, "DeviceIdentifier": "disk3s6"],
        ]],
    ]] }

    @Test func whatTheToolsPrintIsReadBack() throws {
        #expect(SystemText.container(fromInfo: try SystemTests.plist(["APFSContainerReference": "disk3"])) == "disk3")
        let volumes = try #require(SystemText.volumes(fromList: try SystemTests.plist(SystemTests.list), container: "disk3"))
        #expect(volumes.map(\.name) == ["Macintosh HD", "Macintosh HD - Data", "VM"])
        #expect(volumes[2] == APFSVolumeInfo(name: "VM", roles: ["VM"], usedBytes: 2_147_508_224, device: "disk3s6"))
        #expect(SystemText.snapshotNames(fromList: try SystemTests.plist(["Snapshots": [["SnapshotName": "com.apple.os.update-ABC"]]])) == ["com.apple.os.update-ABC"])
        let snapshot = SystemText.snapshot("com.apple.TimeMachine.2026-10-18-101010.local")
        #expect(snapshot.date != nil && !snapshot.isSystem)
        #expect(SystemText.snapshot("com.apple.os.update-ABC").isSystem)
        #expect(SystemText.swapTotal("vm.swapusage: total = 2048.00M  used = 1024.50M  free = 1023.50M  (encrypted)") == 2_147_483_648)
        #expect(SystemText.swapTotal("vm.swapusage: total = 0.00M  used = 0.00M") == 0)
    }

    @Test func eachFigureSaysWhatItMeans() {
        var space = SystemSpace()
        space.totalBytes = 1_000
        space.freeBytes = 100
        space.usedBytes = 900
        space.importantFreeBytes = 150
        space.scannedBytes = 400
        space.scannedApparentBytes = 1_400
        let unknown = SystemText.lines(space)
        #expect(unknown.first { $0.key == "purgeable" }?.bytes == 50)
        #expect(unknown.first { $0.key == "snapshots" }?.meaning.hasPrefix("Not known") == true)
        #expect(unknown.first { $0.key == "scanned" }?.meaning.contains("1 KB is shared by clones") == true, "\(unknown)")
        space.snapshots = []
        #expect(SystemText.lines(space).first { $0.key == "snapshots" }?.meaning.hasPrefix("No local snapshots") == true)
        space.snapshots = [SystemText.snapshot("com.apple.TimeMachine.2026-10-18-101010.local"), SystemText.snapshot("com.apple.os.update-ABC")]
        let some = SystemText.lines(space)
        let summary = try? #require(some.first { $0.key == "snapshots" })
        #expect(summary?.meaning.hasPrefix("2 local snapshots") == true && summary?.meaning.contains("1 belongs to an OS update") == true)
        #expect(some.filter { $0.key == "snapshot" }.count == 2)
        #expect(some.first { $0.label.contains("TimeMachine") }?.meaning.hasPrefix("Taken 2026-10-18") == true)
        space.importantFreeBytes = 90
        #expect(!SystemText.lines(space).contains { $0.key == "purgeable" })
    }

    @Test func theReaderAsksOnlyTheFixturesTools() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        // A bare fixture: no tools, so nothing of this Mac's is read.
        let bare = SystemReader.read(context: fixture.context())
        #expect(bare.snapshots == nil && bare.swapBytes == nil && bare.volumes.isEmpty && bare.sleepImageBytes == nil)

        let data = fixture.path("data")
        try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: true)
        try SystemTests.plist(["APFSContainerReference": "disk3"]).write(to: URL(fileURLWithPath: data + "/info.plist"))
        try SystemTests.plist(SystemTests.list).write(to: URL(fileURLWithPath: data + "/list.plist"))
        try SystemTests.plist(["Snapshots": [["SnapshotName": "com.apple.os.update-ABC"]]]).write(to: URL(fileURLWithPath: data + "/snaps.plist"))
        let tools = [
            "diskutil": "case \"$1 $2\" in\n\"info -plist\") cat '\(data)/info.plist' ;;\n\"apfs list\") cat '\(data)/list.plist' ;;\n\"apfs listSnapshots\") cat '\(data)/snaps.plist' ;;\nesac",
            "tmutil": "echo 'Snapshots for disk /:'; echo 'com.apple.TimeMachine.2026-10-18-101010.local'",
            "sysctl": "echo 'vm.swapusage: total = 1024.00M  used = 512.00M  free = 512.00M  (encrypted)'",
        ]
        for (name, body) in tools {
            try fixture.file("bin/" + name, contents: "#!/bin/sh\n" + body + "\n")
            _ = CommandRunner.run("/bin/chmod", ["755", fixture.path("bin/" + name)], timeout: 10)
        }
        try fixture.file("root/private/var/vm/sleepimage", bytes: 40_000)
        let space = SystemReader.read(context: fixture.context())
        #expect(space.container == "disk3")
        #expect(space.volumes.map(\.roles) == [["System"], ["Data"], ["VM"]])
        #expect(space.snapshots?.map(\.name) == ["com.apple.TimeMachine.2026-10-18-101010.local", "com.apple.os.update-ABC"])
        #expect(space.swapBytes == 1_073_741_824)
        #expect((space.sleepImageBytes ?? 0) >= 40_000)
        #expect((space.totalBytes ?? 0) > 0 && (space.freeBytes ?? 0) > 0)
    }

    @Test func apparentSizeCountsEveryCloneInFull() throws {
        let root = URL(fileURLWithPath: "/private/tmp/diskmaid-apparent-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }).write(to: root.appendingPathComponent("original"))
        for index in 0..<9 { #expect(clonefile(root.path + "/original", root.path + "/copy-\(index)", 0) == 0) }
        let measured = Sizer.measure(root.path)
        #expect(measured.bytes < 1_100_000, "\(measured.bytes)")
        #expect(measured.apparentBytes >= 10_000_000, "\(measured.apparentBytes)")
    }
}
