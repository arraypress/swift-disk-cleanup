//
//  WhereTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The `where` tree on a fixture home: every folder the size Sizer gives it
//  alone, clones once, refused folders not visible, labels from the
//  catalogue, small ones folded, depth kept.
//

import Darwin
import Foundation
import Testing
@testable import DiskCleanup

struct WhereTests {

    func find(_ node: WhereNode, _ path: String) -> WhereNode? {
        if node.path == path { return node }
        for child in node.children { if let found = find(child, path) { return found } }
        return nil
    }

    func deepest(_ node: WhereNode, below root: String) -> Int {
        let depth = PathText.components(node.path).count - PathText.components(root).count
        return node.children.map { deepest($0, below: root) }.max() ?? depth
    }

    @Test func eachFolderIsTheSizeSizerGivesItAlone() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file("Big/one.bin", bytes: 3_000_000)
        try fixture.file("Big/inner/two.bin", bytes: 500_000)
        try fixture.file("Big/clones/original", bytes: 1_000_000)
        for index in 0..<5 {
            #expect(clonefile(fixture.path("Big/clones/original"), fixture.path("Big/clones/copy-\(index)"), 0) == 0)
        }
        let tree = TreeSizer.tree(fixture.path("Big"), depth: 2)
        for relative in ["Big", "Big/inner", "Big/clones"] {
            let node = try #require(find(tree, fixture.path(relative)), "\(relative)")
            #expect(node.bytes == Sizer.measure(fixture.path(relative)).bytes, "\(relative)")
        }
        let clones = try #require(find(tree, fixture.path("Big/clones")))
        #expect((clones.bytes ?? 0) < 1_200_000 && (clones.apparentBytes ?? 0) >= 6_000_000, "\(clones)")
    }

    @Test func aRefusedFolderIsNotVisibleNeverZero() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file("Big/open/a.bin", bytes: 100_000)
        try fixture.file("Big/open/locked/b.bin", bytes: 100_000)
        _ = CommandRunner.run("/bin/chmod", ["000", fixture.path("Big/open/locked")], timeout: 10)
        let tree = TreeSizer.tree(fixture.path("Big"), depth: 3)
        let locked = try #require(find(tree, fixture.path("Big/open/locked")))
        #expect(locked.visibility == .notVisible && locked.bytes == nil)
        #expect(find(tree, fixture.path("Big/open"))?.visibility == .partial)
        #expect(tree.visibility == .partial)
        // A refused folder, and the small one holding it, stay in sight whatever the size floor.
        let labels = Where.Labels(items: [], catalogue: try Catalogue.builtIn(), home: fixture.home.path)
        let shown = Where.finish(tree, labels: labels, minBytes: 1_000_000_000)
        #expect(shown.children.map(\.path) == [fixture.path("Big/open")])
        #expect(find(shown, fixture.path("Big/open/locked"))?.visibility == .notVisible)
    }

    @Test func placesCarryTheCataloguesWord() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try fixture.file("Library/Keychains/login.keychain-db", bytes: 4_000)
        let tree = Where.tree(fixture.home.path, depth: 4, minBytes: 0, catalogue: try Catalogue.builtIn(), context: fixture.context())
        let build = try #require(find(tree, fixture.path("Developer/swift-old/.build")))
        #expect(build.label == PlaceLabel(rule: "build-swift", category: "build-folders", tier: "safe", owner: build.label?.owner, inside: false))
        #expect(find(tree, fixture.path("Developer/swift-old/.build/debug"))?.label?.inside == true)
        #expect(find(tree, fixture.path("Library/Keychains"))?.label?.rule == "protected")
        // Holding a protected place is not being one.
        #expect(find(tree, fixture.path("Library"))?.label == nil)
        #expect(deepest(tree, below: fixture.home.path) <= 4)
    }

    @Test func smallFoldersFoldAndTheBiggestComeFirst() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        // Named so that A to Z and biggest-first disagree.
        try fixture.file("Big/alpha/a.bin", bytes: 2_000_000)
        try fixture.file("Big/zulu/a.bin", bytes: 3_000_000)
        try fixture.file("Big/tiny/a.bin", bytes: 10_000)
        try fixture.file("Big/wee/a.bin", bytes: 20_000)
        let tree = Where.tree(fixture.path("Big"), depth: 1, minBytes: 1_000_000, catalogue: try Catalogue.builtIn(), context: fixture.context())
        #expect(tree.children.map(\.path) == [fixture.path("Big/zulu"), fixture.path("Big/alpha")])
        #expect(tree.smallerCount == 2 && tree.smallerBytes >= 30_000)
        #expect(tree.children.allSatisfy { $0.children.isEmpty })
    }
}
