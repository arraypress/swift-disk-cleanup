//
//  DiskHealthTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The drive's health from `diskutil info -plist`, with no drive: NVMe's
//  units and kelvin converted, a SMART-only drive, and the warnings that
//  call for a backup. The new maintenance tasks are checked too. The
//  numbers are invented.
//

import Foundation
import Testing
@testable import DiskCleanup

struct DiskHealthTests {

    static func info(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    static var nvme: [String: Any] { [
        "SMARTStatus": "Verified",
        "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": [
            "PERCENTAGE_USED": 12, "AVAILABLE_SPARE": 100, "AVAILABLE_SPARE_THRESHOLD": 99, "MEDIA_ERRORS_0": 0,
            "DATA_UNITS_WRITTEN_0": 1_000_000, "POWER_ON_HOURS_0": 7788, "TEMPERATURE": 317, "UNSAFE_SHUTDOWNS_0": 19,
        ],
    ] }

    @Test func anNVMeLogIsReadInBytesAndDegrees() throws {
        let health = try #require(DiskHealthText.health(fromInfo: Self.info(Self.nvme)))
        #expect(health.writtenBytes == 512_000_000_000, "a data unit is 1,000 × 512 bytes")
        #expect(health.temperatureCelsius == 44, "317 K")
        #expect(health.lifeUsedPercent == 12 && health.sparePercent == 100 && health.unsafeShutdowns == 19)
        let line = DiskHealthText.meaning(health)
        #expect(line.hasPrefix("SMART verified · 12% of its rated life used · 100% spare · 0 media errors"), "\(line)")
        #expect(!line.contains("back up"), "a healthy drive gets no warning")
    }

    @Test func aDriveWithOnlyAVerdictGivesOnlyThat() throws {
        let health = try #require(DiskHealthText.health(fromInfo: Self.info(["SMARTStatus": "Verified"])))
        #expect(DiskHealthText.meaning(health) == "SMART verified")
        #expect(DiskHealthText.health(fromInfo: try Self.info(["DeviceIdentifier": "disk3"])) == nil, "nothing to say, no line")
    }

    @Test func warningsCallForABackup() {
        #expect(DiskHealthText.warning(DiskHealth(smart: "Failing"))?.contains("failing") == true)
        #expect(DiskHealthText.warning(DiskHealth(smart: "Not Supported")) == nil, "an external drive that says nothing is not failing")
        #expect(DiskHealthText.warning(DiskHealth(smart: "Verified", mediaErrors: 2)) != nil)
        #expect(DiskHealthText.warning(DiskHealth(sparePercent: 9, spareThresholdPercent: 10)) != nil)
        #expect(DiskHealthText.warning(DiskHealth(lifeUsedPercent: 93)) != nil)
        #expect(DiskHealthText.warning(DiskHealth(smart: "Verified", lifeUsedPercent: 40, sparePercent: 100, spareThresholdPercent: 10,
                                                  mediaErrors: 0)) == nil)
    }

    @Test func theNewTasksAreDeclaredHonestly() throws {
        let tasks = Maintenance.tasks(volume: "/")
        let icons = try #require(tasks.first { $0.id == "icon-cache" })
        #expect(icons.needsRoot, "root's caches: a printed sudo line, never run")
        #expect(Maintenance.byHand([icons])?.contains("sudo") == true)
        let verify = try #require(tasks.first { $0.id == "verify-disk" })
        #expect(!verify.needsRoot && verify.commands == [["/usr/sbin/diskutil", "verifyVolume", "/"]], "read-only, no root")
    }
}
