import Foundation
import Darwin

/// The prototype's R worker has its own process and private control channel.
/// Neither user stdin nor printed R output is interpreted as control traffic.
@MainActor final class RConsoleSession {
    var onEvent: (([String: Any]) -> Void)?
    private(set) var sessionId = ""
    private(set) var generation = 0
    private(set) var state = "stopped"
    private(set) var prompt = "> "
    private(set) var workingDirectory: URL?
    private(set) var inputRequestId: String?
    private(set) var commandId: String?
    var isRunning: Bool { startup != nil || process?.isRunning == true }
    var isBusy: Bool { ["starting", "busy", "input", "interrupting"].contains(state) }

    private let worker: URL
    private let bootstrap: URL
    private let workingRoot: URL
    private let rExecutable: () -> String?
    private var process: Process?
    private var startup: Task<Void, Never>?
    private var homeProbe: RConsoleHomeProbe?
    private var timer: DispatchSourceTimer?
    private var channel: RConsoleFIFOChannel?
    private var eventReader: FileHandle?
    private var ipcDirectory: URL?
    private var rawReaders: [RConsolePipeReader] = []
    private var eventBuffer = Data()
    private var rawBuffers: [String: Data] = [:]
    private var workerSequence = -1
    private var viewSequence = -1
    private var lifecycle = UUID()
    private var interruptRequested = false
    private var inputMaximumBytes = 4094
    private var inputAddToHistory = false
    private var interruptSignal: Int32 = SIGINT
    private var closing = false
    private let maximumEventBytes = 8 * 1024 * 1024

    init(worker: URL, bootstrap: URL, workingRoot: URL,
         rExecutable: @escaping () -> String? = { RRuntime.executable() }) {
        self.worker = worker
        self.bootstrap = bootstrap
        self.workingRoot = workingRoot
        self.rExecutable = rExecutable
    }

    func start() {
        guard !isRunning else { return }
        generation += 1; sessionId = UUID().uuidString; lifecycle = UUID()
        workerSequence = -1; viewSequence = -1; eventBuffer.removeAll(); rawBuffers.removeAll()
        commandId = nil; inputRequestId = nil; interruptRequested = false; closing = false
        inputMaximumBytes = 4094; inputAddToHistory = false
        interruptSignal = SIGINT
        state = "starting"; prompt = "> "
        emit(["type": "session"])
        emit(["type": "state", "state": state, "prompt": prompt])
        guard FileManager.default.isExecutableFile(atPath: worker.path),
              FileManager.default.isReadableFile(atPath: bootstrap.path) else {
            fail("The interactive R prototype worker is missing. Build the console prototype first."); return
        }
        guard let executable = rExecutable() else {
            fail("R is not installed. Use Install R to set it up before starting this console."); return
        }
        let token = lifecycle
        let probe = RConsoleHomeProbe()
        homeProbe = probe
        startup = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.resolveRHome(executable, probe: probe)
            }.value
            guard let self, self.lifecycle == token, !Task.isCancelled else { return }
            self.startup = nil
            self.homeProbe = nil
            switch result {
            case .success(let home):
                do { try self.launch(rHome: home, token: token) }
                catch { self.fail("R could not start: " + error.localizedDescription) }
            case .failure(let error): self.fail(error.message)
            }
        }
    }

    @discardableResult func submit(source: String, origin: String = "console") -> Bool {
        guard ["ready", "continuation"].contains(state), !interruptRequested,
              process?.isRunning == true, let channel else {
            emit(["type": "notice", "text": "Wait for R's input prompt before submitting another command."]); publishCurrentState(); return false
        }
        guard !source.utf8.contains(0) else {
            emit(["type": "notice", "text": "R input cannot contain a NUL character."]); publishCurrentState(); return false
        }
        let id = state == "continuation" ? (commandId ?? UUID().uuidString) : UUID().uuidString
        let payload = id + "\n" + source
        guard payload.utf8.count <= RConsoleFIFOChannel.maximumPayload else {
            emit(["type": "notice", "text": "This console submission exceeds the prototype's 8 MiB input limit."]); publishCurrentState(); return false
        }
        commandId = id; inputRequestId = nil; state = "busy"
        emit(["type": "inputEcho", "text": source, "prompt": prompt, "origin": origin, "commandId": id])
        emit(["type": "state", "state": state, "commandId": id])
        let token = lifecycle
        channel.send(operation: 69, payload: payload) { [weak self] error in
            guard let self, self.lifecycle == token, let error else { return }
            self.fail("R input could not be delivered: " + error)
        }
        return true
    }

    @discardableResult func reply(requestId: String, text: String) -> Bool {
        guard state == "input", !interruptRequested, requestId == inputRequestId,
              process?.isRunning == true, let channel else { publishCurrentState(); return false }
        let payload = requestId + "\n" + text
        guard !text.utf8.contains(0), !text.contains("\n"), !text.contains("\r"), text.utf8.count <= inputMaximumBytes,
              payload.utf8.count <= RConsoleFIFOChannel.maximumPayload else {
            emit(["type": "notice", "text": "R needs a single-line answer of at most \(inputMaximumBytes) UTF-8 bytes, without NUL characters. Please shorten the answer and try again."])
            publishCurrentState(); return false
        }
        inputRequestId = nil; state = "busy"
        emit(["type": "inputEcho", "text": text, "prompt": prompt, "origin": "input", "requestId": requestId])
        emit(["type": "state", "state": state])
        let token = lifecycle
        channel.send(operation: 73, payload: payload) { [weak self] error in
            guard let self, self.lifecycle == token, let error else { return }
            self.fail("The answer could not be delivered to R: " + error)
        }
        return true
    }

    func interrupt() {
        guard let process, process.isRunning, ["busy", "input", "continuation"].contains(state) else { return }
        inputRequestId = nil; interruptRequested = true; state = "busy"
        emit(["type": "state", "state": state, "interrupting": true])
        emit(["type": "notice", "text": "Interrupt requested. R will return to its prompt after the current operation unwinds."])
        // No blank line or EOF is sent: either could answer a question and run
        // code that should have been interrupted. This PID belongs to our worker.
        if process.processIdentifier > 0 { _ = Darwin.kill(process.processIdentifier, interruptSignal) }
    }

    func restart() {
        shutdown(announce: false)
        start()
    }

    func shutdown() { shutdown(announce: true) }

    private func launch(rHome: String, token: UUID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: workingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = workingRoot.appendingPathComponent("Session-" + sessionId, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        workingDirectory = directory
        let ipc = fm.temporaryDirectory.appendingPathComponent("StatsDirect-RConsole-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: ipc, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        ipcDirectory = ipc
        let fifo = ipc.appendingPathComponent("input"), events = ipc.appendingPathComponent("events.ndjson")
        guard Darwin.mkfifo(fifo.path, 0o600) == 0 else { throw posixError("Could not create the private R input channel") }
        guard fm.createFile(atPath: events.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        channel = try RConsoleFIFOChannel(fifo)
        eventReader = try FileHandle(forReadingFrom: events)
        let task = Process(), stdout = Pipe(), stderr = Pipe()
        task.executableURL = worker
        task.arguments = ["--r-home", rHome, "--input", fifo.path, "--events", events.path,
                          "--workdir", directory.path, "--bootstrap", bootstrap.path, "--session", sessionId]
        task.currentDirectoryURL = directory
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = stdout; task.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["R_HOME"] = rHome
        environment["LC_CTYPE"] = "en_US.UTF-8"
        task.environment = environment
        task.terminationHandler = { [weak self] child in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycle == token else { return }
                self.workerExited(child, token: token)
            }
        }
        process = task
        rawReaders = [
            RConsolePipeReader(stdout.fileHandleForReading) { [weak self] bytes in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.lifecycle == token else { return }
                    self.consumeRaw(bytes, stream: "stdout")
                }
            },
            RConsolePipeReader(stderr.fileHandleForReading) { [weak self] bytes in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.lifecycle == token else { return }
                    self.consumeRaw(bytes, stream: "stderr")
                }
            }
        ]
        try task.run()
        try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(30), leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lifecycle == token else { return }
                self.readEvents()
            }
        }
        timer = source; source.resume()
    }

    @discardableResult private func readEvents() -> Bool {
        guard let reader = eventReader, !closing else { return false }
        do {
            let bytes = try reader.read(upToCount: 256 * 1024) ?? Data()
            eventBuffer.append(bytes)
            while let newline = eventBuffer.firstIndex(of: 10) {
                let line = eventBuffer.subdata(in: 0..<newline)
                eventBuffer.removeSubrange(0...newline)
                if line.isEmpty { continue }
                guard line.count <= maximumEventBytes,
                      let event = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    fail("R returned a malformed console event."); return false
                }
                consumeWorker(event)
                if closing || eventReader == nil { return false }
            }
            if eventBuffer.count > maximumEventBytes { fail("An R console event exceeds the prototype's size limit.") }
            return !bytes.isEmpty
        } catch { fail("The private R event channel could not be read: " + error.localizedDescription); return false }
    }

    private func consumeWorker(_ event: [String: Any]) {
        guard event["protocolVersion"] as? Int == 1, event["sessionId"] as? String == sessionId,
              let sequence = event["seq"] as? Int, sequence > workerSequence,
              let type = event["type"] as? String else {
            // Events from a retired generation or duplicate sequence are stale,
            // not fresh input, output or permission to act in this session.
            return
        }
        workerSequence = sequence
        var forwarded = event
        forwarded["backendSeq"] = sequence
        switch type {
        case "state":
            guard let next = event["state"] as? String,
                  ["ready", "busy", "continuation", "input", "stopped"].contains(next) else {
                fail("R returned an unrecognised console state."); return
            }
            if interruptRequested && next != "ready" && next != "stopped" {
                // An input event already in flight cannot undo a Stop request.
                return
            }
            state = next
            if let value = event["prompt"] as? String { prompt = value }
            if let value = event["commandId"] as? String { commandId = value }
            if next == "ready" || next == "stopped" {
                inputRequestId = nil; commandId = nil; interruptRequested = false
            }
        case "inputRequested":
            guard !interruptRequested, let id = event["requestId"] as? String, !id.isEmpty else { return }
            inputRequestId = id; state = "input"
            inputMaximumBytes = min(max(event["maxAnswerBytes"] as? Int ?? 4094, 0), RConsoleFIFOChannel.maximumPayload)
            inputAddToHistory = event["addToHistory"] as? Bool ?? false
            if let value = event["prompt"] as? String { prompt = value }
        case "commandAccepted":
            if let value = event["commandId"] as? String { commandId = value }
        case "commandFinished":
            inputRequestId = nil
            // Completion does not itself advertise ready. Wait for R's state
            // event after the evaluator has unwound and restored its top level.
        case "inputRejected":
            forwarded["type"] = "notice"
            forwarded["text"] = event["reason"] as? String ?? "R did not accept that answer. Please try again."
        case "plot":
            guard let path = event["path"] as? String, let directory = workingDirectory else { return }
            let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard file.path.hasPrefix(root), file.pathExtension.lowercased() == "pdf" else {
                emit(["type": "notice", "text": "A plot outside this console's output folder was not opened."]); return
            }
            forwarded["path"] = file.path
        case "output":
            guard event["text"] is String, ["stdout", "stderr"].contains(event["stream"] as? String ?? "stdout") else { return }
        case "started", "capabilities":
            let capabilities = event["capabilities"] as? [String: Any] ?? event
            if let value = capabilities["interruptSignal"] as? String {
                if value == "SIGUSR1" { interruptSignal = SIGUSR1 }
                else if value == "SIGINT" { interruptSignal = SIGINT }
            }
        case "notice", "exited": break
        default: return
        }
        emit(forwarded)
    }

    private func consumeRaw(_ bytes: Data, stream: String) {
        guard !bytes.isEmpty else { return }
        var data = rawBuffers[stream] ?? Data(); data.append(bytes)
        let count = Self.completeUTF8Prefix(data)
        if count > 0 {
            let text = String(decoding: data.prefix(count), as: UTF8.self)
            emit(["type": "output", "stream": stream, "text": text])
            data.removeFirst(count)
        }
        rawBuffers[stream] = data
    }

    private func workerExited(_ child: Process, token: UUID) {
        guard process === child, lifecycle == token else { return }
        rawReaders.forEach { $0.finish() }
        // Give pending pipe chunks a main-queue turn before the final event.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
            guard let self, self.lifecycle == token, self.process === child else { return }
            self.finishExitedWorker(child, token: token)
        }
    }

    private func finishExitedWorker(_ child: Process, token: UUID) {
        guard lifecycle == token, process === child else { return }
        // Drain bounded chunks over main-queue turns rather than dropping a
        // final burst or freezing the UI while the child is already stopped.
        if readEvents() {
            DispatchQueue.main.async { [weak self] in self?.finishExitedWorker(child, token: token) }
            return
        }
        guard lifecycle == token, process === child else { return }
        for (stream, bytes) in rawBuffers where !bytes.isEmpty {
            emit(["type": "output", "stream": stream, "text": String(decoding: bytes, as: UTF8.self)])
        }
        rawBuffers.removeAll()
        releaseIO()
        process = nil; state = "stopped"; commandId = nil; inputRequestId = nil
        emit(["type": "state", "state": "stopped"])
        emit(["type": "exited", "status": child.terminationStatus, "expected": closing])
    }

    private func shutdown(announce: Bool) {
        let child = process
        lifecycle = UUID(); startup?.cancel(); startup = nil
        homeProbe?.cancel(); homeProbe = nil
        inputRequestId = nil; commandId = nil; interruptRequested = false; closing = true
        releaseIO(); process = nil; state = "stopped"
        if let child, child.isRunning {
            child.terminationHandler = nil
            child.terminate()
            let pid = child.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(700)) {
                if child.isRunning, child.processIdentifier == pid, pid > 0 { _ = Darwin.kill(pid, SIGKILL) }
                child.waitUntilExit()
            }
        }
        if announce { emit(["type": "state", "state": "stopped"]) }
    }

    private func releaseIO() {
        timer?.setEventHandler {}; timer?.cancel(); timer = nil
        channel?.close(); channel = nil
        try? eventReader?.close(); eventReader = nil
        rawReaders.forEach { $0.finish() }; rawReaders.removeAll()
        eventBuffer.removeAll()
        if let directory = ipcDirectory { try? FileManager.default.removeItem(at: directory) }
        ipcDirectory = nil
    }

    private func fail(_ message: String) {
        emit(["type": "notice", "text": message])
        shutdown(announce: true)
    }

    private func emit(_ values: [String: Any]) {
        var event = values
        viewSequence += 1
        event["protocolVersion"] = 1; event["sessionId"] = sessionId
        event["generation"] = generation; event["seq"] = viewSequence
        onEvent?(event)
    }

    /// A rejected browser submission has already put the renderer into its
    /// submitting state. Restore the native prompt, including the original
    /// readline request, so rejection never strands the user or answers R.
    private func publishCurrentState() {
        var event: [String: Any] = ["type": "state", "state": state, "prompt": prompt]
        if let commandId { event["commandId"] = commandId }
        if interruptRequested { event["interrupting"] = true }
        emit(event)
        if state == "input", !interruptRequested, let inputRequestId {
            var request: [String: Any] = ["type": "inputRequested", "requestId": inputRequestId, "prompt": prompt,
                                          "addToHistory": inputAddToHistory, "maxAnswerBytes": inputMaximumBytes]
            if let commandId { request["commandId"] = commandId }
            emit(request)
        }
    }

    private func posixError(_ text: String) -> NSError {
        NSError(domain: "StatsDirect.RConsole", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: text + ": " + String(cString: strerror(errno))])
    }

    private struct HomeFailure: Error, Sendable { let message: String }
    nonisolated private static func resolveRHome(_ executable: String, probe: RConsoleHomeProbe) -> Result<String, HomeFailure> {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["--vanilla", "-e", "cat(R.home())"]
        task.standardInput = FileHandle.nullDevice; task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do {
            guard try probe.start(task) else { return .failure(HomeFailure(message: "R startup was cancelled.")) }
            let timeout = DispatchWorkItem { probe.cancel() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
            let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit(); timeout.cancel()
            let home = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard task.terminationStatus == 0, !home.isEmpty,
                  FileManager.default.fileExists(atPath: URL(fileURLWithPath: home).appendingPathComponent("lib/libR.dylib").path) else {
                return .failure(HomeFailure(message: "The installed R runtime did not provide a usable R home directory."))
            }
            return .success(home)
        } catch { return .failure(HomeFailure(message: "The installed R runtime could not be started: " + error.localizedDescription)) }
    }

    /// Leave a split final UTF-8 scalar for the next pipe chunk. Invalid bytes
    /// elsewhere are displayed as replacement characters, never parsed as code.
    nonisolated private static func completeUTF8Prefix(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let bytes = [UInt8](data.suffix(4))
        var lead = bytes.count - 1
        while lead > 0 && bytes[lead] & 0xC0 == 0x80 { lead -= 1 }
        let first = bytes[lead]
        let expected = first & 0xE0 == 0xC0 ? 2 : first & 0xF0 == 0xE0 ? 3 : first & 0xF8 == 0xF0 ? 4 : 1
        let available = bytes.count - lead
        return expected > available ? data.count - available : data.count
    }
}

/// The FIFO descriptor is nonblocking: an unresponsive R worker cannot block
/// the app's main thread or prevent shutdown. Writes remain frame-atomic in order.
private final class RConsoleHomeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var child: Process?
    func start(_ process: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        child = process
        try process.run()
        return true
    }
    func cancel() {
        lock.lock(); cancelled = true; let process = child; lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(700)) {
            if process.isRunning, process.processIdentifier == pid, pid > 0 { _ = Darwin.kill(pid, SIGKILL) }
        }
    }
}

private final class RConsoleFIFOChannel: @unchecked Sendable {
    static let maximumPayload = 8 * 1024 * 1024
    private let queue = DispatchQueue(label: "com.statsdirect.r-console-input")
    private let lock = NSLock()
    private var descriptor: Int32

    init(_ url: URL) throws {
        descriptor = Darwin.open(url.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    func send(operation: UInt8, payload: String, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        let bytes = Data(payload.utf8)
        guard bytes.count <= Self.maximumPayload else {
            DispatchQueue.main.async { completion("Input frame exceeds 8 MiB.") }; return
        }
        var size = UInt32(bytes.count).bigEndian
        var frame = Data([operation]); withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }; frame.append(bytes)
        let packet = frame
        queue.async { [self] in
            var offset = 0; var failure: String?
            while offset < packet.count {
                lock.lock(); let fd = descriptor
                if fd < 0 { lock.unlock(); failure = "The input channel closed."; break }
                let sent = packet.withUnsafeBytes { buffer in Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), packet.count - offset) }
                let error = errno; lock.unlock()
                if sent > 0 { offset += sent; continue }
                if sent < 0 && (error == EAGAIN || error == EWOULDBLOCK || error == EINTR) {
                    var item = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = Darwin.poll(&item, 1, 50); continue
                }
                failure = String(cString: strerror(error)); break
            }
            DispatchQueue.main.async { completion(failure) }
        }
    }
    func close() {
        lock.lock(); let fd = descriptor; descriptor = -1; lock.unlock()
        if fd >= 0 { _ = Darwin.close(fd) }
    }
    deinit { close() }
}

private final class RConsolePipeReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.statsdirect.r-console-output")
    private let handle: FileHandle
    private let source: DispatchSourceRead
    private let receive: @Sendable (Data) -> Void
    private var finished = false
    init(_ handle: FileHandle, receive: @escaping @Sendable (Data) -> Void) {
        self.handle = handle; self.receive = receive
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { try? handle.close() }
        source.resume()
    }
    private func drain() {
        guard !finished else { return }
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let length = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if length > 0 { receive(Data(bytes.prefix(length))); continue }
            if length == 0 { finished = true; source.cancel(); return }
            if errno == EINTR { continue }
            if errno != EAGAIN && errno != EWOULDBLOCK { finished = true; source.cancel() }
            return
        }
    }
    func finish() {
        queue.async { [self] in
            guard !finished else { return }
            drain(); finished = true; source.cancel()
        }
    }
}
