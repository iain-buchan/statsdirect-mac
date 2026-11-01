import AppKit
import Foundation
import Darwin

/// Each invocation is a real NSApplication process. Terminate is deliberately
/// called synchronously inside a main-actor Task: AppKit's terminateLater loop
/// must still deliver retirement completion and exit without another Task.
@MainActor private final class ConsoleTerminationDelegate: NSObject, NSApplicationDelegate {
    let kind: String, folder: URL
    let session: RConsoleSession
    private var workers: [[String: Any]] = []

    init(kind: String, folder: URL, worker: URL, bootstrap: URL) throws {
        self.kind = kind; self.folder = folder
        var executable: (() -> String?)?
        if kind == "startup" {
            let script = folder.appendingPathComponent("held-r-probe")
            let pid = folder.appendingPathComponent("probe-pid.txt").path
            let quoted = "'" + pid.replacingOccurrences(of: "'", with: "'\\''") + "'"
            try Data(("#!/bin/sh\nprintf '%s\\n' \"$$\" > " + quoted + "\nexec /bin/sleep 60\n").utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            executable = { script.path }
        }
        let library = ProcessInfo.processInfo.environment["STATSDIRECT_CONSOLE_PRIVATE_LIBRARY"]
            ?? NSHomeDirectory() + "/Library/Application Support/StatsDirect Viewer/R Library"
        session = RConsoleSession(worker: worker, bootstrap: bootstrap,
                                  workingRoot: folder.appendingPathComponent("Sessions"),
                                  privateLibrary: URL(fileURLWithPath: library),
                                  rExecutable: executable ?? { RRuntime.executable() })
    }
    private func log(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "StatsDirect.RConsoleTermination", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private func wait(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() {
            try require(Date() < deadline, "Timed out waiting for " + description)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    private func run(_ code: String) async throws {
        try require(session.submit(source: code), "Fixture command rejected")
        try await wait("ready") { session.state == "ready" }
    }
    private func rememberWorker() throws {
        guard let directory = session.workingDirectory else { throw CocoaError(.fileNoSuchFile) }
        let lines = try String(contentsOf: directory.appendingPathComponent("quit-info.txt"), encoding: .utf8).split(separator: "\n").map(String.init)
        guard lines.count == 2, let pid = Int32(lines[0]), pid > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let temporary = URL(fileURLWithPath: lines[1]).resolvingSymlinksInPath()
        workers.append(["pid": pid, "temporary": temporary.path,
                        "ipc": temporary.deletingLastPathComponent().deletingLastPathComponent().path,
                        "directory": directory.path])
    }
    private func prepare() async throws {
        session.start()
        if kind == "startup" {
            let pidURL = folder.appendingPathComponent("probe-pid.txt")
            try await wait("held startup probe") { FileManager.default.fileExists(atPath: pidURL.path) }
            let text = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(text), pid > 0 else { throw CocoaError(.fileReadCorruptFile) }
            workers.append(["pid": pid])
        } else {
            try await wait("ready") { session.state == "ready" }
            try await run("writeLines(c(Sys.getpid(), tempdir()), 'quit-info.txt'); writeLines('preserved user content', 'user-file.txt'); shutdownFinalizer <- new.env(); reg.finalizer(shutdownFinalizer, function(e) writeLines('finalized', 'finalizer.txt'), onexit=TRUE)")
            try rememberWorker()
            switch kind {
            case "idle": try await run("pdf('still-open.pdf'); plot(1:3)")
            case "busy", "restart-retired":
                try require(session.submit(source: "writeLines('running', 'busy-ready.txt'); repeat Sys.sleep(0.02)"), "Busy command rejected")
                let file = session.workingDirectory!.appendingPathComponent("busy-ready.txt")
                try await wait("busy R evaluation") { FileManager.default.fileExists(atPath: file.path) }
                if kind == "restart-retired" {
                    session.restart()
                    try require(RConsoleSession.hasPendingShutdowns, "Restart did not retain its predecessor")
                    // Quit immediately, while the predecessor is retiring and
                    // the replacement's asynchronous probe has not yet run.
                }
            case "readline":
                try require(session.submit(source: "answer <- readline('Quit during this question? '); writeLines('wrong', 'after-question.txt')"), "Question rejected")
                try await wait("readline") { session.state == "input" }
            default: throw CocoaError(.fileReadCorruptFile)
            }
        }
        try JSONSerialization.data(withJSONObject: ["case": kind, "workers": workers], options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        try Data(String(Date().timeIntervalSince1970).utf8).write(to: folder.appendingPathComponent("quit-start.txt"))
        log("READY: " + kind)
        NSApplication.shared.terminate(nil)
        // Successful termination never returns from NSApplication.terminate.
        log("FAIL: NSApplication.terminate returned")
        exit(3)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await prepare() }
            catch { log("FAIL: " + error.localizedDescription); exit(1) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.shutdown()
        guard RConsoleSession.hasPendingShutdowns else {
            log("FAIL: expected deferred termination"); return .terminateCancel
        }
        RConsoleSession.whenShutdownComplete { [self] in
            do { try Data("complete".utf8).write(to: folder.appendingPathComponent("drain-complete.txt")) }
            catch { log("FAIL: " + error.localizedDescription); exit(1) }
            log("DRAINED: " + kind)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        do { try Data("terminated".utf8).write(to: folder.appendingPathComponent("application-will-terminate.txt")) }
        catch { log("FAIL: " + error.localizedDescription); exit(1) }
        log("TERMINATED: " + kind)
    }
}

@main enum RConsoleTerminationChecks {
    @MainActor static func main() {
        do {
            guard CommandLine.arguments.count == 5 else { throw CocoaError(.fileReadCorruptFile) }
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let delegate = try ConsoleTerminationDelegate(kind: CommandLine.arguments[1],
                folder: URL(fileURLWithPath: CommandLine.arguments[2]), worker: URL(fileURLWithPath: CommandLine.arguments[3]),
                bootstrap: URL(fileURLWithPath: CommandLine.arguments[4]))
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { FileHandle.standardError.write(Data(("FAIL: " + error.localizedDescription + "\n").utf8)); exit(1) }
    }
}
