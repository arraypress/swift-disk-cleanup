//
//  WebFetcher.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The real network, with a timeout: a feed that does not answer in time is
/// an unknown, not a hang.
public struct WebFetcher: UpdateFetching {
    /// Seconds before a request gives up.
    public var timeout: TimeInterval

    /// A fetcher.
    ///
    /// - Parameter timeout: Seconds before a request gives up.
    public init(timeout: TimeInterval = 20) { self.timeout = timeout }

    /// The body at a URL.
    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("diskmaid (update check)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
