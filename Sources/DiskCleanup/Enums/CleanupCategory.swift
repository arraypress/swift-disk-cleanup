//
//  CleanupCategory.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A family of things a Mac accumulates. Every rule belongs to one.
public enum CleanupCategory: String, Codable, CaseIterable, Sendable {
    /// Disk images, packages and zipped apps whose app is already installed.
    case installers
    /// DerivedData, archives, device support and simulators.
    case xcode
    /// `.build`, `node_modules`, `target` and friends, beside their marker file.
    case buildFolders = "build-folders"
    /// Homebrew, uv, npm, pnpm and the other package managers' caches.
    case packageCaches = "package-caches"
    /// Hugging Face, Core AI's compiled models, Ollama, LM Studio, fleet models.
    case mlCaches = "ml-caches"
    /// Data left behind by apps that are no longer installed.
    case leftovers
    /// `~/Library/Caches` and `~/Library/Logs`.
    case userCaches = "user-caches"
    /// Trash, snapshots, backups, mail and chat stores: shown, never cleaned.
    case reportOnly = "report-only"
}
