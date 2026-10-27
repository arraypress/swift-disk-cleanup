//
//  DiskHealth.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The startup drive's own health report, as `diskutil info` passes it on:
/// the SMART verdict, and the NVMe log behind it when the drive gives one.
public struct DiskHealth: Codable, Equatable, Sendable {
    /// `Verified`, `Failing`, `Not Supported`…
    public var smart: String?
    /// The drive's estimate of its rated life used, in percent (can pass 100).
    public var lifeUsedPercent: Int?
    /// Spare capacity left, in percent.
    public var sparePercent: Int?
    /// The spare level the drive warns below, in percent.
    public var spareThresholdPercent: Int?
    /// Unrecovered data errors.
    public var mediaErrors: Int?
    /// Everything ever written to it, in bytes.
    public var writtenBytes: Int64?
    /// Hours powered on.
    public var powerOnHours: Int?
    /// Its temperature now, in °C.
    public var temperatureCelsius: Int?
    /// Times it lost power without being shut down cleanly.
    public var unsafeShutdowns: Int?

    /// A report.
    public init(smart: String? = nil, lifeUsedPercent: Int? = nil, sparePercent: Int? = nil, spareThresholdPercent: Int? = nil,
                mediaErrors: Int? = nil, writtenBytes: Int64? = nil, powerOnHours: Int? = nil, temperatureCelsius: Int? = nil,
                unsafeShutdowns: Int? = nil) {
        self.smart = smart
        self.lifeUsedPercent = lifeUsedPercent
        self.sparePercent = sparePercent
        self.spareThresholdPercent = spareThresholdPercent
        self.mediaErrors = mediaErrors
        self.writtenBytes = writtenBytes
        self.powerOnHours = powerOnHours
        self.temperatureCelsius = temperatureCelsius
        self.unsafeShutdowns = unsafeShutdowns
    }
}
