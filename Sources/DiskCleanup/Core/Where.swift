//
//  Where.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Where the space went: a biggest-first tree, clone-aware, each place
//  labelled with what the catalogue says of it — the rule or category that
//  owns it, its tier, its app — or "protected" when no rule may reach it.
//  The labels come from a scan that only looks, never measures (installers
//  are left out: judging one means attaching a disk image).
//

import Foundation
import os

public enum Where {

    /// `path` sized `depth` levels down, labelled, children under `minBytes`
    /// folded into a count. A folder macOS refuses, or one holding such a
    /// folder, is always shown, so "not visible" is never folded away.
    public static func tree(_ path: String, depth: Int, minBytes: Int64, catalogue: Catalogue, context: CleanupContext,
                            progress: ((Int, Int) -> Void)? = nil) -> WhereNode {
        // The labels' scan and the walk share nothing, so they run side by side.
        let categories = Set(CleanupCategory.allCases).subtracting([.installers])
        let labelled = OSAllocatedUnfairLock<[Item]>(initialState: [])
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            let report = Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: categories, measure: false))
            labelled.withLock { $0 = report.items }
        }
        let tree = TreeSizer.tree(path, depth: max(depth, 1), progress: progress)
        group.wait()
        return finish(tree, labels: Labels(items: labelled.withLock { $0 }, catalogue: catalogue, home: context.home.path), minBytes: minBytes)
    }

    /// The catalogue's word on a place.
    struct Labels {
        let items: [Item]
        let catalogue: Catalogue
        let home: String

        init(items: [Item], catalogue: Catalogue, home: String) {
            self.items = items.filter { $0.path.hasPrefix("/") }
            self.catalogue = catalogue
            self.home = home
        }

        func label(_ path: String) -> PlaceLabel? {
            if let item = items.first(where: { $0.path == path }) {
                return PlaceLabel(rule: item.rule, category: item.category.rawValue, tier: item.tier.rawValue, owner: item.owner, inside: false)
            }
            if let item = items.filter({ PathText.isWithin(path, $0.path) }).max(by: { $0.path.count < $1.path.count }) {
                return PlaceLabel(rule: item.rule, category: item.category.rawValue, tier: item.tier.rawValue, owner: item.owner, inside: true)
            }
            if isProtected(path) {
                return PlaceLabel(rule: "protected", category: nil, tier: nil, owner: nil, inside: false)
            }
            return nil
        }

        /// A place inside a protected one, or named like a secret. Holding a
        /// protected place (~/Library holds the Keychains) is not being one.
        func isProtected(_ path: String) -> Bool {
            if catalogue.protect.contains(where: { PathText.isWithin(path, PathText.expand($0, home: home)) }) { return true }
            let name = PathText.lastComponent(path).lowercased()
            return catalogue.protectNames.contains { name.contains($0.lowercased()) }
        }
    }

    static func finish(_ node: WhereNode, labels: Labels, minBytes: Int64) -> WhereNode {
        var node = node
        node.label = labels.label(node.path)
        var shown: [WhereNode] = []
        for child in node.children {
            if child.visibility != .visible || (child.bytes ?? 0) >= minBytes {
                shown.append(finish(child, labels: labels, minBytes: minBytes))
            } else {
                node.smallerCount += 1
                node.smallerBytes += child.bytes ?? 0
            }
        }
        node.children = shown.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
        return node
    }
}
