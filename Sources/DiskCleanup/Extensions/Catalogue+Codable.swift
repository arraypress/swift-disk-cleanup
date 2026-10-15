//
//  Catalogue+Codable.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension Catalogue: Codable {

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, protect, protectNames, rules
    }

    public init(from decoder: any Decoder) throws {
        try StrictKeys.check(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "the catalogue")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            protect: try c.decode([String].self, forKey: .protect),
            protectNames: try c.decode([String].self, forKey: .protectNames),
            rules: try c.decode([Rule].self, forKey: .rules)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(protect, forKey: .protect)
        try c.encode(protectNames, forKey: .protectNames)
        try c.encode(rules, forKey: .rules)
    }
}
