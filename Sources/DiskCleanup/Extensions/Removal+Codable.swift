//
//  Removal+Codable.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension Removal: Codable {

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let word = try? container.decode(String.self) {
            switch word {
            case "trash": self = .trash
            case "delete": self = .delete
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "removal must be trash, delete or a command array, not \(word)")
            }
        } else {
            let arguments = try container.decode([String].self)
            guard !arguments.isEmpty else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "a removal command cannot be empty")
            }
            self = .command(arguments)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .trash: try container.encode("trash")
        case .delete: try container.encode("delete")
        case .command(let arguments): try container.encode(arguments)
        }
    }
}

public extension Removal {
    /// `trash`, `delete`, or the command as typed.
    var display: String {
        switch self {
        case .trash: "trash"
        case .delete: "delete"
        case .command(let arguments): CommandTemplate.display(arguments)
        }
    }
}
