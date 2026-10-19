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
            case "sudo": self = .sudo
            case "dock": self = .dock
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "removal must be trash, delete, sudo or a command array, not \(word)")
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
        case .sudo: try container.encode("sudo")
        case .dock: try container.encode("dock")
        }
    }
}

public extension Removal {
    /// `trash`, `delete`, `sudo rm -rf`, or the command as typed.
    var display: String {
        switch self {
        case .trash: "trash"
        case .delete: "delete"
        case .command(let arguments): CommandTemplate.display(arguments)
        case .sudo: "sudo rm -rf"
        case .dock: "dock"
        }
    }

    /// What a person runs to remove `path` themselves, for `.sudo`; `nil`
    /// for everything diskmaid removes on its own.
    func byHand(_ path: String) -> String? {
        guard self == .sudo else { return nil }
        return "sudo rm -rf " + PathText.shellQuoted(path)
    }
}
