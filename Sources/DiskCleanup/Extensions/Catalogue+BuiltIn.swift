//
//  Catalogue+BuiltIn.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Catalogue {

    /// The catalogue compiled into this library, read strictly and checked.
    static func builtIn() throws(DiskCleanupError) -> Catalogue {
        try decode(Data(CatalogueData.json.utf8))
    }

    /// Reads a catalogue: unknown keys, bad values and broken rules all refuse.
    static func decode(_ data: Data) throws(DiskCleanupError) -> Catalogue {
        let catalogue: Catalogue
        do {
            catalogue = try JSONDecoder().decode(Catalogue.self, from: data)
        } catch {
            throw .invalidCatalogue(String(describing: error))
        }
        let problems = CatalogueCheck.problems(catalogue)
        guard problems.isEmpty else { throw .invalidCatalogue(problems.joined(separator: "; ")) }
        return catalogue
    }

    /// Every problem with this catalogue; empty when it is sound.
    var problems: [String] { CatalogueCheck.problems(self) }

    /// The rule called `id`.
    func rule(_ id: String) -> Rule? { rules.first { $0.id == id } }

    /// The rule an item id belongs to.
    func rule(forItem id: String) -> Rule? { ItemID.rule(of: id).flatMap { rule($0) } }
}
