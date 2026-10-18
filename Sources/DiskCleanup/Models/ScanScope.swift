//
//  ScanScope.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a scan covers.
public struct ScanScope: Sendable {
    /// The categories to look at; empty means all.
    public var categories: Set<CleanupCategory>
    /// Folders to look for build output in; `nil` uses the context's project roots.
    public var projectRoots: [URL]?
    /// Folders to look for installers in; `nil` uses the context's.
    public var installerFolders: [URL]?
    /// How many folders deep to look for marker files.
    public var depth: Int
    /// Lift the recency guard on things that rebuild themselves.
    public var includeRecent: Bool
    /// Worker threads for measuring.
    public var parallelism: Int
    /// Walk what is found to size it; off, items carry only what their
    /// detector knew — for labelling places, where sizes come from elsewhere.
    public var measure: Bool

    public init(categories: Set<CleanupCategory> = [], projectRoots: [URL]? = nil, installerFolders: [URL]? = nil,
                depth: Int = 6, includeRecent: Bool = false, parallelism: Int = 6, measure: Bool = true) {
        self.categories = categories
        self.projectRoots = projectRoots
        self.installerFolders = installerFolders
        self.depth = depth
        self.includeRecent = includeRecent
        self.parallelism = parallelism
        self.measure = measure
    }
}
