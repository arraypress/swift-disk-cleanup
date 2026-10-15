//
//  BundleInfo.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The four Info.plist values every decision here turns on.
public struct BundleInfo: Codable, Equatable, Sendable {
    public let bundleID: String
    public let version: String?
    public let build: String?
    public let name: String?

    public init(bundleID: String, version: String?, build: String?, name: String?) {
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.name = name
    }
}
