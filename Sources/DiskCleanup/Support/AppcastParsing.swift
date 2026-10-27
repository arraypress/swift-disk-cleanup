//
//  AppcastParsing.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  A Sparkle appcast's newest release: every `<item>`'s
//  `sparkle:shortVersionString` (what people see) and `sparkle:version`
//  (the build Sparkle compares), from the item or its enclosure, the
//  highest by build. Pure: XML in, a release out.
//

import Foundation

enum AppcastParsing {

    /// One release in a feed.
    struct Release: Sendable, Equatable {
        var shortVersion: String?
        var build: String?
        /// The oldest macOS it runs on, when the feed says.
        var minimumSystem: String?
    }

    /// The newest release in `data`, or nil when it holds none.
    static func newest(_ data: Data) -> Release? {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() || !reader.releases.isEmpty else { return nil }
        return reader.releases.max { a, b in
            let left = a.build ?? a.shortVersion ?? "", right = b.build ?? b.shortVersion ?? ""
            return VersionOrder.compare(left, right) == .orderedAscending
        }
    }

    /// Collects each item's versions, from attributes or elements.
    private final class Reader: NSObject, XMLParserDelegate {
        var releases: [Release] = []
        private var current: Release?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "item" { current = Release() }
            if name == "enclosure", var release = current {
                release.shortVersion = release.shortVersion ?? attributes["sparkle:shortVersionString"]
                release.build = release.build ?? attributes["sparkle:version"]
                current = release
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:shortVersionString" where !value.isEmpty: current?.shortVersion = value
            case "sparkle:version" where !value.isEmpty: current?.build = value
            case "sparkle:minimumSystemVersion" where !value.isEmpty: current?.minimumSystem = value
            case "item":
                if let release = current, release.build != nil || release.shortVersion != nil { releases.append(release) }
                current = nil
            default: break
            }
            text = ""
        }
    }
}
