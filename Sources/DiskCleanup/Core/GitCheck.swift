//
//  GitCheck.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  A build folder that git tracks files in is not build output, whatever its
//  name. Asked of a real git only: /usr/bin/git on a Mac without the command
//  line tools opens an installer dialog, so it is never used.
//

import Foundation

enum GitCheck {

    static let candidates = [
        "/opt/homebrew/bin/git", "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    static let executable: String? = {
        if let selected = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"),
           FileManager.default.isExecutableFile(atPath: selected + "/usr/bin/git") {
            return selected + "/usr/bin/git"
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Why `path` must stay because of git, or `nil` when git tracks nothing in it.
    static func protection(_ path: String) -> String? {
        var folder = PathText.parent(path)
        var repository: String?
        while folder != "/" {
            if PathProbe.exists(folder + "/.git") { repository = folder; break }
            folder = PathText.parent(folder)
        }
        guard let repository else { return nil }
        guard let git = executable else { return "inside a git repository, and no git to ask" }
        let relative = String(path.dropFirst(repository.count + 1))
        guard let output = CommandRunner.run(git, ["-C", repository, "ls-files", "-z", "--", relative], timeout: 60),
              output.succeeded else {
            return "git could not say what it tracks here"
        }
        return output.stdout.isEmpty ? nil : "holds files git tracks"
    }
}
