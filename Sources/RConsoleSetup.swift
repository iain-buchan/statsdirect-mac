import Cocoa
import Darwin

/// Shared first-use preparation; concurrent R tabs do not race package installs.
/// The external R installation and the app's private packages remain separate.
@MainActor final class RConsoleSetup: NSObject {
    static let shared = RConsoleSetup()
    private enum Phase { case probe, install, verify }
    private var callbacks: [UUID: (Result<Void, Error>) -> Void] = [:]
    private var job: UUID?
    private var process: Process?
    private var logHandle: FileHandle?
    private var temporary: URL?
    private var library: URL?
    private var resources: URL?
    private var phase = Phase.probe
    private var timeout: Task<Void, Never>?
    private var panel: NSPanel?
    private var prepared = Set<String>()

    @discardableResult
    func ensureReady(resources: URL, library: URL, completion: @escaping (Result<Void, Error>) -> Void) -> UUID {
        let request = UUID()
        if prepared.contains(library.path), RRuntime.executable() != nil {
            DispatchQueue.main.async { completion(.success(())) }
            return request
        }
        callbacks[request] = completion
        guard job == nil else { panel?.makeKeyAndOrderFront(nil); return request }
        let token = UUID()
        job = token; self.resources = resources; self.library = library
        RInstaller.shared.ensureInstalled { [weak self] installed in
            guard let self, self.job == token else { return }
            guard installed else {
                self.finish(.failure(Self.failure("R setup was postponed. Your script is kept. Choose Restart to try again.")))
                return
            }
            self.launch(.probe, token: token)
        }
        return request
    }

    func cancel(_ request: UUID) {
        callbacks.removeValue(forKey: request)
        if callbacks.isEmpty, job != nil {
            finish(.failure(Self.failure("R setup was cancelled. Choose Restart to try again.")))
        }
    }
    func invalidate(library: URL) { prepared.remove(library.path) }

    private func launch(_ phase: Phase, token: UUID) {
        guard job == token, let library, let resources, let executable = RRuntime.executable() else { return }
        self.phase = phase
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: library, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if temporary == nil {
                let directory = library.appendingPathComponent(".console-setup-" + token.uuidString, isDirectory: true)
                try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                temporary = directory
            }
            guard let temporary else { throw CocoaError(.fileNoSuchFile) }
            let stage = temporary.appendingPathComponent("packages", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            let log = temporary.appendingPathComponent("setup.log")
            fm.createFile(atPath: log.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            logHandle = try FileHandle(forWritingTo: log)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = ["--vanilla", resources.appendingPathComponent("R/console-setup.R").path,
                              phase == .install ? "--install" : "--probe", library.path] + (phase == .install ? [stage.path] : [])
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = logHandle; task.standardError = logHandle
            task.terminationHandler = { [weak self] child in
                let status = child.terminationStatus
                Task { @MainActor [weak self] in self?.completed(status, token: token) }
            }
            process = task
            if phase == .install { showProgress() }
            try task.run()
            timeout?.cancel()
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: phase == .install ? 180_000_000_000 : 30_000_000_000) }
                catch { return }
                guard let self, self.job == token else { return }
                self.finish(.failure(Self.failure("R chart support took too long to prepare. Check your connection and choose Restart to try again.")))
            }
        } catch { finish(.failure(error)) }
    }

    private func completed(_ status: Int32, token: UUID) {
        guard job == token else { return }
        timeout?.cancel(); timeout = nil
        try? logHandle?.close(); logHandle = nil
        process = nil
        let details = logTail()
        if status == 0 {
            if phase == .install { launch(.verify, token: token); return }
            if let library { prepared.insert(library.path) }
            if let marker = details.split(separator: "\n").first(where: { $0.hasPrefix("STATSDIRECT_CONSOLE_READY") }) {
                NSLog("R chart support: %@", String(marker))
            }
            finish(.success(()))
        } else if phase == .probe, status == 23 {
            launch(.install, token: token)
        } else if phase == .probe, status == 24 {
            // An Intel Rscript can run through Rosetta, but its libR cannot be
            // loaded by this arm64 helper. Use the existing guided ARM installer.
            RInstaller.shared.ensureInstalled(requireNativeR: true) { [weak self] installed in
                guard let self, self.job == token else { return }
                if installed { self.launch(.probe, token: token) }
                else { self.finish(.failure(Self.failure("Apple Silicon R setup was postponed. Your script is kept. Choose Restart to try again."))) }
            }
        } else {
            NSLog("R chart setup failed: %@", details)
            finish(.failure(Self.failure("R chart support could not be prepared. Check your connection and choose Restart to try again.")))
        }
    }

    private func logTail() -> String {
        guard let temporary, let handle = try? FileHandle(forReadingFrom: temporary.appendingPathComponent("setup.log")) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    private func showProgress() {
        guard panel == nil else { return }
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 155),
                             styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Preparing R chart support"; window.isReleasedWhenClosed = false
        let detail = NSTextField(wrappingLabelWithString: "Preparing R chart support. You can keep working while this finishes.")
        let progress = NSProgressIndicator(); progress.isIndeterminate = true; progress.startAnimation(nil)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPreparation))
        let stack = NSStackView(views: [detail, progress, cancel])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        panel = window; window.center(); window.makeKeyAndOrderFront(nil)
    }
    @objc private func cancelPreparation() {
        finish(.failure(Self.failure("R chart setup was cancelled. Your script is kept. Choose Restart to try again.")))
    }

    private func finish(_ result: Result<Void, Error>) {
        let child = process, directory = temporary, target = library
        process = nil; job = nil; temporary = nil
        timeout?.cancel(); timeout = nil
        try? logHandle?.close(); logHandle = nil
        panel?.orderOut(nil); panel = nil
        if let child, child.isRunning {
            child.terminationHandler = { _ in Self.cleanup(directory, library: target) }
            child.terminate()
            let pid = child.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning, child.processIdentifier == pid { _ = Darwin.kill(pid, SIGKILL) }
            }
        } else { Self.cleanup(directory, library: target) }
        let waiting = callbacks.values; callbacks.removeAll()
        for completion in waiting { completion(result) }
    }

    nonisolated private static func cleanup(_ directory: URL?, library: URL?) {
        guard let directory else { return }
        let fm = FileManager.default
        if let library, let packages = try? fm.contentsOfDirectory(at: directory.appendingPathComponent("packages"), includingPropertiesForKeys: nil) {
            for backup in packages where backup.lastPathComponent.hasPrefix(".backup-") {
                let target = library.appendingPathComponent(String(backup.lastPathComponent.dropFirst(".backup-".count)))
                if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: backup, to: target) }
            }
        }
        try? fm.removeItem(at: directory)
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "StatsDirect.RConsoleSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
