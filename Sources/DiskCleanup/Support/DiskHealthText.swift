//
//  DiskHealthText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The drive's health from `diskutil info -plist`, and the line that says
//  what it means. Pure. NVMe counts data in units of 1,000 × 512 bytes and
//  reports its temperature in kelvin; both are converted. A drive that only
//  gives the SMART verdict (or none) gives only that.
//

import Foundation

enum DiskHealthText {

    /// One NVMe data unit, in bytes.
    static let dataUnit: Int64 = 512_000

    /// The health in a `diskutil info -plist` answer, or nil with none of it.
    static func health(fromInfo data: Data) -> DiskHealth? {
        guard let plist = PlistValues.dictionary(data) else { return nil }
        let log = plist["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Int64? { (log[key] as? NSNumber)?.int64Value }
        var health = DiskHealth(smart: plist["SMARTStatus"] as? String)
        health.lifeUsedPercent = number("PERCENTAGE_USED").map(Int.init)
        health.sparePercent = number("AVAILABLE_SPARE").map(Int.init)
        health.spareThresholdPercent = number("AVAILABLE_SPARE_THRESHOLD").map(Int.init)
        health.mediaErrors = number("MEDIA_ERRORS_0").map(Int.init)
        health.writtenBytes = number("DATA_UNITS_WRITTEN_0").map { $0 * dataUnit }
        health.powerOnHours = number("POWER_ON_HOURS_0").map(Int.init)
        health.temperatureCelsius = number("TEMPERATURE").flatMap { $0 > 200 ? Int($0 - 273) : nil }
        health.unsafeShutdowns = number("UNSAFE_SHUTDOWNS_0").map(Int.init)
        return health == DiskHealth() ? nil : health
    }

    /// What the health says, in a line: the verdict first, then the numbers
    /// behind it, and a warning when one of them calls for a backup.
    static func meaning(_ health: DiskHealth) -> String {
        var parts: [String] = []
        if let smart = health.smart { parts.append("SMART \(smart.lowercased())") }
        if let used = health.lifeUsedPercent { parts.append("\(used)% of its rated life used") }
        if let spare = health.sparePercent { parts.append("\(spare)% spare") }
        if let errors = health.mediaErrors { parts.append("\(errors) media error\(errors == 1 ? "" : "s")") }
        if let written = health.writtenBytes { parts.append("\(SystemText.size(written)) written") }
        if let hours = health.powerOnHours { parts.append("\(hours.formatted()) hours on") }
        if let celsius = health.temperatureCelsius { parts.append("\(celsius) °C") }
        if let unsafe = health.unsafeShutdowns { parts.append("\(unsafe) unsafe shutdown\(unsafe == 1 ? "" : "s")") }
        var line = parts.joined(separator: " · ")
        if let warning = warning(health) { line += ". " + warning }
        return line
    }

    /// Why the drive needs attention, or nil when nothing says so.
    static func warning(_ health: DiskHealth) -> String? {
        if let smart = health.smart, smart.lowercased() != "verified", smart.lowercased() != "not supported" {
            return "The drive reports itself failing: back up now."
        }
        if let errors = health.mediaErrors, errors > 0 { return "It has lost data it could not recover: back up, and watch this number." }
        if let spare = health.sparePercent, let threshold = health.spareThresholdPercent, spare <= threshold {
            return "Its spare capacity is at the level it warns below: back up."
        }
        if let used = health.lifeUsedPercent, used >= 90 { return "It is near the end of its rated life: keep backups current." }
        return nil
    }
}
