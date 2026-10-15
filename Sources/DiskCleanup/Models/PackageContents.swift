//
//  PackageContents.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a flat package's Distribution and PackageInfo files promise to install.
public struct PackageContents: Codable, Equatable, Sendable {
    /// Receipt identifiers with the version each would record.
    public var packages: [PackageRef]
    /// App bundles inside the payload, by their Info.plist values.
    public var bundles: [BundleInfo]
    /// The product title, when the Distribution file gives one.
    public var title: String?

    public init(packages: [PackageRef] = [], bundles: [BundleInfo] = [], title: String? = nil) {
        self.packages = packages
        self.bundles = bundles
        self.title = title
    }
}

/// One package receipt: `pkgutil --pkg-info` knows it by `id`.
public struct PackageRef: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String?

    public init(id: String, version: String?) {
        self.id = id
        self.version = version
    }
}
