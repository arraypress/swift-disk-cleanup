//
//  ModelStoreNames.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum ModelStoreNames {

    /// A Hugging Face hub folder (`models--org--name`) as its kind and repo id.
    static func huggingFace(_ folder: String) -> (kind: String, repo: String)? {
        let parts = folder.components(separatedBy: "--")
        guard parts.count >= 2, ["models", "datasets", "spaces"].contains(parts[0]) else { return nil }
        return (String(parts[0].dropLast()), parts.dropFirst().joined(separator: "/"))
    }

    /// The bytes an Ollama manifest's layers and config add up to.
    static func ollamaBytes(_ data: Data) -> Int64? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var total: Int64 = 0
        if let config = root["config"] as? [String: Any], let size = (config["size"] as? NSNumber)?.int64Value {
            total += size
        }
        for layer in root["layers"] as? [[String: Any]] ?? [] {
            total += (layer["size"] as? NSNumber)?.int64Value ?? 0
        }
        return total
    }

    /// An Ollama manifest path's model name: `…/manifests/registry.ollama.ai/library/llama3/8b` → `llama3:8b`.
    static func ollamaModel(_ path: String, manifests: String) -> String? {
        let relative = PathText.components(String(path.dropFirst(PathText.normalised(manifests).count)))
        guard relative.count >= 3 else { return nil }
        let tag = relative[relative.count - 1], model = relative[relative.count - 2]
        let namespace = relative[relative.count - 3]
        return namespace == "library" ? "\(model):\(tag)" : "\(namespace)/\(model):\(tag)"
    }

    /// The version in an Xcode `.xip` name: `Xcode_16.2.xip` → `16.2`.
    static func xcodeVersion(_ name: String) -> String? {
        name.firstMatch(of: /(?i)xcode[_ -]?(\d+(?:\.\d+)*)/).map { String($0.1) }
    }
}
