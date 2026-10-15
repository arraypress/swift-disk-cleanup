//
//  CacheDirTag.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  https://bford.info/cachedir/ — a folder that says it is a cache, by a
//  file whose first line is this exact signature.
//

import Foundation

enum CacheDirTag {

    static let signature = "Signature: 8a477f597d28d172789f06886806bc55"

    static func isValid(_ data: Data) -> Bool {
        data.prefix(signature.utf8.count) == Data(signature.utf8)
    }
}
