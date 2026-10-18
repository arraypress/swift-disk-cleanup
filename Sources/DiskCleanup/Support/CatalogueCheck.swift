//
//  CatalogueCheck.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The rules the rules must keep. Run by the tests on every build and by
//  `Catalogue.builtIn()` on every load: a catalogue that breaks one is
//  refused, never half-used.
//

import Foundation

enum CatalogueCheck {

    /// Detectors that find their own places and need no paths.
    static let pathless: Set<Detector> = [.installers, .simulatorDevices, .simulatorRuntimes, .snapshots]

    /// Every problem with the catalogue; empty when it is sound.
    static func problems(_ catalogue: Catalogue, home: String = "/Users/example") -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for rule in catalogue.rules {
            let label = "rule \(rule.id)"
            if rule.id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) == nil { problems.append("\(label): id is not kebab-case") }
            if !seen.insert(rule.id).inserted { problems.append("\(label): duplicate id") }
            let places = rule.paths + rule.globs
            if places.isEmpty && !pathless.contains(rule.detector) { problems.append("\(label): no paths or globs") }
            if rule.detector == .marker {
                if rule.marker.isEmpty { problems.append("\(label): a marker rule needs marker files") }
                if !rule.globs.isEmpty { problems.append("\(label): a marker rule names folders in paths, not globs") }
                if rule.paths.contains(where: { $0.contains("/") }) { problems.append("\(label): marker paths are folder names") }
            } else {
                if !rule.marker.isEmpty { problems.append("\(label): marker without the marker detector") }
                for place in places where !(place.hasPrefix("~/") || place.hasPrefix("/")) {
                    problems.append("\(label): \(place) is not absolute or ~/")
                }
            }
            if rule.keepNewest != nil && rule.detector != .deviceSupport { problems.append("\(label): keepNewest is for device support") }
            if (rule.detector == .appLibraries) == rule.apps.isEmpty { problems.append("\(label): apps go with, and only with, the app-libraries detector") }
            if case .command(let arguments) = rule.removal {
                if arguments.isEmpty { problems.append("\(label): empty command") }
                if let first = arguments.first, first.contains("/") { problems.append("\(label): command names a path, not a tool") }
            }
            if let days = rule.minAgeDays, days < 0 { problems.append("\(label): negative minAgeDays") }
            guard rule.tier != .report else { continue }
            // Removable from here on.
            if !rule.regenerable && rule.removal == .delete {
                problems.append("\(label): user data must go to the Trash, not be deleted")
            }
            guard rule.detector != .marker else { continue }
            for place in places {
                let expanded = PathText.expand(place, home: home)
                let (base, rest) = Glob.split(expanded)
                if let reason = PathSafety.reason(for: rest.isEmpty ? expanded : base + "/x", catalogue: catalogue, home: home) {
                    problems.append("\(label): \(place) reaches \(reason)")
                }
                for entry in catalogue.protect {
                    let protected = PathText.expand(entry, home: home)
                    if rest.isEmpty {
                        if PathText.overlaps(expanded, protected) { problems.append("\(label): \(place) overlaps protected \(entry)") }
                        continue
                    }
                    // A pattern inside a protected place, or one that matches a
                    // protected place (or a folder holding one).
                    let depth = PathText.components(expanded).count
                    let parts = PathText.components(protected)
                    if PathText.isWithin(base, protected)
                        || (parts.count >= depth && Glob.matchesPath(expanded, "/" + parts.prefix(depth).joined(separator: "/"))) {
                        problems.append("\(label): \(place) matches protected \(entry)")
                    }
                }
            }
        }
        return problems
    }
}
