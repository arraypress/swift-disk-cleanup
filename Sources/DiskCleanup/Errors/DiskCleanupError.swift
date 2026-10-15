//
//  DiskCleanupError.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why something in this library refused or failed.
public enum DiskCleanupError: Error, Equatable, Sendable {
    /// The catalogue JSON is malformed or breaks a rule of its own.
    case invalidCatalogue(String)
    /// A name is neither a category nor an item id.
    case unknownTarget(String)
    /// An id has the right shape but no such item was found this run.
    case itemNotFound(String)
    /// A place that was asked about could not be read: Full Disk Access.
    case needsFullDiskAccess([String])
    /// No journal entry or batch by that id.
    case journalEntryNotFound(String)
    /// The journal could not be read or written.
    case journal(String)
    /// A folder argument does not exist.
    case noSuchFolder(String)
}

extension DiskCleanupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCatalogue(let reason): "the rule catalogue is invalid: \(reason)"
        case .unknownTarget(let name): "\(name) is neither a category nor an item id"
        case .itemNotFound(let id): "no item \(id) was found on this run"
        case .needsFullDiskAccess(let paths): "not visible without Full Disk Access: \(paths.joined(separator: ", "))"
        case .journalEntryNotFound(let id): "nothing in the undo journal is called \(id)"
        case .journal(let reason): "the undo journal: \(reason)"
        case .noSuchFolder(let path): "no such folder: \(path)"
        }
    }
}
