//
//  MaintenanceTasks.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The maintenance jobs that do something, declared as data. Only ones with
//  a real effect are here: no "free RAM" (macOS manages memory, and purging
//  it only slows the next launch), no "repair permissions" (gone since OS X
//  10.11; SIP protects system files), no periodic scripts (launchd runs what
//  is left of them). `lsregister -kill` was removed from macOS — its help
//  says it was "dangerous and no longer useful" — so Launch Services is
//  re-registered with -f and garbage-collected with -gc instead.
//

import Foundation

enum MaintenanceTasks {

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    static func all(volume: String, logsOlderThan days: Int) -> [MaintenanceTask] {
        [
            MaintenanceTask(
                id: "dns", title: "Flush the DNS cache",
                fixes: "A site still going to its old address after a DNS change, or one name that will not resolve while others do.",
                commands: [["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"]],
                needsRoot: true),
            MaintenanceTask(
                id: "spotlight", title: "Rebuild the Spotlight index of \(volume)",
                fixes: "Spotlight (and Mail's search) not finding files that are there, or finding ones that are gone.",
                commands: [["/usr/bin/mdutil", "-E", volume]], needsRoot: true,
                warning: "macOS re-indexes the whole volume in the background: until it is done searches are incomplete and the Mac works harder — an hour or more on a full disk."),
            MaintenanceTask(
                id: "launch-services", title: "Rebuild the Launch Services database",
                fixes: "Duplicate or stale apps in \u{201C}Open With\u{201D}, wrong app icons, files opening in the wrong app.",
                commands: [[lsregister, "-r", "-f", "-all", "local,system,user"], [lsregister, "-gc"]], needsRoot: false,
                warning: "Re-registers every app in the standard folders; it takes a minute or two."),
            MaintenanceTask(
                id: "logs", title: "Clear logs older than \(days) days",
                fixes: "Space taken by old crash reports and app logs in ~/Library/Logs, which nothing needs to run.",
                commands: [], needsRoot: false, olderThanDays: days),
            MaintenanceTask(
                id: "quicklook", title: "Reset the Quick Look cache",
                fixes: "Stale or wrong thumbnails and previews in Finder and Quick Look.",
                commands: [["/usr/bin/qlmanage", "-r", "cache"]], needsRoot: false),
            MaintenanceTask(
                id: "icon-cache", title: "Reset the icon caches",
                fixes: "Wrong, blank or old app icons in Finder and the Dock that a Launch Services rebuild did not fix.",
                commands: [["/bin/rm", "-rf", "/Library/Caches/com.apple.iconservices.store"],
                           ["/usr/bin/find", "/private/var/folders", "-name", "com.apple.dock.iconcache", "-delete"],
                           ["/usr/bin/killall", "Dock", "Finder"]],
                needsRoot: true,
                warning: "The Dock and Finder restart; icons redraw over the next minute."),
            MaintenanceTask(
                id: "verify-disk", title: "Check \(volume) for file system errors",
                fixes: "Nothing by itself: it reads the volume and says whether it is sound (about 10 seconds on a live volume), so a repair is only tried when there is something to repair.",
                commands: [["/usr/sbin/diskutil", "verifyVolume", volume]], needsRoot: false),
        ]
    }

    /// A command as a person types it: tools on PATH by name, quoted as needed.
    static func display(_ command: [String]) -> String {
        command.enumerated().map { index, word in
            let shown = index == 0 && word.hasPrefix("/usr/bin/") ? String(word.dropFirst("/usr/bin/".count)) : word
            return shown.allSatisfy({ $0.isLetter || $0.isNumber || "-_./,:".contains($0) }) ? shown : PathText.shellQuoted(shown)
        }.joined(separator: " ")
    }

    /// The one line for root's tasks: every command with sudo, joined by `&&`.
    static func byHand(_ tasks: [MaintenanceTask]) -> String? {
        let commands = tasks.filter(\.needsRoot).flatMap(\.commands)
        return commands.isEmpty ? nil : commands.map { "sudo " + display($0) }.joined(separator: " && ")
    }
}
