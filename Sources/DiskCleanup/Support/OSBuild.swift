//
//  OSBuild.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum OSBuild {

    /// Whether a folder name is a macOS build number: `26A428`, `24G90`, `25A5279m`.
    static func isBuild(_ name: String) -> Bool {
        name.wholeMatch(of: /\d{2}[A-Z]\d{1,5}[a-z]?/) != nil
    }

    /// The build and version in `ProcessInfo.operatingSystemVersionString`
    /// (`Version 27.0 (Build 26A428)`).
    static func parse(_ text: String) -> (version: String?, build: String?) {
        let version = text.firstMatch(of: /Version\s+([\d.]+)/).map { String($0.1) }
        let build = text.firstMatch(of: /Build\s+([0-9A-Za-z]+)/).map { String($0.1) }
        return (version, build)
    }
}
