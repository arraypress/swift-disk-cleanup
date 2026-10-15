//
//  StrictKeys.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  JSON decoding that refuses keys it does not know. A rule with
//  `"minAgeDay": 30` decoded leniently is a rule with no age gate.
//

import Foundation

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

enum StrictKeys {

    /// Throws when the object being decoded has a key outside `allowed`.
    static func check(_ decoder: any Decoder, allowed: [String], in what: String) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "unknown key\(unknown.count == 1 ? "" : "s") in \(what): \(unknown.joined(separator: ", "))"
            ))
        }
    }
}
