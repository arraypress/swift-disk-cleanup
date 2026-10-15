//
//  PlistValues.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum PlistValues {

    /// The top-level dictionary of a property list (XML or binary).
    static func dictionary(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// An Info.plist's identity: `nil` without a bundle identifier.
    static func bundleInfo(_ data: Data) -> BundleInfo? {
        guard let plist = dictionary(data),
              let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        return BundleInfo(
            bundleID: id,
            version: plist["CFBundleShortVersionString"] as? String,
            build: plist["CFBundleVersion"] as? String,
            name: (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
        )
    }

    /// The owner a container's `.com.apple.containermanagerd.metadata.plist` names.
    static func containerOwner(_ data: Data) -> String? {
        dictionary(data)?["MCMMetadataIdentifier"] as? String
    }

    /// A launchd plist's label and the program it runs.
    static func launchJob(_ data: Data) -> (label: String?, program: String?)? {
        guard let plist = dictionary(data) else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        return (plist["Label"] as? String, program)
    }
}
