//
//  SimctlJSON.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

enum SimctlJSON {

    /// `xcrun simctl list devices -j`.
    static func devices(_ data: Data) -> [SimulatorDevice]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return nil }
        var devices: [SimulatorDevice] = []
        for (runtime, list) in byRuntime.sorted(by: { $0.key < $1.key }) {
            for device in list {
                guard let udid = device["udid"] as? String, isUDID(udid) else { continue }
                let dataPath = device["dataPath"] as? String
                devices.append(SimulatorDevice(
                    udid: udid,
                    name: device["name"] as? String ?? udid,
                    runtime: runtime,
                    state: device["state"] as? String,
                    isAvailable: device["isAvailable"] as? Bool ?? true,
                    folder: dataPath.map(PathText.parent)
                ))
            }
        }
        return devices
    }

    /// `xcrun simctl runtime list -j`.
    static func runtimes(_ data: Data) -> [SimulatorRuntime]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return nil }
        return root.values.compactMap { entry in
            guard let identifier = entry["identifier"] as? String, isUDID(identifier),
                  let runtime = entry["runtimeIdentifier"] as? String else { return nil }
            return SimulatorRuntime(
                identifier: identifier,
                runtimeIdentifier: runtime,
                version: entry["version"] as? String,
                build: entry["build"] as? String,
                bytes: (entry["sizeBytes"] as? NSNumber)?.int64Value,
                deletable: entry["deletable"] as? Bool ?? false,
                state: entry["state"] as? String
            )
        }
        .sorted { ($0.runtimeIdentifier, $0.build ?? "") < ($1.runtimeIdentifier, $1.build ?? "") }
    }

    /// Runtime images that share their runtime with another image. Which of
    /// two is "newer" cannot be read from the build (a beta seed's `24A5390f`
    /// sorts after the release's `24A434`), so neither is chosen for the
    /// person: both are offered for review.
    static func shared(_ runtimes: [SimulatorRuntime]) -> Set<String> {
        var shared = Set<String>()
        for (_, group) in Dictionary(grouping: runtimes, by: \.runtimeIdentifier) where group.count > 1 {
            shared.formUnion(group.map(\.identifier))
        }
        return shared
    }

    /// An argument that is safe to hand to simctl: a UUID and nothing else.
    static func isUDID(_ text: String) -> Bool {
        text.wholeMatch(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) != nil
    }
}
