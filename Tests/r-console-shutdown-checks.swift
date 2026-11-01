import Foundation
import Darwin

/// Exercises the production session against the real worker, without a WebView.
/// Every path belongs to this fixture; user session folders must never be swept.
@MainActor func rConsoleShutdownChecks(worker: URL, bootstrap: URL, workingRoot: URL,
                                     privateLibrary: URL? = nil) async throws -> Int {
    let fm = FileManager.default
    let root = workingRoot.appendingPathComponent("Shutdown-checks-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let session = RConsoleSession(worker: worker, bootstrap: bootstrap, workingRoot: root, privateLibrary: privateLibrary)
    defer { session.shutdown() }
    var events: [[String: Any]] = [], passed = 0
    session.onEvent = { events.append($0) }
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "StatsDirect.RConsoleShutdown", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: message + " (fixture: " + root.path + ")"]) }
        passed += 1; print("PASS: " + message)
    }
    func wait(_ message: String, timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= end { throw NSError(domain: "StatsDirect.RConsoleShutdown", code: 2,
                                             userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + message + " (fixture: " + root.path + ")"]) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    func ready() async throws { try await wait("the real R worker's prompt", timeout: 20) { session.state == "ready" } }
    func run(_ source: String) async throws {
        try checkSubmission(session.submit(source: source))
        try await ready()
    }
    func checkSubmission(_ accepted: Bool) throws {
        guard accepted else { throw NSError(domain: "StatsDirect.RConsoleShutdown", code: 3,
                                            userInfo: [NSLocalizedDescriptionKey: "The shutdown fixture command was rejected."]) }
    }
    func record() throws -> ShutdownWorkerRecord {
        guard let directory = session.workingDirectory else { throw CocoaError(.fileNoSuchFile) }
        let lines = try String(contentsOf: directory.appendingPathComponent("shutdown-info.txt"), encoding: .utf8).split(separator: "\n").map(String.init)
        guard lines.count == 2, let pid = Int32(lines[0]), pid > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let temporary = URL(fileURLWithPath: lines[1], isDirectory: true).resolvingSymlinksInPath()
        return ShutdownWorkerRecord(pid: pid, directory: directory, temporary: temporary,
                                    ipc: temporary.deletingLastPathComponent().deletingLastPathComponent())
    }
    func ended(_ record: ShutdownWorkerRecord) -> Bool {
        errno = 0
        return Darwin.kill(record.pid, 0) == -1 && errno == ESRCH && !fm.fileExists(atPath: record.ipc.path)
    }
    func start() async throws -> ShutdownWorkerRecord {
        session.start(); try await ready()
        try await run("writeLines(c(as.character(Sys.getpid()), tempdir()), 'shutdown-info.txt'); writeLines('keep user content', 'user-file.txt')")
        return try record()
    }
    func close(_ record: ShutdownWorkerRecord) async throws {
        let before = Date(); session.shutdown()
        try check(Date().timeIntervalSince(before) < 0.2 && session.state == "stopped" && !session.isRunning,
                  "R shutdown retires the session immediately without blocking the main thread")
        var drained = false
        Task { @MainActor in await RConsoleSession.waitForPendingShutdowns(); drained = true }
        try await wait("the application-quit drain and its retired worker's private IPC/R temporary cleanup", timeout: 5) { drained && ended(record) }
    }

    let idle = try await start()
    try check(idle.temporary.path.hasPrefix(fm.temporaryDirectory.resolvingSymlinksInPath().path + "/StatsDirect-RConsole-")
              && idle.temporary.deletingLastPathComponent().lastPathComponent == "Rtmp",
              "each real R worker owns a private temporary root inside its IPC directory")
    try await run("shutdownFinalizer <- new.env(); reg.finalizer(shutdownFinalizer, function(e) { status <- system('printf FINALIZER_RAW_STDOUT; printf FINALIZER_RAW_STDERR >&2'); writeLines(as.character(status), 'shutdown-finalized.txt') }, onexit=TRUE); pdf('shutdown-open.pdf'); plot(1:3)")
    let chart = try fm.contentsOfDirectory(at: idle.directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("console-plot-") && $0.pathExtension == "svg" }
    guard let chart else { throw CocoaError(.fileNoSuchFile) }
    let svg = try Data(contentsOf: chart)
    let external = idle.directory.appendingPathComponent("External R-retained", isDirectory: true)
    try fm.createDirectory(at: external, withIntermediateDirectories: true)
    let externalScript = external.appendingPathComponent("retained.R")
    try Data("plot(1:3)".utf8).write(to: externalScript)
    try await close(idle)
    let finalPDF = try Data(contentsOf: idle.directory.appendingPathComponent("shutdown-open.pdf"))
    try check(try String(contentsOf: idle.directory.appendingPathComponent("shutdown-finalized.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "0"
              && String(decoding: finalPDF.suffix(64), as: UTF8.self).contains("%%EOF"),
              "idle Quit drains raw finalizer output, reaches R exit finalizers and closes the user's still-open PDF device")
    try check(!fm.fileExists(atPath: idle.temporary.path) && !fm.fileExists(atPath: idle.ipc.path)
              && (try Data(contentsOf: chart)) == svg && fm.fileExists(atPath: idle.directory.appendingPathComponent("user-file.txt").path)
              && (try Data(contentsOf: externalScript)) == Data("plot(1:3)".utf8),
              "Quit removes only internal IPC/R temporary files and preserves original charts, user files and external-R snapshots")

    let question = try await start()
    try await run("shutdownFinalizer <- new.env(); reg.finalizer(shutdownFinalizer, function(e) writeLines('finalized', 'shutdown-finalized.txt'), onexit=TRUE)")
    try checkSubmission(session.submit(source: "answer <- readline('Close this question? '); writeLines('must not run', 'after-question.txt')"))
    try await wait("readline") { session.state == "input" }
    try await close(question)
    try check(fm.fileExists(atPath: question.directory.appendingPathComponent("shutdown-finalized.txt").path)
              && !fm.fileExists(atPath: question.directory.appendingPathComponent("after-question.txt").path),
              "Quit unwinds readline without answering it or running subsequent source, then finalizes R")

    let busy = try await start()
    try checkSubmission(session.submit(source: "writeLines('started', 'busy-started.txt'); repeat Sys.sleep(0.02)"))
    try await wait("a running R command") { fm.fileExists(atPath: busy.directory.appendingPathComponent("busy-started.txt").path) }
    let busyClose = Date()
    try await close(busy)
    try check(Date().timeIntervalSince(busyClose) < 4 && fm.fileExists(atPath: busy.directory.appendingPathComponent("user-file.txt").path),
              "an unresponsive busy worker is terminated within the deadline without orphaning its process or deleting user files")

    let retired = try await start()
    try await run("restartSentinel <- TRUE")
    let retiredID = session.sessionId, eventBoundary = events.count
    session.restart(); try await ready()
    try await run("stopifnot(!exists('restartSentinel')); writeLines(c(as.character(Sys.getpid()), tempdir()), 'shutdown-info.txt')")
    let replacement = try record()
    try await wait("the restarted session's predecessor to exit") { ended(retired) }
    try check(session.sessionId != retiredID && replacement.pid != retired.pid
              && events.dropFirst(eventBoundary).allSatisfy { ($0["sessionId"] as? String) == session.sessionId }
              && fm.fileExists(atPath: retired.directory.appendingPathComponent("user-file.txt").path),
              "Restart retires the old worker, ignores its late callbacks and preserves files while starting a fresh workspace")
    try await close(replacement)

    let crashed = try await start()
    _ = Darwin.kill(crashed.pid, SIGKILL)
    try await wait("a failed worker's native exit cleanup") { session.state == "stopped" && !session.isRunning && ended(crashed) }
    try check(fm.fileExists(atPath: crashed.directory.appendingPathComponent("user-file.txt").path)
              && !fm.fileExists(atPath: crashed.temporary.path),
              "unexpected worker failure reaps the worker and cleans internal temporary files without removing session content")

    // An app can quit before its asynchronous R-home probe completes. Its
    // retirement must participate in the same application-termination drain.
    let probePID = root.appendingPathComponent("probe-pid.txt"), probeScript = root.appendingPathComponent("slow-r-probe")
    let quotedPID = "'" + probePID.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    try Data(("#!/bin/sh\nprintf '%s\\n' \"$$\" > " + quotedPID + "\nexec /bin/sleep 60\n").utf8).write(to: probeScript)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: probeScript.path)
    let starting = RConsoleSession(worker: worker, bootstrap: bootstrap, workingRoot: root,
                                   privateLibrary: privateLibrary, rExecutable: { probeScript.path })
    starting.start()
    try await wait("the deliberately held R-home probe to start") { fm.fileExists(atPath: probePID.path) }
    let pidText = try String(contentsOf: probePID, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let probeProcess = Int32(pidText), probeProcess > 0 else { throw CocoaError(.fileReadCorruptFile) }
    starting.shutdown()
    try check(RConsoleSession.hasPendingShutdowns && !starting.isRunning,
              "application Quit tracks a cancelled startup probe even after its session is immediately retired")
    var startupDrained = false
    Task { @MainActor in await RConsoleSession.waitForPendingShutdowns(); startupDrained = true }
    try await wait("the startup probe's application-quit drain") {
        errno = 0
        return startupDrained && Darwin.kill(probeProcess, 0) == -1 && errno == ESRCH
    }
    try check(!RConsoleSession.hasPendingShutdowns,
              "the asynchronous application-quit drain completes only after all retired workers and startup probes are reaped")

    // All workers are gone; only this fixture owns these preserved user files.
    try fm.removeItem(at: root)
    return passed
}

private struct ShutdownWorkerRecord {
    let pid: Int32
    let directory: URL
    let temporary: URL
    let ipc: URL
}
