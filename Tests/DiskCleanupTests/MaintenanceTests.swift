//
//  MaintenanceTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  The maintenance jobs with a stand-in runner: this user's commands run in
//  order and stop at the first failure, root's never run and come back as
//  one line, and old logs go to a fixture's Trash with undo.
//

import Foundation
import os
import Testing
@testable import DiskCleanup

/// Records every command; answers with `status` for tools named in `failing`.
final class FixtureRunner: MaintenanceRunner {
    let failing: Set<String>
    private let calls = OSAllocatedUnfairLock(initialState: [[String]]())

    init(failing: Set<String> = []) { self.failing = failing }

    var ran: [[String]] { calls.withLock { $0 } }

    func run(_ tool: String, _ arguments: [String], timeout: Double) -> CommandOutput? {
        calls.withLock { $0.append([tool] + arguments) }
        let fails = failing.contains(PathText.lastComponent(tool))
        return CommandOutput(status: fails ? 1 : 0, timedOut: false, stdout: Data(), stderr: fails ? Data("it broke".utf8) : Data())
    }
}

struct MaintenanceTests {

    @Test func theTasksAreTheHonestOnesAndRootsAreOneLine() {
        let tasks = Maintenance.tasks(volume: "/", logsOlderThan: 30)
        #expect(tasks.map(\.id) == ["dns", "spotlight", "launch-services", "logs", "quicklook", "icon-cache", "verify-disk"])
        #expect(tasks.allSatisfy { !$0.fixes.isEmpty && !$0.title.isEmpty })
        #expect(tasks.filter(\.needsRoot).map(\.id) == ["dns", "spotlight", "icon-cache"])
        #expect(tasks.first { $0.id == "spotlight" }?.warning?.contains("an hour or more") == true)
        let lsregister = tasks.first { $0.id == "launch-services" }?.commands ?? []
        #expect(lsregister.allSatisfy { !$0.contains("-kill") } && lsregister.first?.suffix(4) == ["-r", "-f", "-all", "local,system,user"])
        #expect(Maintenance.byHand(tasks) == "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && sudo mdutil -E / && "
                + "sudo /bin/rm -rf /Library/Caches/com.apple.iconservices.store && "
                + "sudo find /private/var/folders -name com.apple.dock.iconcache -delete && sudo killall Dock Finder")
        #expect(Maintenance.byHand(tasks.filter { !$0.needsRoot }) == nil)
        #expect(Maintenance.byHand(Maintenance.tasks(volume: "/Volumes/Big Disk").filter { $0.id == "spotlight" })
                == "sudo mdutil -E '/Volumes/Big Disk'")
    }

    @Test func thisUsersCommandsRunInOrderAndStopAtTheFirstFailure() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        let context = fixture.context()
        let tasks = Maintenance.tasks()
        let services = try #require(tasks.first { $0.id == "launch-services" })
        let runner = FixtureRunner()
        let ran = Maintenance.run(services, catalogue: catalogue, context: context, runner: runner)
        #expect(ran.result == .ran)
        #expect(runner.ran == services.commands)

        let failing = FixtureRunner(failing: ["lsregister"])
        let failed = Maintenance.run(services, catalogue: catalogue, context: context, runner: failing)
        #expect(failed.result == .failed && failed.detail?.contains("exit 1: it broke") == true, "\(failed)")
        #expect(failing.ran.count == 1)

        let dns = try #require(tasks.first { $0.id == "dns" })
        let rootRunner = FixtureRunner()
        let root = Maintenance.run(dns, catalogue: catalogue, context: context, runner: rootRunner)
        #expect(root.result == .byHand && root.detail == "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder")
        #expect(rootRunner.ran.isEmpty)
    }

    @Test func aFixtureHomeRunsOnlyItsOwnStandIns() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let quicklook = try #require(Maintenance.tasks().first { $0.id == "quicklook" })
        let missing = Maintenance.run(quicklook, catalogue: try Catalogue.builtIn(), context: fixture.context())
        #expect(missing.result == .failed && missing.detail?.contains("could not start") == true)
        try fixture.file("bin/qlmanage", contents: "#!/bin/sh\necho \"$@\" > \"$(dirname \"$0\")/../qlmanage-ran\"\n")
        _ = CommandRunner.run("/bin/chmod", ["+x", fixture.path("bin/qlmanage")], timeout: 10)
        let ran = Maintenance.run(quicklook, catalogue: try Catalogue.builtIn(), context: fixture.context())
        #expect(ran.result == .ran)
        #expect((try? String(contentsOfFile: fixture.path("qlmanage-ran"), encoding: .utf8)) == "-r cache\n")
    }

    @Test func oldLogsGoToTheTrashWithUndoAndYoungOnesStay() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let catalogue = try Catalogue.builtIn()
        let context = fixture.context()
        try fixture.file("Library/Logs/young.log", bytes: 1000)
        #expect(Maintenance.logs(olderThan: 60, catalogue: catalogue, context: context).isEmpty)
        let old = Maintenance.logs(olderThan: 20, catalogue: catalogue, context: context)
        #expect(old.map(\.path) == [fixture.path("Library/Logs/old.log")])

        let logs = try #require(Maintenance.tasks(logsOlderThan: 20).first { $0.id == "logs" })
        let outcome = Maintenance.run(logs, catalogue: catalogue, context: context, runner: FixtureRunner(), batch: "m1")
        #expect(outcome.result == .ran && outcome.removals.map(\.result) == [.trashed], "\(outcome)")
        #expect(!fixture.exists("Library/Logs/old.log") && fixture.exists("Library/Logs/young.log"))
        _ = try Restorer.undo("m1", journal: context.journal, context: context)
        #expect(fixture.exists("Library/Logs/old.log"))
    }
}
