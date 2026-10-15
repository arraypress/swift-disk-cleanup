//
//  InstallerVerdict.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What an installer turned out to be. Only `dead` is ever cleaned.
public enum InstallerVerdict: String, Codable, CaseIterable, Sendable {
    /// The same or a newer version is installed.
    case dead
    /// The installer is newer than what is installed: a pending update, kept.
    case pendingUpdate = "pending-update"
    /// Nothing answered for this app. Never read as "not installed".
    case unknown
    /// An encrypted image: opening it would prompt, so it is not opened.
    case encrypted
    /// An image with a licence agreement: attaching it would prompt.
    case licenceAgreement = "licence-agreement"
    /// It could not be read (damaged, no app inside, a tool failed).
    case unreadable
}
