//
//  AppUpdates.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Which apps are out of date, read-only. Each app is asked of the source
//  that knows it best: the App Store's public lookup for an app it installed
//  (a `_MASReceipt`), the app's own Sparkle feed (`SUFeedURL`), else
//  Homebrew's public cask catalogue, matched by the app's bundle name —
//  which knows most apps that update themselves, Homebrew-installed or not.
//  The installed version is always the APP's own (MEASURED: Homebrew's
//  record said one app was 10.1.1 after it had updated itself to 10.2.0).
//  Apple's own apps update with macOS and are left out. Nothing is
//  downloaded but version information; nothing is installed.
//

import Foundation

/// Update checks for the installed apps.
public enum AppUpdates {

    /// Homebrew's public cask catalogue.
    static let catalogueURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    /// How long a downloaded catalogue is used before it is fetched again.
    static let catalogueLifetime: TimeInterval = 86_400

    /// Every non-Apple app under `folders`, checked; available updates first.
    ///
    /// - Parameters:
    ///   - folders: Where to look, two levels deep.
    ///   - fetcher: The network.
    ///   - cache: Where Homebrew's catalogue is kept between runs (it is about
    ///     19 MB); nil fetches it every time.
    ///   - caskroom: Homebrew's Caskroom, to say `brew upgrade` for its apps.
    public static func check(_ folders: [URL], fetcher: any UpdateFetching = WebFetcher(),
                             cache: URL? = defaultCache(), caskroom: String = "/opt/homebrew/Caskroom") async -> [AppUpdate] {
        let apps = installed(folders)
        let needsCatalogue = apps.contains { $0.receipt == false && $0.feed == nil }
        let casks = needsCatalogue ? await catalogue(fetcher: fetcher, cache: cache) : nil
        var results: [AppUpdate] = []
        // A few at a time: feeds are slow, and nobody wants 40 requests at once.
        for batch in stride(from: 0, to: apps.count, by: 8).map({ Array(apps[$0..<min($0 + 8, apps.count)]) }) {
            await withTaskGroup(of: AppUpdate.self) { group in
                for app in batch {
                    group.addTask { await check(app, fetcher: fetcher, casks: casks, caskroom: caskroom) }
                }
                for await result in group { results.append(result) }
            }
        }
        let order: [UpdateStatus: Int] = [.available: 0, .unknown: 1, .current: 2]
        return results.sorted { (order[$0.status]!, $0.name.lowercased()) < (order[$1.status]!, $1.name.lowercased()) }
    }

    /// Where the catalogue is cached by default.
    public static func defaultCache(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Caches/arraypress/diskmaid/cask.json")
    }

    // MARK: - One app

    /// An installed app as the check needs it.
    struct Installed: Sendable {
        let name: String
        let bundleID: String
        let path: String
        let version: String?
        let build: String?
        let feed: URL?
        let receipt: Bool
    }

    /// The non-Apple apps under `folders`, links followed, each once.
    static func installed(_ folders: [URL]) -> [Installed] {
        var seen: Set<String> = []
        var found: [Installed] = []
        for folder in folders {
            for path in AppIndex.bundles(in: folder.path, depth: 2) {
                let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                guard seen.insert(real).inserted, let data = PathProbe.read(real + "/Contents/Info.plist"),
                      let plist = PlistValues.dictionary(data), let id = plist["CFBundleIdentifier"] as? String,
                      !id.lowercased().hasPrefix("com.apple.") else { continue }
                let name = StackRules.cleanName((plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
                                                ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                found.append(Installed(name: name, bundleID: id, path: path,
                                       version: plist["CFBundleShortVersionString"] as? String,
                                       build: plist["CFBundleVersion"] as? String,
                                       feed: (plist["SUFeedURL"] as? String).flatMap(URL.init(string:)),
                                       receipt: PathProbe.exists(real + "/Contents/_MASReceipt/receipt")))
            }
        }
        return found
    }

    /// One app, from the source that knows it best.
    static func check(_ app: Installed, fetcher: any UpdateFetching, casks: [String: UpdateCatalogues.Cask]?,
                      caskroom: String) async -> AppUpdate {
        func result(_ latest: (version: String?, build: String?), _ source: UpdateSource, detail: String) -> AppUpdate {
            let status = UpdateRules.status(installed: (app.version, app.build), latest: latest)
            return AppUpdate(name: app.name, bundleID: app.bundleID, path: app.path, installed: app.version,
                             latest: latest.version ?? latest.build, source: source, status: status, detail: detail)
        }
        func unknown(_ source: UpdateSource, _ why: String) -> AppUpdate {
            AppUpdate(name: app.name, bundleID: app.bundleID, path: app.path, installed: app.version, latest: nil,
                      source: source, status: .unknown, detail: why)
        }
        if app.receipt {
            var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
            lookup.queryItems = [URLQueryItem(name: "bundleId", value: app.bundleID), URLQueryItem(name: "entity", value: "macSoftware")]
            guard let data = try? await fetcher.data(from: lookup.url!), let version = UpdateCatalogues.appStoreVersion(data) else {
                return unknown(.appStore, "the App Store did not answer for it")
            }
            return result((version, nil), .appStore, detail: UpdateRules.how(.appStore, cask: nil, viaHomebrew: false))
        }
        if let feed = app.feed {
            guard let data = try? await fetcher.data(from: feed), let release = AppcastParsing.newest(data) else {
                return unknown(.sparkle, "its update feed did not answer, or held no release")
            }
            return result((release.shortVersion, release.build), .sparkle, detail: UpdateRules.how(.sparkle, cask: nil, viaHomebrew: false))
        }
        let bundleName = (app.path as NSString).lastPathComponent.lowercased()
        guard let casks else { return unknown(.homebrew, "Homebrew's catalogue could not be fetched") }
        guard let cask = casks[bundleName] ?? casks["id:" + app.bundleID.lowercased()] else {
            return unknown(.none, UpdateRules.how(.none, cask: nil, viaHomebrew: false))
        }
        let viaHomebrew = PathProbe.isDirectory(caskroom + "/" + cask.token)
        return result((cask.version, nil), .homebrew, detail: UpdateRules.how(.homebrew, cask: cask.token, viaHomebrew: viaHomebrew))
    }

    // MARK: - The catalogue

    /// Homebrew's casks by app name: the cached copy while it is a day old
    /// or less, else fetched (and cached); a stale copy beats none.
    static func catalogue(fetcher: any UpdateFetching, cache: URL?, now: Date = Date()) async -> [String: UpdateCatalogues.Cask]? {
        if let cache, let modified = PathProbe.modified(cache.path), now.timeIntervalSince(modified) < catalogueLifetime,
           let data = try? Data(contentsOf: cache) {
            return UpdateCatalogues.casks(data)
        }
        if let data = try? await fetcher.data(from: catalogueURL) {
            if let cache {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cache, options: .atomic)
            }
            return UpdateCatalogues.casks(data)
        }
        return cache.flatMap { try? Data(contentsOf: $0) }.map(UpdateCatalogues.casks)
    }
}
