//
//  Remover.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Acting on a plan, one item at a time, each one checked again first:
//
//  1. the path is still allowed (system and protected paths, re-checked here
//     even though the scan already did — this is the last door);
//  2. it is still the same thing — device, inode, modification time and
//     allocated size all as measured — or it is skipped as "changed";
//  3. then trash (journalled for undo), delete, or the owning tool's command
//     — or, for a root-owned item, nothing but the sudo command to run.
//

import Foundation

public enum Remover {

    /// Removes `items`. Never throws for one item's failure: each outcome says
    /// what happened, and the caller decides what a failure means.
    ///
    /// - Parameters:
    ///   - batch: The journal batch id for this run's trashed items.
    ///   - progress: Told before each item.
    public static func remove(_ items: [Item], catalogue: Catalogue, context: CleanupContext,
                              batch: String = Remover.newBatchID(),
                              progress: ((Item) -> Void)? = nil) -> [RemovalOutcome] {
        var outcomes: [RemovalOutcome] = []
        var commandsRun: [[String]: RemovalOutcome.Result] = [:]
        for item in items {
            progress?(item)
            outcomes.append(removeOne(item, catalogue: catalogue, context: context, batch: batch, commandsRun: &commandsRun))
        }
        return outcomes
    }

    /// A batch id that sorts by time: `20261015-142233-1a2b`.
    public static func newBatchID(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: now) + "-" + UUID().uuidString.prefix(4).lowercased()
    }

    static func removeOne(_ item: Item, catalogue: Catalogue, context: CleanupContext, batch: String,
                          commandsRun: inout [[String]: RemovalOutcome.Result]) -> RemovalOutcome {
        func skip(_ reason: String) -> RemovalOutcome {
            RemovalOutcome(id: item.id, path: item.path, result: .skipped, reason: reason)
        }
        func fail(_ reason: String) -> RemovalOutcome {
            RemovalOutcome(id: item.id, path: item.path, result: .failed, reason: reason)
        }
        if item.tier == .report { return skip("report only") }
        if let protected = item.protected { return skip(protected) }
        let isFile = item.path.hasPrefix("/")
        if isFile {
            if let reason = PathSafety.reason(for: item.path, catalogue: catalogue, home: context.home.path) {
                return skip(reason)
            }
            if let changed = hasChanged(item) { return skip(changed) }
        }

        switch item.removal {
        case .command(let template):
            guard let arguments = CommandTemplate.fill(template, from: item.evidence) else {
                return fail("the command \(CommandTemplate.display(template)) has a value missing")
            }
            if let earlier = commandsRun[arguments] {
                return RemovalOutcome(id: item.id, path: item.path, result: earlier == .commanded ? .commanded : .failed,
                                      to: CommandTemplate.display(arguments), reason: "same command as an earlier item")
            }
            guard let tool = arguments.first, let executable = CommandLocator.find(tool, in: context) else {
                return fail("\(arguments.first ?? "the tool") is not installed here")
            }
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("diskmaid-cmd-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let output = CommandRunner.run(executable, Array(arguments.dropFirst()), timeout: 1800, directory: scratch.path)
            guard let output, output.succeeded else {
                commandsRun[arguments] = .failed
                let why = output.map { $0.timedOut ? "timed out" : "exit \($0.status): \($0.errorText.suffix(300))" } ?? "did not start"
                return fail("\(CommandTemplate.display(arguments)) \(why)")
            }
            commandsRun[arguments] = .commanded
            var freed = item.bytes
            if isFile, item.identity != nil, let before = item.bytes {
                freed = max(0, before - (PathProbe.exists(item.path) ? Sizer.measure(item.path).bytes : 0))
            }
            return RemovalOutcome(id: item.id, path: item.path, result: .commanded, to: CommandTemplate.display(arguments), bytes: freed)

        case .trash:
            guard isFile else { return fail("not a file") }
            do {
                let landed = try TrashBin.move(item.path, folder: context.trashFolder)
                let entry = JournalEntry(id: UUID().uuidString.lowercased(), batch: batch, original: item.path,
                                         trashed: landed, at: Date(), bytes: item.bytes, rule: item.rule)
                do {
                    try JournalStore.append(entry, to: context.journal)
                } catch {
                    return RemovalOutcome(id: item.id, path: item.path, result: .trashed, to: landed, bytes: item.bytes,
                                          reason: "moved, but the undo journal could not be written: \(error.localizedDescription)")
                }
                return RemovalOutcome(id: item.id, path: item.path, result: .trashed, to: landed, bytes: item.bytes)
            } catch {
                return fail(error.localizedDescription)
            }

        case .sudo:
            return RemovalOutcome(id: item.id, path: item.path, result: .skipped, to: item.removal.byHand(item.path),
                                  reason: "owned by root: diskmaid does not ask for admin rights, so run the command yourself")

        case .delete:
            guard isFile else { return fail("not a file") }
            do {
                try FileManager.default.removeItem(atPath: item.path)
                return RemovalOutcome(id: item.id, path: item.path, result: .deleted, bytes: item.bytes)
            } catch {
                return fail(error.localizedDescription)
            }
        }
    }

    /// Why the item is no longer what was measured, or `nil` when it still is.
    static func hasChanged(_ item: Item) -> String? {
        guard let planned = item.identity else { return nil }
        guard let now = Sizer.identity(item.path, bytes: Sizer.measure(item.path).bytes) else {
            return "gone since it was measured"
        }
        if now.device != planned.device || now.inode != planned.inode { return "replaced since it was measured" }
        if now.modified != planned.modified { return "modified since it was measured" }
        if now.bytes != planned.bytes { return "size changed since it was measured" }
        return nil
    }
}
