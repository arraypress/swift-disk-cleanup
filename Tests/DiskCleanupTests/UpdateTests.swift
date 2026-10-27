//
//  UpdateTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Update checks with no network: a stand-in fetcher answers for an App
//  Store lookup, a Sparkle feed and Homebrew's catalogue, and fixture apps
//  take each road. The apps, feeds and casks are invented.
//

import Foundation
import Testing
@testable import DiskCleanup

/// The network, as a table of answers; anything else fails.
struct TableFetcher: UpdateFetching {
    let answers: [String: Data]
    func data(from url: URL) async throws -> Data {
        guard let data = answers.first(where: { url.absoluteString.contains($0.key) })?.value else { throw URLError(.cannotFindHost) }
        return data
    }
}

struct UpdateTests {

    static let appcast = Data("""
        <?xml version="1.0"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>3.1</title><sparkle:version>310</sparkle:version><sparkle:shortVersionString>3.1</sparkle:shortVersionString>
            <enclosure url="https://example.com/a.zip"/></item>
          <item><title>3.2</title><enclosure url="https://example.com/b.zip" sparkle:version="320" sparkle:shortVersionString="3.2"/>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion></item>
          <item><title>3.0</title><sparkle:version>300</sparkle:version></item>
        </channel></rss>
        """.utf8)

    static let casks = Data("""
        [{"token": "chatter", "version": "5.0.1,9001", "artifacts": [{"app": ["Chatter.app"]}]},
         {"token": "tunnel", "version": "2026.6", "artifacts": [{"pkg": ["Tunnel.pkg"]}, {"uninstall": [{"quit": "com.example.tunnel", "pkgutil": "x"}]}]},
         {"token": "nightly", "version": "latest", "artifacts": [{"app": ["Nightly.app"]}]},
         {"token": "renamed", "version": "1.0", "artifacts": [{"app": ["Weird.app", {"target": "Renamed.app"}]}]}]
        """.utf8)

    // MARK: - Pure

    @Test func theNewestReleaseIsTheHighestBuildWhereverItIsWritten() throws {
        let newest = try #require(AppcastParsing.newest(Self.appcast))
        #expect(newest.build == "320", "a version on the enclosure counts")
        #expect(newest.shortVersion == "3.2")
        #expect(newest.minimumSystem == "15.0")
        #expect(AppcastParsing.newest(Data("<rss><channel></channel></rss>".utf8)) == nil)
    }

    @Test func casksAreFoundByAppNameAndByTheAppTheyQuit() {
        let casks = UpdateCatalogues.casks(Self.casks)
        #expect(casks["chatter.app"] == .init(token: "chatter", version: "5.0.1"), "version,build reads as version")
        #expect(casks["id:com.example.tunnel"]?.version == "2026.6", "a package cask names its app by bundle id")
        #expect(casks["nightly.app"] == nil, "`latest` is no version")
        #expect(casks["renamed.app"]?.token == "renamed", "a renamed app is found by its new name")
        #expect(UpdateCatalogues.appStoreVersion(Data(#"{"resultCount":1,"results":[{"version":"26.42.74"}]}"#.utf8)) == "26.42.74")
        #expect(UpdateCatalogues.appStoreVersion(Data(#"{"resultCount":0,"results":[]}"#.utf8)) == nil)
    }

    @Test func statusComparesBuildsWhenBothHaveThem() {
        #expect(UpdateRules.status(installed: ("3.1", "310"), latest: ("3.2", "320")) == .available)
        #expect(UpdateRules.status(installed: ("3.2", "320"), latest: ("3.2", "320")) == .current)
        #expect(UpdateRules.status(installed: ("3.2", "330"), latest: ("3.2", "320")) == .current, "newer than the feed is current")
        #expect(UpdateRules.status(installed: ("277.3", nil), latest: ("274.4", nil)) == .current)
        #expect(UpdateRules.status(installed: ("1.9", "x"), latest: ("1.10", nil)) == .available, "short versions when builds can't")
        #expect(UpdateRules.status(installed: (nil, nil), latest: ("1.0", nil)) == .unknown, "no installed version is unknown")
        #expect(UpdateRules.status(installed: ("beta", nil), latest: ("1.0", nil)) == .unknown)
    }

    // MARK: - Every road

    static func app(_ name: String, id: String, version: String, build: String? = nil, feed: String? = nil,
                    receipt: Bool = false, in folder: URL) throws {
        let contents = folder.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleName": name]
        if let build { plist["CFBundleVersion"] = build }
        if let feed { plist["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        if receipt {
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("_MASReceipt"), withIntermediateDirectories: true)
            try Data([1]).write(to: contents.appendingPathComponent("_MASReceipt/receipt"))
        }
    }

    @Test func eachAppIsAskedOfTheSourceThatKnowsItBest() async throws {
        let folder = URL(fileURLWithPath: "/private/tmp/diskmaid-updates-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.app("Messenger", id: "com.example.messenger", version: "26.41.74", receipt: true, in: folder)
        try Self.app("Transfer", id: "com.example.transfer", version: "3.1", build: "310", feed: "https://feeds.example.com/transfer.xml", in: folder)
        try Self.app("Chatter", id: "com.example.chatter", version: "5.0.1", in: folder)
        try Self.app("Tunnel", id: "com.example.tunnel", version: "2026.5", in: folder)
        try Self.app("Orphan", id: "com.example.orphan", version: "1.0", in: folder)
        try Self.app("Broken Feed", id: "com.example.broken", version: "1.0", feed: "https://down.example.com/feed.xml", in: folder)
        try Self.app("Finder Plus", id: "com.apple.finderplus", version: "1.0", in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Caskroom/tunnel"), withIntermediateDirectories: true)

        let fetcher = TableFetcher(answers: [
            "itunes.apple.com/lookup": Data(#"{"resultCount":1,"results":[{"version":"26.42.74"}]}"#.utf8),
            "feeds.example.com/transfer.xml": Self.appcast,
            "formulae.brew.sh": Self.casks,
        ])
        let results = await AppUpdates.check([folder], fetcher: fetcher, cache: nil,
                                             caskroom: folder.appendingPathComponent("Caskroom").path)
        let by = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0) })
        #expect(by["Finder Plus"] == nil, "Apple's apps update with macOS")
        #expect(by["Messenger"]?.source == .appStore && by["Messenger"]?.status == .available)
        #expect(by["Transfer"]?.source == .sparkle && by["Transfer"]?.status == .available && by["Transfer"]?.latest == "3.2")
        #expect(by["Chatter"]?.source == .homebrew && by["Chatter"]?.status == .current)
        #expect(by["Tunnel"]?.status == .available && by["Tunnel"]?.detail == "brew upgrade --cask tunnel", "installed through Homebrew")
        #expect(by["Orphan"]?.source == UpdateSource.none && by["Orphan"]?.status == .unknown)
        #expect(by["Broken Feed"]?.status == .unknown, "a feed that does not answer is unknown, never current")
        #expect(results.prefix(3).allSatisfy { $0.status == .available }, "updates first")
    }

    @Test func theCatalogueIsCachedForADayAndAStaleOneBeatsNone() async throws {
        let cache = URL(fileURLWithPath: "/private/tmp/diskmaid-cask-\(UUID().uuidString.prefix(8)).json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let online = TableFetcher(answers: ["formulae.brew.sh": Self.casks])
        let offline = TableFetcher(answers: [:])
        #expect(await AppUpdates.catalogue(fetcher: online, cache: cache)?["chatter.app"] != nil)
        #expect(FileManager.default.fileExists(atPath: cache.path), "fetched and kept")
        #expect(await AppUpdates.catalogue(fetcher: offline, cache: cache)?["chatter.app"] != nil, "a fresh cache needs no network")
        let tomorrow = Date().addingTimeInterval(2 * 86_400)
        #expect(await AppUpdates.catalogue(fetcher: offline, cache: cache, now: tomorrow)?["chatter.app"] != nil, "stale beats none")
        #expect(await AppUpdates.catalogue(fetcher: offline, cache: nil) == nil)
        try Data("[]".utf8).write(to: cache)
        #expect(await AppUpdates.catalogue(fetcher: online, cache: cache, now: tomorrow)?["chatter.app"] != nil,
                "a day-old catalogue is fetched again")
    }
}
