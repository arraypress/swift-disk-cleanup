//
//  Rule+Codable.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension Rule: Codable {

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, category, paths, globs, marker, detector, owner, regenerable, tier, removal
        case minAgeDays, protect, keepNewest, apps, note
    }

    public init(from decoder: any Decoder) throws {
        try StrictKeys.check(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "a rule")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            category: try c.decode(CleanupCategory.self, forKey: .category),
            paths: try c.decodeIfPresent([String].self, forKey: .paths) ?? [],
            globs: try c.decodeIfPresent([String].self, forKey: .globs) ?? [],
            marker: try c.decodeIfPresent([String].self, forKey: .marker) ?? [],
            detector: try c.decodeIfPresent(Detector.self, forKey: .detector) ?? .paths,
            owner: try c.decodeIfPresent(String.self, forKey: .owner),
            regenerable: try c.decode(Bool.self, forKey: .regenerable),
            tier: try c.decode(Tier.self, forKey: .tier),
            removal: try c.decode(Removal.self, forKey: .removal),
            minAgeDays: try c.decodeIfPresent(Int.self, forKey: .minAgeDays),
            protect: try c.decodeIfPresent([String].self, forKey: .protect) ?? [],
            keepNewest: try c.decodeIfPresent(Int.self, forKey: .keepNewest),
            apps: try c.decodeIfPresent([String].self, forKey: .apps) ?? [],
            note: try c.decodeIfPresent(String.self, forKey: .note)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        if !paths.isEmpty { try c.encode(paths, forKey: .paths) }
        if !globs.isEmpty { try c.encode(globs, forKey: .globs) }
        if !marker.isEmpty { try c.encode(marker, forKey: .marker) }
        if detector != .paths { try c.encode(detector, forKey: .detector) }
        try c.encodeIfPresent(owner, forKey: .owner)
        try c.encode(regenerable, forKey: .regenerable)
        try c.encode(tier, forKey: .tier)
        try c.encode(removal, forKey: .removal)
        try c.encodeIfPresent(minAgeDays, forKey: .minAgeDays)
        if !protect.isEmpty { try c.encode(protect, forKey: .protect) }
        try c.encodeIfPresent(keepNewest, forKey: .keepNewest)
        if !apps.isEmpty { try c.encode(apps, forKey: .apps) }
        try c.encodeIfPresent(note, forKey: .note)
    }
}
