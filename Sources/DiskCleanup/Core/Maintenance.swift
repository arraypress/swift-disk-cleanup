//
//  Maintenance.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Running the maintenance jobs: each of this user's commands with no shell,
//  stopping at the first that fails; root's never — they come back as one
//  line for a person; old logs through the catalogue's `user-logs` rule, to
//  the Trash and journalled, so `undo` puts them back. A runner protocol so
//  tests stand in for lsregister and qlmanage.
//

import Foundation

/// Runs one of macOS's tools.
public protocol MaintenanceRunner: Sendable {
    /// Runs `tool` (a system path) with `arguments`; `nil` when it could not start.
    func run(_ tool: String, _ arguments: [String], timeout: Double) -> CommandOutput?
}

/// The real tools — or, for a fixture home, only stand-ins in `<home>/bin`.
public struct SystemMaintenanceRunner: MaintenanceRunner {
    let context: CleanupContext

    public init(context: CleanupContext) {
        self.context = context
    }

    public func run(_ tool: String, _ arguments: [String], timeout: Double) -> CommandOutput? {
        guard let path = CommandLocator.system(PathText.lastComponent(tool), at: tool, in: context) else { return nil }
        return CommandRunner.run(path, arguments, timeout: timeout)
    }
}

public enum Maintenance {

    /// Every task, in the order they are shown and run.
    public static func tasks(volume: String = "/", logsOlderThan days: Int = 30) -> [MaintenanceTask] {
        MaintenanceTasks.all(volume: volume, logsOlderThan: days)
    }

    /// The line a person runs as root for `tasks`, or `nil` when none needs root.
    public static func byHand(_ tasks: [MaintenanceTask]) -> String? {
        MaintenanceTasks.byHand(tasks)
    }

    /// A command as a person would type it.
    public static func display(_ command: [String]) -> String {
        MaintenanceTasks.display(command)
    }

    /// The old logs `logs` would move to the Trash (review tier, taken here by name).
    public static func logs(olderThan days: Int, catalogue: Catalogue, context: CleanupContext) -> [Item] {
        let report = Scanner.scan(catalogue: catalogue, context: context, options: ScanScope(categories: [.userCaches]))
        let logs = report.items.filter { $0.rule == "user-logs" }
        return Selection.pick(logs, categories: [.userCaches], ids: [], includeReview: true,
                              olderThanDays: days, now: context.now).take
    }

    /// Runs one task. Root's is never run: its outcome is the line.
    public static func run(_ task: MaintenanceTask, catalogue: Catalogue, context: CleanupContext,
                           runner: (any MaintenanceRunner)? = nil, batch: String = Remover.newBatchID()) -> MaintenanceOutcome {
        if task.needsRoot {
            return MaintenanceOutcome(task: task.id, result: .byHand, detail: byHand([task]))
        }
        if task.id == "logs" {
            let items = logs(olderThan: task.olderThanDays ?? 30, catalogue: catalogue, context: context)
            let removals = Remover.remove(items, catalogue: catalogue, context: context, batch: batch)
            let failed = removals.filter { $0.result == .failed }
            let moved = removals.filter { $0.result == .trashed }
            let bytes = moved.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            return MaintenanceOutcome(task: task.id, result: failed.isEmpty ? .ran : .failed,
                                      detail: failed.isEmpty ? "\(moved.count) moved to the Trash (\(bytes) bytes)"
                                                             : "\(failed.count) could not be moved: \(failed.compactMap(\.reason).joined(separator: "; "))",
                                      removals: removals)
        }
        let runner = runner ?? SystemMaintenanceRunner(context: context)
        for command in task.commands {
            guard let tool = command.first else { continue }
            guard let output = runner.run(tool, Array(command.dropFirst()), timeout: 600) else {
                return MaintenanceOutcome(task: task.id, result: .failed, detail: "\(display(command)) could not start")
            }
            guard output.succeeded else {
                let why = output.timedOut ? "timed out" : "exit \(output.status)" + (output.errorText.isEmpty ? "" : ": " + output.errorText.suffix(300))
                return MaintenanceOutcome(task: task.id, result: .failed, detail: "\(display(command)) \(why)")
            }
        }
        return MaintenanceOutcome(task: task.id, result: .ran, detail: task.commands.map(display).joined(separator: " && "))
    }
}
