//
//  CatalogueTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import DiskCleanup

struct CatalogueTests {

    @Test func builtInCatalogueLoadsAndIsSound() throws {
        let catalogue = try Catalogue.builtIn()
        #expect(catalogue.rules.count > 60)
        #expect(catalogue.problems.isEmpty, "\(catalogue.problems)")
    }

    @Test func everyRuleIDIsUniqueKebabCase() throws {
        let ids = try Catalogue.builtIn().rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids { #expect(id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil, "\(id)") }
    }

    @Test func everyCategoryHasARule() throws {
        let used = Set(try Catalogue.builtIn().rules.map(\.category))
        #expect(used == Set(CleanupCategory.allCases))
    }

    @Test func noRemovableRuleReachesAProtectedPath() throws {
        let catalogue = try Catalogue.builtIn()
        let home = "/Users/example"
        for rule in catalogue.rules where rule.tier != .report && rule.detector != .marker {
            for place in rule.paths + rule.globs {
                let expanded = PathText.expand(place, home: home)
                for entry in catalogue.protect {
                    let protected = PathText.expand(entry, home: home)
                    let (base, rest) = Glob.split(expanded)
                    #expect(!(rest.isEmpty ? PathText.overlaps(expanded, protected) : PathText.isWithin(base, protected)),
                            "\(rule.id) reaches \(entry)")
                }
                for system in PathSafety.systemPaths {
                    #expect(!PathText.isWithin(expanded, system), "\(rule.id) reaches \(system)")
                }
            }
        }
    }

    @Test func userMadeThingsGoToTheTrash() throws {
        // A root-owned library is never removed by diskmaid at all: it only prints the command.
        for rule in try Catalogue.builtIn().rules where !rule.regenerable && rule.tier != .report {
            #expect([.trash, .sudo].contains(rule.removal), "\(rule.id)")
        }
        // Installers and leftovers are the two user-made categories.
        let catalogue = try Catalogue.builtIn()
        for rule in catalogue.rules where [.installers, .leftovers].contains(rule.category) {
            #expect([.trash, .sudo].contains(rule.removal), "\(rule.id)")
        }
        #expect(catalogue.rules.filter { $0.removal == .sudo }.allSatisfy { $0.tier == .review && $0.paths.allSatisfy { $0.hasPrefix("/Library/") } })
    }

    @Test func broadSweepsComeAfterEverySpecificRule() throws {
        let rules = try Catalogue.builtIn().rules
        let sweep = try #require(rules.firstIndex { $0.id == "user-caches" })
        for (index, rule) in rules.enumerated() where index > sweep {
            #expect(rule.category == .userCaches || rule.category == .reportOnly, "\(rule.id) comes after the sweep")
        }
        // Leftovers judge caches before the sweep counts them as plain caches.
        let leftovers = try #require(rules.firstIndex { $0.id == "leftover-caches" })
        #expect(leftovers < sweep)
    }

    @Test func unknownKeysAreRefused() {
        let json = #"{"version":1,"protect":[],"protectNames":[],"rules":[{"id":"x","category":"xcode","paths":["~/x"],"regenerable":true,"tier":"safe","removal":"delete","minAgeDay":3}]}"#
        #expect(throws: DiskCleanupError.self) { try Catalogue.decode(Data(json.utf8)) }
        let topLevel = #"{"version":1,"protect":[],"protectNames":[],"rules":[],"extra":true}"#
        #expect(throws: DiskCleanupError.self) { try Catalogue.decode(Data(topLevel.utf8)) }
    }

    @Test func badValuesAreRefused() {
        let category = #"{"version":1,"protect":[],"protectNames":[],"rules":[{"id":"x","category":"nonsense","paths":["~/x"],"regenerable":true,"tier":"safe","removal":"delete"}]}"#
        #expect(throws: DiskCleanupError.self) { try Catalogue.decode(Data(category.utf8)) }
        let removal = #"{"version":1,"protect":[],"protectNames":[],"rules":[{"id":"x","category":"xcode","paths":["~/x"],"regenerable":true,"tier":"safe","removal":"shred"}]}"#
        #expect(throws: DiskCleanupError.self) { try Catalogue.decode(Data(removal.utf8)) }
        let empty = #"{"version":1,"protect":[],"protectNames":[],"rules":[{"id":"x","category":"xcode","paths":["~/x"],"regenerable":true,"tier":"safe","removal":[]}]}"#
        #expect(throws: DiskCleanupError.self) { try Catalogue.decode(Data(empty.utf8)) }
    }

    @Test func aRuleAimedAtSomethingProtectedIsRefused() throws {
        let base = try Catalogue.builtIn()
        let cases: [Rule] = [
            Rule(id: "ssh-keys", category: .userCaches, paths: ["~/.ssh"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "temp", category: .userCaches, globs: ["/private/var/folders/*"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "groups", category: .leftovers, globs: ["~/Library/Group Containers/*"], regenerable: false, tier: .review, removal: .trash),
            Rule(id: "library", category: .userCaches, paths: ["~/Library"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "keychain-cache", category: .userCaches, paths: ["~/Library/Caches/com.agilebits.onepassword"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "Bad_ID", category: .userCaches, paths: ["~/x"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "user-stuff", category: .leftovers, paths: ["~/x"], regenerable: false, tier: .review, removal: .delete),
            Rule(id: "relative", category: .userCaches, paths: ["Library/x"], regenerable: true, tier: .safe, removal: .delete),
        ]
        for rule in cases {
            let catalogue = Catalogue(version: 1, protect: base.protect, protectNames: base.protectNames, rules: [rule])
            #expect(!catalogue.problems.isEmpty, "\(rule.id) should be refused")
        }
        let duplicate = Catalogue(version: 1, protect: [], protectNames: [], rules: [
            Rule(id: "a", category: .xcode, paths: ["~/a"], regenerable: true, tier: .safe, removal: .delete),
            Rule(id: "a", category: .xcode, paths: ["~/b"], regenerable: true, tier: .safe, removal: .delete),
        ])
        #expect(!duplicate.problems.isEmpty)
    }

    @Test func catalogueRoundTripsThroughJSON() throws {
        let catalogue = try Catalogue.builtIn()
        let data = try JSONEncoder().encode(catalogue)
        #expect(try Catalogue.decode(data) == catalogue)
    }
}
