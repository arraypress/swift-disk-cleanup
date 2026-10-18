//
//  PluginEntry.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One plugin found: an audio plugin, a Quick Look plugin, a preference
/// pane, an Internet plug-in or a legacy Safari extension.
public struct PluginEntry: Codable, Equatable, Sendable {
    public let path: String
    /// `AU`, `VST`, `VST3`, `CLAP`, `AAX`, `Quick Look`, `Preference Pane`,
    /// `Internet Plug-in` or `Safari Extension`.
    public let format: String
    public let name: String
    public let bundleID: String?
    /// The bundle id's first two parts (`com.xfer`), or `unknown`.
    public let vendor: String
    public let version: String?
    /// `arm64`, `x86_64`…; `nil` when the binary could not be read.
    public let architectures: [String]?
    public let bytes: Int64?
    /// Why it cannot load, when it provably cannot — then it may go (review).
    public let cannotLoad: String?
    /// The removable item's id, when it may go.
    public let itemID: String?

    public init(path: String, format: String, name: String, bundleID: String?, vendor: String, version: String?,
                architectures: [String]?, bytes: Int64?, cannotLoad: String?, itemID: String?) {
        self.path = path
        self.format = format
        self.name = name
        self.bundleID = bundleID
        self.vendor = vendor
        self.version = version
        self.architectures = architectures
        self.bytes = bytes
        self.cannotLoad = cannotLoad
        self.itemID = itemID
    }
}
