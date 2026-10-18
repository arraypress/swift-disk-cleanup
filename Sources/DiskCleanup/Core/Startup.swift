//
//  Startup.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  What starts by itself, and who it belongs to: launch agents (yours and
//  /Library's), launch daemons, helpers apps register from inside their
//  bundle (SMAppService), and — when asked, since System Events may ask
//  permission once — legacy login items. Each says its program, owner app
//  and team, whether launchd has it loaded or disabled, and whether it is
//  Apple's. Removing follows `uninstall`: your own agents are unloaded and
//  trashed with undo (which loads them again), root's go in a printed sudo
//  line, legacy login items go through System Events, what an app
//  registered only its app or Login Items settings can remove, and Apple's
//  never go. Disabling and enabling are launchctl's, and reversible.
//

import Darwin
import Foundation

public enum Startup {

    /// The rule on journal entries, so undo knows to load the agent again.
    public static let rule = "startup-agent"

    /// Everything that starts by itself, sorted by kind then label.
    public static func list(context: CleanupContext, loginItems: Bool = false) -> (items: [StartupItem], notes: [String]) {
        var notes: [String] = []
        let root = context.root.path == "/" ? "" : context.root.path
        let home = context.home.path
        let index = AppIndex.build(folders: context.applicationFolders)
        let launchctl = CommandLocator.system("launchctl", at: "/bin/launchctl", in: context)
        let uid = getuid()
        var disabled: [String: Bool]?
        if let launchctl, let text = run(launchctl, ["print-disabled", "gui/\(uid)"]) { disabled = StartupText.disabled(text) }
        if let launchctl, let text = run(launchctl, ["print-disabled", "system"]) {
            disabled = (disabled ?? [:]).merging(StartupText.disabled(text)) { user, _ in user }
        }
        if launchctl == nil { notes.append("launchctl was not found, so loaded and disabled are not known") }

        var items: [StartupItem] = []
        let folders = [(home + "/Library/LaunchAgents", "launch-agent", "gui"), (root + "/Library/LaunchAgents", "launch-agent", "gui"),
                       (root + "/Library/LaunchDaemons", "launch-daemon", "system")]
        for (folder, kind, domain) in folders {
            for name in PathProbe.list(folder).names where name.hasSuffix(".plist") {
                items.append(item(folder + "/" + name, kind: kind, domain: domain, index: index, disabled: disabled,
                                  launchctl: launchctl, context: context))
            }
        }
        // Helpers apps register from inside themselves: SMAppService agents and daemons, and login item apps.
        for app in index.apps.values.flatMap({ $0 }) {
            for (sub, domain) in [("Contents/Library/LaunchAgents", "gui"), ("Contents/Library/LaunchDaemons", "system")] {
                for name in PathProbe.list(app.path + "/" + sub).names where name.hasSuffix(".plist") {
                    items.append(item(app.path + "/" + sub + "/" + name, kind: "app-service", domain: domain, index: index,
                                      disabled: disabled, launchctl: launchctl, context: context, owner: app))
                }
            }
            for name in PathProbe.list(app.path + "/Contents/Library/LoginItems").names where name.hasSuffix(".app") {
                let helper = app.path + "/Contents/Library/LoginItems/" + name
                let id = AppIndex.read(appAt: helper)?.bundleID ?? name
                items.append(StartupItem(kind: "app-service", label: id, path: helper, program: helper, programExists: true,
                                         owner: app.name ?? PathText.lastComponent(app.path), ownerBundleID: app.bundleID,
                                         team: BundleIDs.isApple(app.bundleID) ? nil : context.records.teamID(appAt: app.path),
                                         isApple: BundleIDs.isApple(app.bundleID), loaded: nil, disabled: disabled?[id],
                                         removal: BundleIDs.isApple(app.bundleID) ? "never" : "settings"))
            }
        }
        if loginItems {
            if let osascript = CommandLocator.system("osascript", at: "/usr/bin/osascript", in: context),
               let text = run(osascript, ["-s", "s", "-e", "tell application \"System Events\" to get {name, path} of every login item"]) {
                for login in StartupText.loginItems(text) {
                    let app = AppIndex.read(appAt: login.path)
                    let isApple = app.map { BundleIDs.isApple($0.bundleID) } ?? false
                    items.append(StartupItem(kind: "login-item", label: login.name, path: login.path, program: login.path,
                                             programExists: PathProbe.exists(login.path), owner: app?.name ?? login.name,
                                             ownerBundleID: app?.bundleID, team: nil, isApple: isApple, loaded: nil, disabled: nil,
                                             removal: isApple ? "never" : "system-events"))
                }
            } else {
                notes.append("System Events did not list login items (allow your terminal under Privacy & Security › Automation)")
            }
        }
        return (items.sorted { ($0.kind, $0.label) < ($1.kind, $1.label) }, notes)
    }

    /// One launchd plist, described.
    static func item(_ plist: String, kind: String, domain: String, index: AppIndex, disabled: [String: Bool]?,
                     launchctl: String?, context: CleanupContext, owner: InstalledApp? = nil) -> StartupItem {
        let data = PathProbe.read(plist, limit: 1 << 20)
        let dictionary = data.flatMap(PlistValues.dictionary) ?? [:]
        let label = dictionary["Label"] as? String ?? String(PathText.lastComponent(plist).dropLast(".plist".count))
        var program = (dictionary["Program"] as? String) ?? (dictionary["ProgramArguments"] as? [String])?.first
        if program == nil, let relative = dictionary["BundleProgram"] as? String, let owner { program = owner.path + "/" + relative }
        let root = context.root.path == "/" ? "" : context.root.path
        // A fixture reads /Applications, /Library… under <home>/root; a path in the home is itself.
        let onDisk = program.map { $0.hasPrefix("/") && !root.isEmpty && !PathText.isWithin($0, context.home.path) ? root + $0 : $0 }
        let associated = (dictionary["AssociatedBundleIdentifiers"] as? [String]) ?? (dictionary["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        let app = owner ?? onDisk.flatMap(StartupText.app).flatMap(AppIndex.read)
            ?? associated.lazy.compactMap { index.apps[$0.lowercased()]?.first }.first
        let isApple = StartupText.isApple(label: label, plist: plist) || app.map { BundleIDs.isApple($0.bundleID) } ?? false
        var team: String?
        if !isApple, let signed = app?.path ?? onDisk, PathProbe.exists(signed) { team = context.records.teamID(appAt: signed) }
        var loaded: Bool?
        if let launchctl {
            let target = domain == "system" ? "system/\(label)" : "gui/\(getuid())/\(label)"
            loaded = CommandRunner.run(launchctl, ["print", target], timeout: 15).map { $0.status == 0 }
        }
        // No program at all (an emptied plist, as updaters leave) is a dead entry: "program missing".
        return StartupItem(kind: kind, label: label, path: plist, program: program, programExists: onDisk.map(PathProbe.exists) ?? false,
                           owner: app?.name ?? app.map { PathText.lastComponent($0.path) }, ownerBundleID: app?.bundleID, team: team,
                           isApple: isApple, loaded: loaded, disabled: disabled?[label],
                           removal: StartupText.removal(kind: kind, path: plist, isApple: isApple, home: context.home.path))
    }

    /// The item a label (or a login item's name) names.
    public static func find(_ label: String, in items: [StartupItem]) throws(DiskCleanupError) -> StartupItem {
        let matches = items.filter { $0.label == label }
        guard let item = matches.first else { throw .itemNotFound(label) }
        guard matches.count == 1 else { throw .refusedTarget("\(label) names \(matches.count) startup items; remove the plist itself instead") }
        return item
    }

    /// What removing `item` would do. Apple's are refused.
    public static func plan(_ item: StartupItem, context: CleanupContext) throws(DiskCleanupError) -> StartupRemoval {
        switch item.removal {
        case "never":
            throw .refusedTarget("\(item.label) is Apple's; diskmaid lists it and never removes it")
        case "settings", "system-events":
            return StartupRemoval(item: item, target: nil, byHand: nil, settings: item.removal == "settings" ? StartupText.settingsURL : nil)
        default:
            let measured = Sizer.measure(item.path)
            let domain = item.kind == "launch-daemon" ? "system" : "gui"
            let target = Item(id: ItemID.make(rule: rule, path: item.path), rule: rule, category: .leftovers, path: item.path,
                              bytes: measured.bytes, tier: .safe, removal: item.removal == "trash" ? .trash : .sudo, regenerable: false,
                              owner: item.owner, newest: measured.newest, visibility: measured.visibility, protected: nil,
                              evidence: ["launchLabel": item.label, "launchDomain": domain], note: nil,
                              identity: Sizer.identity(item.path, bytes: measured.bytes))
            return StartupRemoval(item: item, target: target, byHand: HandBack.line([target], among: [target]), settings: nil)
        }
    }

    /// Removes per the plan: your agent unloaded and trashed (journalled, so
    /// undo loads it again), a login item through System Events, Login Items
    /// settings opened for what only its app can remove. Root's part is the
    /// plan's `byHand`, never run here.
    public static func remove(_ removal: StartupRemoval, catalogue: Catalogue, context: CleanupContext,
                              batch: String = Remover.newBatchID()) -> [RemovalOutcome] {
        let item = removal.item
        switch item.removal {
        case "settings":
            if let open = CommandLocator.system("open", at: "/usr/bin/open", in: context) {
                _ = CommandRunner.run(open, [StartupText.settingsURL.absoluteString], timeout: 15)
            }
            return [RemovalOutcome(id: item.label, path: item.path, result: .skipped,
                                   reason: "only \(item.owner ?? "its app") can remove it: Login Items settings are open")]
        case "system-events":
            guard let osascript = CommandLocator.system("osascript", at: "/usr/bin/osascript", in: context) else {
                return [RemovalOutcome(id: item.label, path: item.path, result: .failed, reason: "osascript was not found")]
            }
            let name = item.label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let output = CommandRunner.run(osascript, ["-e", "tell application \"System Events\" to delete login item \"\(name)\""], timeout: 30)
            return [RemovalOutcome(id: item.label, path: item.path, result: output?.succeeded == true ? .deleted : .failed,
                                   reason: output?.succeeded == true ? nil : output?.errorText ?? "System Events did not answer")]
        default:
            guard let target = removal.target else { return [] }
            if item.kind != "launch-daemon", let launchctl = CommandLocator.system("launchctl", at: "/bin/launchctl", in: context) {
                _ = CommandRunner.run(launchctl, ["bootout", "gui/\(getuid())/\(item.label)"], timeout: 30)
            }
            return Remover.remove([target], catalogue: catalogue, context: context, batch: batch, allowing: Uninstaller.allowedInside)
        }
    }

    /// `launchctl disable` (or `enable`) for an agent of yours, which launchd
    /// remembers until undone. A daemon's is root's: the line comes back.
    public static func setEnabled(_ enabled: Bool, _ item: StartupItem, context: CleanupContext) throws(DiskCleanupError) -> (done: Bool, byHand: String?) {
        guard !item.isApple else { throw .refusedTarget("\(item.label) is Apple's; diskmaid does not change it") }
        guard item.kind != "login-item" else { throw .refusedTarget("\(item.label) is a login item; remove it instead") }
        let verb = enabled ? "enable" : "disable"
        if item.kind == "launch-daemon" {
            return (false, "sudo launchctl \(verb) system/" + PathText.shellQuoted(item.label))
        }
        guard let launchctl = CommandLocator.system("launchctl", at: "/bin/launchctl", in: context),
              let output = CommandRunner.run(launchctl, [verb, "gui/\(getuid())/\(item.label)"], timeout: 30), output.succeeded else {
            throw .refusedTarget("launchctl \(verb) did not work for \(item.label)")
        }
        return (true, nil)
    }

    /// Loads a restored agent of yours again.
    static func bootstrap(_ plist: String, context: CleanupContext) -> String? {
        guard let launchctl = CommandLocator.system("launchctl", at: "/bin/launchctl", in: context) else { return "launchctl was not found" }
        guard let output = CommandRunner.run(launchctl, ["bootstrap", "gui/\(getuid())", plist], timeout: 30) else { return "launchctl did not start" }
        return output.succeeded ? nil : "launchctl bootstrap: \(output.errorText)"
    }

    static func run(_ tool: String, _ arguments: [String]) -> String? {
        guard let output = CommandRunner.run(tool, arguments, timeout: 30), output.succeeded else { return nil }
        return output.text
    }
}
