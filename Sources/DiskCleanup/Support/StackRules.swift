//
//  StackRules.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  What an app is built with, from what is inside it. Pure: the names in
//  Contents/Frameworks and a few facts about the bundle come in, a stack and
//  the file that decided it go out. First match wins, in the order below —
//  an Electron app also ships Squirrel and Mantle, a Flutter one may carry
//  Sparkle; only the runtime decides. No match is not proof of native: an
//  app that renamed its runtime, or a WebKit wrapper like Tauri, reads as
//  native here.
//

import Foundation

enum StackRules {

    /// What a bundle holds, as the rules need it.
    struct Contents: Sendable, Equatable {
        /// The names in `Contents/Frameworks`: frameworks and dylibs.
        var frameworks: [String] = []
        /// Whether `Contents/MonoBundle` exists.
        var monoBundle = false
        /// Whether it carries a Java runtime (`Contents/runtime`, a `.jdk` plug-in, `Contents/Java`).
        var javaRuntime: String?
        /// Whether it is an iOS app in a `Wrapper/`.
        var wrapper = false
        /// Whether its Info.plist names the Mac as a UIKit device family (Catalyst).
        var catalyst = false
    }

    /// Runtime frameworks, in the order they decide.
    static let frameworkRules: [(match: @Sendable (String) -> Bool, stack: AppStack)] = [
        ({ $0 == "Electron Framework.framework" }, .electron),
        ({ $0 == "Chromium Embedded Framework.framework" }, .cef),
        ({ $0 == "nwjs Framework.framework" }, .nwjs),
        ({ $0 == "FlutterMacOS.framework" }, .flutter),
        ({ $0 == "React.framework" || $0 == "hermes.framework" }, .reactNative),
        ({ $0 == "QtCore.framework" || ($0.hasPrefix("libQt") && $0.hasSuffix(".dylib")) }, .qt),
        ({ $0 == "UnityPlayer.dylib" }, .unity),
    ]

    /// The stack and the file that decided it.
    static func stack(of contents: Contents) -> (stack: AppStack, evidence: String?) {
        if contents.wrapper { return (.iosApp, "Wrapper/") }
        for rule in frameworkRules {
            if let name = contents.frameworks.sorted().first(where: rule.match) {
                return (rule.stack, "Contents/Frameworks/" + name)
            }
        }
        if let java = contents.javaRuntime { return (.java, java) }
        if contents.monoBundle { return (.dotnet, "Contents/MonoBundle") }
        if contents.catalyst { return (.catalyst, "Info.plist: UIDeviceFamily") }
        return (.native, nil)
    }

    /// The Electron version from its framework's `CFBundleVersion`: the
    /// leading numbers only, as some vendors add their own suffix
    /// (`37.10.3-dropbox-75-…` is 37.10.3).
    static func electronVersion(_ bundleVersion: String) -> String? {
        let leading = bundleVersion.prefix { $0.isNumber || $0 == "." }
        let parts = leading.split(separator: ".")
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts.joined(separator: ".")
    }

    /// An Electron version's major number.
    static func major(_ version: String) -> Int? {
        version.split(separator: ".").first.flatMap { Int($0) }
    }

    /// A name without invisible formatting characters — direction marks and
    /// the like, which some apps put in their display name.
    static func cleanName(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespaces)
    }

    /// The architecture a binary's slices make: both kinds is universal.
    static func architecture(_ slices: [String]?) -> AppArchitecture {
        guard let slices, !slices.isEmpty else { return .unknown }
        let silicon = slices.contains { $0.hasPrefix("arm64") }
        let intel = slices.contains { $0.hasPrefix("x86_64") || $0 == "i386" }
        switch (silicon, intel) {
        case (true, true): return .universal
        case (true, false): return .appleSilicon
        case (false, true): return .intel
        default: return .unknown
        }
    }

    /// Whether a UIKit device family list names the Mac (6), as Catalyst apps do.
    static func isCatalyst(deviceFamily: [Int]?) -> Bool {
        deviceFamily?.contains(6) ?? false
    }
}
