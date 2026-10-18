//
//  StartupTests.swift
//  DiskCleanupTests
//
//  Created by David Sherlock on 2026.
//
//  Startup items in a fixture home, with stand-in launchctl, open and
//  osascript in its bin that log what they are asked: who each item is,
//  removal the uninstall way with undo loading it again, root's and apps'
//  handed back, Apple's refused, disable and enable.
//

import Darwin
import Foundation
import Testing
@testable import DiskCleanup

struct StartupTests {

    func plist(_ values: [String: Any]) throws -> String {
        String(decoding: try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0), as: UTF8.self)
    }

    func make() throws -> (Fixture, CleanupContext, String) {
        let fixture = try Fixture.make()
        let log = fixture.path("data/calls.log")
        try fixture.file("data/loaded.txt", contents: "dev.mine.agent\ndev.vendor.daemon\n")
        try fixture.file("data/disabled.txt", contents: "\tdisabled services = {\n\t\t\"dev.mine.agent\" => enabled\n\t\t\"dev.vendor.daemon\" => disabled\n\t}\n")
        let tools = [
            "launchctl": "echo \"launchctl $@\" >> '\(log)'\ncase \"$1\" in\nprint) label=\"${2##*/}\"; grep -qx \"$label\" '\(fixture.path("data/loaded.txt"))' && exit 0 || exit 113 ;;\nprint-disabled) cat '\(fixture.path("data/disabled.txt"))' ;;\nesac\nexit 0",
            "open": "echo \"open $@\" >> '\(log)'",
            "osascript": "echo \"osascript $@\" >> '\(log)'\ncase \"$*\" in *'get {name, path}'*) echo '{{\"Old Helper\"}, {\"/Applications/Old Helper.app\"}}' ;; esac",
        ]
        for (name, body) in tools {
            try fixture.file("bin/" + name, contents: "#!/bin/sh\n" + body + "\n")
            _ = CommandRunner.run("/bin/chmod", ["755", fixture.path("bin/" + name)], timeout: 10)
        }
        let apps = fixture.home.appendingPathComponent("Applications")
        try InstallerFixtures.app("Mine", id: "dev.mine.app", version: "1", in: apps)
        try InstallerFixtures.app("Vendor", id: "dev.vendor.app", version: "1", in: apps)
        try fixture.file("Library/LaunchAgents/dev.mine.agent.plist",
                         contents: try plist(["Label": "dev.mine.agent", "Program": fixture.path("Applications/Mine.app/Contents/MacOS/Mine")]))
        try fixture.file("Library/LaunchAgents/dev.shell.agent.plist", contents: try plist(["Label": "dev.shell.agent", "ProgramArguments": ["/bin/sh", "-c", "true"]]))
        try fixture.file("Library/LaunchAgents/com.apple.something.plist", contents: try plist(["Label": "com.apple.something", "Program": "/usr/libexec/x"]))
        try fixture.file("Library/LaunchAgents/dev.emptied.agent.plist", contents: try plist([:]))
        try fixture.file("root/Library/LaunchDaemons/dev.vendor.daemon.plist",
                         contents: try plist(["Label": "dev.vendor.daemon", "Program": "/Applications/Vendor.app/Contents/MacOS/Vendor",
                                              "AssociatedBundleIdentifiers": ["dev.vendor.app"]]))
        try fixture.file("Applications/Vendor.app/Contents/Library/LaunchAgents/dev.vendor.helper.plist",
                         contents: try plist(["Label": "dev.vendor.helper", "BundleProgram": "Contents/MacOS/Vendor"]))
        try InstallerFixtures.app("VendorLogin", id: "dev.vendor.login", version: "1", in: apps.appendingPathComponent("Vendor.app/Contents/Library/LoginItems"))
        var context = fixture.context()
        context.records = FixtureRecords(teams: ["Mine.app": "MINE123456", "Vendor.app": "VEND123456"])
        return (fixture, context, log)
    }

    func calls(_ log: String) -> [String] {
        ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    @Test func eachItemSaysWhoseItIsAndHowItCanGo() throws {
        let (fixture, context, _) = try make()
        defer { fixture.remove() }
        let items = Startup.list(context: context).items
        func item(_ label: String) throws -> StartupItem { try #require(items.first { $0.label == label }, "\(label)") }
        let mine = try item("dev.mine.agent")
        #expect(mine.kind == "launch-agent" && mine.owner == "Mine" && mine.team == "MINE123456" && mine.loaded == true && mine.disabled == false)
        #expect(mine.removal == "trash" && !mine.isApple)
        // Running /bin/sh does not make an agent Apple's.
        #expect(try item("dev.shell.agent").isApple == false)
        #expect(try item("com.apple.something").isApple && (try item("com.apple.something").removal) == "never")
        #expect(try item("dev.emptied.agent").programExists == false)
        let daemon = try item("dev.vendor.daemon")
        #expect(daemon.kind == "launch-daemon" && daemon.removal == "sudo" && daemon.disabled == true && daemon.owner == "Vendor" && daemon.team == "VEND123456")
        let helper = try item("dev.vendor.helper")
        #expect(helper.kind == "app-service" && helper.removal == "settings" && helper.program?.hasSuffix("Vendor.app/Contents/MacOS/Vendor") == true)
        #expect(try item("dev.vendor.login").removal == "settings")
        #expect(!items.contains { $0.kind == "login-item" })
        let withLogin = Startup.list(context: context, loginItems: true).items
        #expect(withLogin.first { $0.kind == "login-item" }?.label == "Old Helper")
    }

    @Test func yourAgentIsUnloadedTrashedAndUndoLoadsItAgain() throws {
        let (fixture, context, log) = try make()
        defer { fixture.remove() }
        let mine = try Startup.find("dev.mine.agent", in: Startup.list(context: context).items)
        let plan = try Startup.plan(mine, context: context)
        #expect(plan.byHand == nil && plan.target?.removal == .trash)
        let outcomes = Startup.remove(plan, catalogue: try Catalogue.builtIn(), context: context, batch: "s1")
        #expect(outcomes.map(\.result) == [.trashed])
        #expect(!fixture.exists("Library/LaunchAgents/dev.mine.agent.plist"))
        #expect(calls(log).contains("launchctl bootout gui/\(getuid())/dev.mine.agent"))
        let restored = try Restorer.undo("s1", journal: context.journal, context: context)
        #expect(restored.map(\.result) == [.restored] && restored.first?.reason == nil)
        #expect(fixture.exists("Library/LaunchAgents/dev.mine.agent.plist"))
        #expect(calls(log).contains("launchctl bootstrap gui/\(getuid()) \(fixture.path("Library/LaunchAgents/dev.mine.agent.plist"))"))
    }

    @Test func rootsAppsAndApplesAreHandedBackOrRefused() throws {
        let (fixture, context, log) = try make()
        defer { fixture.remove() }
        let items = Startup.list(context: context).items
        let daemon = try Startup.find("dev.vendor.daemon", in: items)
        let plan = try Startup.plan(daemon, context: context)
        #expect(plan.byHand == "sudo launchctl bootout system/'dev.vendor.daemon'; sudo rm -rf '\(daemon.path)'")
        let helper = try Startup.plan(try Startup.find("dev.vendor.helper", in: items), context: context)
        #expect(helper.settings?.absoluteString == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        let opened = Startup.remove(helper, catalogue: try Catalogue.builtIn(), context: context)
        #expect(opened.first?.result == .skipped && calls(log).contains("open x-apple.systempreferences:com.apple.LoginItems-Settings.extension"))
        let apple = try Startup.find("com.apple.something", in: items)
        #expect(throws: DiskCleanupError.self) { try Startup.plan(apple, context: context) }
        #expect(throws: DiskCleanupError.self) { try Startup.setEnabled(false, apple, context: context) }
        let login = try Startup.find("Old Helper", in: Startup.list(context: context, loginItems: true).items)
        let deleted = Startup.remove(try Startup.plan(login, context: context), catalogue: try Catalogue.builtIn(), context: context)
        #expect(deleted.first?.result == .deleted)
        #expect(calls(log).contains { $0.contains("delete login item \"Old Helper\"") })
    }

    @Test func disableAndEnableAreLaunchctls() throws {
        let (fixture, context, log) = try make()
        defer { fixture.remove() }
        let items = Startup.list(context: context).items
        let mine = try Startup.find("dev.mine.agent", in: items)
        #expect(try Startup.setEnabled(false, mine, context: context).done)
        #expect(try Startup.setEnabled(true, mine, context: context).done)
        #expect(calls(log).contains("launchctl disable gui/\(getuid())/dev.mine.agent"))
        #expect(calls(log).contains("launchctl enable gui/\(getuid())/dev.mine.agent"))
        let daemon = try Startup.setEnabled(false, try Startup.find("dev.vendor.daemon", in: items), context: context)
        #expect(!daemon.done && daemon.byHand == "sudo launchctl disable system/'dev.vendor.daemon'")
        #expect(!calls(log).contains { $0.hasPrefix("launchctl disable system/") })
    }

    @Test func whatLaunchctlAndSystemEventsPrintIsRead() {
        #expect(StartupText.disabled("\t\t\"a.b\" => disabled\n\t\t\"c.d\" => enabled\n\t\t\"e.f\" => true\n") == ["a.b": true, "c.d": false, "e.f": true])
        let items = StartupText.loginItems(#"{{"One", "Two \"Quoted\""}, {"/Applications/One.app", "/Applications/Two.app"}}"#)
        #expect(items.map(\.name) == ["One", #"Two \"Quoted\""#] && items.map(\.path) == ["/Applications/One.app", "/Applications/Two.app"])
        #expect(StartupText.app(containing: "/Applications/X.app/Contents/MacOS/x") == "/Applications/X.app")
        #expect(!StartupText.isApple(label: "local.test", plist: "/Users/me/Library/LaunchAgents/local.test.plist"))
        #expect(StartupText.isApple(label: "x.y", plist: "/System/Library/LaunchAgents/x.y.plist"))
    }
}
