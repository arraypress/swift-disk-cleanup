//
//  CommandRunner.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Running another program with no shell and no pipe to deadlock on: its
//  output goes to temporary files, read once it has exited, and its stdin
//  is /dev/null (or a file) so nothing it runs can wait on a person.
//

import Foundation

public enum CommandRunner {

    /// Runs `executable` with `arguments`, stopping it after `timeout` seconds.
    public static func run(_ executable: String, _ arguments: [String], timeout: Double = 120,
                           directory: String? = nil, input: Data? = nil,
                           environment: [String: String]? = nil) -> CommandOutput? {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskmaid-run-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outURL = scratch.appendingPathComponent("out"), errURL = scratch.appendingPathComponent("err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: outURL), let err = try? FileHandle(forWritingTo: errURL) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        if let input {
            let inURL = scratch.appendingPathComponent("in")
            FileManager.default.createFile(atPath: inURL.path, contents: input)
            process.standardInput = FileHandle(forReadingAtPath: inURL.path)
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        if let environment { process.environment = environment }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if done.wait(timeout: .now() + 3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                done.wait()
            }
        }
        try? out.close()
        try? err.close()
        return CommandOutput(
            status: process.terminationStatus,
            timedOut: timedOut,
            stdout: (try? Data(contentsOf: outURL)) ?? Data(),
            stderr: (try? Data(contentsOf: errURL)) ?? Data()
        )
    }
}

extension CommandOutput {
    var succeeded: Bool { status == 0 && !timedOut }
    var text: String { String(decoding: stdout, as: UTF8.self) }
    var errorText: String { String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
}
