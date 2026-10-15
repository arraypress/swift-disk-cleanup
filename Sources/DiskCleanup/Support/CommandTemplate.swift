//
//  CommandTemplate.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum CommandTemplate {

    /// Fills `{name}` placeholders from an item's evidence. `nil` when one has
    /// no value — a command with a hole in it never runs.
    static func fill(_ arguments: [String], from evidence: [String: String]) -> [String]? {
        var filled: [String] = []
        for argument in arguments {
            var result = argument
            for match in argument.matches(of: /\{([a-zA-Z]+)\}/) {
                guard let value = evidence[String(match.1)], !value.isEmpty else { return nil }
                result = result.replacingOccurrences(of: String(match.0), with: value)
            }
            filled.append(result)
        }
        return filled
    }

    /// A command as a person would type it.
    static func display(_ arguments: [String]) -> String {
        arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }
}
