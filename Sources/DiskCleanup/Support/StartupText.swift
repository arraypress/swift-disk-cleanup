//
//  StartupText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The pure half of `startup`: whose a program is, whether it is Apple's,
//  how an item may go, and what launchctl and AppleScript print.
//

import Foundation

enum StartupText {

    /// Login Items in System Settings.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    /// macOS's own: Apple's label, or a plist in the system's own folders.
    /// What it runs says nothing — anyone's agent may run /bin/sh.
    static func isApple(label: String, plist: String) -> Bool {
        label.lowercased().hasPrefix("com.apple.") || ["/System/", "/Library/Apple/"].contains { plist.hasPrefix($0) }
    }

    /// The `.app` a program lives in, if any.
    static func app(containing program: String) -> String? {
        var parts: [String] = []
        for part in PathText.components(program) {
            parts.append(part)
            if part.hasSuffix(".app") { return "/" + parts.joined(separator: "/") }
        }
        return nil
    }

    /// The label → disabled table of `launchctl print-disabled`.
    static func disabled(_ text: String) -> [String: Bool] {
        var table: [String: Bool] = [:]
        for match in text.matches(of: /"([^"]+)"\s*=>\s*(\w+)/) {
            table[String(match.1)] = ["disabled", "true"].contains(String(match.2))
        }
        return table
    }

    /// `{{"A", "B"}, {"/Applications/A.app", "/b"}}` from System Events' login items, as (name, path).
    static func loginItems(_ text: String) -> [(name: String, path: String)] {
        let values = text.matches(of: /"((?:[^"\\]|\\.)*)"/).map { String($0.1) }
        guard values.count % 2 == 0 else { return [] }
        let half = values.count / 2
        return (0..<half).map { (values[$0], values[$0 + half]) }
    }

    /// How a startup item may go.
    static func removal(kind: String, path: String, isApple: Bool, home: String) -> String {
        if isApple { return "never" }
        switch kind {
        case "app-service": return "settings"
        case "login-item": return "system-events"
        default: return PathText.isWithin(path, home + "/Library/LaunchAgents") ? "trash" : "sudo"
        }
    }
}
