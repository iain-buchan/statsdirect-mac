import Cocoa
import UniformTypeIdentifiers

/// An independent, persistent R process per tab. Scripts run only on explicit Run.
@MainActor
final class RPane: NSObject, NSTextViewDelegate {
    let view = NSView()
    let editor = NSTextView()
    let console = NSTextView()
    let state = NSTextField(labelWithString: "Starting R…")
    private let runButton = NSButton(title: "Run script  ⌘↩", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop / Reset", target: nil, action: nil)
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var directory: URL?
    private var pending = Data()
    private var generation = UUID()
    private var marker = ""
    private var busy = false
    private var savedScript = ""
    var hasUnsavedChanges: Bool { editor.string != savedScript }
    var isRunning: Bool { busy }

    init(script: String = "") {
        super.init()
        editor.string = script
        savedScript = ""
        editor.delegate = self
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 14, height: 12)
        editor.setAccessibilityLabel("R script editor")
        console.isEditable = false; console.isRichText = false; console.isSelectable = true
        console.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        console.textContainerInset = NSSize(width: 14, height: 12)
        console.setAccessibilityLabel("R console output")
        runButton.target = self; runButton.action = #selector(runScript)
        stopButton.target = self; stopButton.action = #selector(stopSession)
        let save = NSButton(title: "Save script…", target: self, action: #selector(saveScript))
        let clear = NSButton(title: "Clear output", target: self, action: #selector(clearOutput))
        let bar = NSStackView(views: [runButton, stopButton, save, clear]); bar.spacing = 10
        let label = NSTextField(labelWithString: "R script · Variables persist between runs. Stop / Reset clears the session.")
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        let split = NSSplitView(); split.isVertical = false; split.dividerStyle = .thin
        for text in [editor, console] {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; split.addArrangedSubview(scroll)
        }
        for child in [bar, label, split, state] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 32), label.heightAnchor.constraint(equalToConstant: 18), state.heightAnchor.constraint(equalToConstant: 16),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor), label.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            split.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10), split.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), split.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            state.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 8), state.leadingAnchor.constraint(equalTo: bar.leadingAnchor), state.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), state.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            split.arrangedSubviews[0].heightAnchor.constraint(greaterThanOrEqualToConstant: 150), split.arrangedSubviews[1].heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        state.font = .systemFont(ofSize: 11); state.lineBreakMode = .byTruncatingMiddle
        startSession()
    }

    private func startSession() {
        guard process == nil else { return }
        let candidates = ["/Library/Frameworks/R.framework/Resources/bin/Rscript", "/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            state.stringValue = "R was not found. Install R for macOS, then click Run script."
            append("Rscript was not found in the standard macOS installation locations.\n"); return
        }
        let token = UUID(); generation = token; marker = "STATSDIRECT_R_DONE_" + token.uuidString
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect/R Sessions/" + token.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bootstrap = """
            options(warn = 1)
            cat(R.version.string, "\\n", sep = "")
            cat("Working directory: ", getwd(), "\\n", sep = "")
            local({
              input <- file("stdin", open = "r")
              repeat {
                path <- readLines(input, n = 1, warn = FALSE)
                if (!length(path)) break
                tryCatch(source(path, local = .GlobalEnv, echo = TRUE, print.eval = TRUE),
                  error = function(e) cat("Error: ", conditionMessage(e), "\\n", sep = ""),
                  interrupt = function(e) cat("Interrupted\\n"))
                unlink(path)
                cat("\\n\(marker)\\n")
                flush.console()
              }
              close(input)
            })
            """
            let script = folder.appendingPathComponent("session.R"); try bootstrap.write(to: script, atomically: true, encoding: .utf8)
            let child = Process(), incoming = Pipe(), outgoing = Pipe()
            child.executableURL = URL(fileURLWithPath: executable); child.arguments = ["--vanilla", script.path]
            child.currentDirectoryURL = folder
            child.standardInput = incoming; child.standardOutput = outgoing; child.standardError = outgoing
            outgoing.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }; self.consume(data)
                }
            }
            child.terminationHandler = { [weak self] task in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.process = nil; self.busy = false; self.runButton.isEnabled = true; self.stopButton.isEnabled = false
                    self.state.stringValue = "R session ended (\(task.terminationStatus)). Run script starts a fresh session."
                    if !self.pending.isEmpty { self.append(String(decoding: self.pending, as: UTF8.self)); self.pending.removeAll() }
                }
                // Retain files the user's R scripts create in the session working directory.
            }
            try child.run()
            process = child; input = incoming; output = outgoing; directory = folder
            stopButton.isEnabled = true; state.stringValue = "Ready · \(executable)"
        } catch {
            state.stringValue = "Could not start R: \(error.localizedDescription)"
            append(state.stringValue + "\n")
        }
    }
    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                busy = false; runButton.isEnabled = true; state.stringValue = "Ready · R session retained"
            } else { append(line + "\n") }
        }
        // Bound unterminated output while retaining enough bytes for a split protocol marker.
        if pending.count > 65536 { let count = pending.count - 256; append(String(decoding: pending.prefix(count), as: UTF8.self)); pending.removeFirst(count) }
    }
    private func append(_ text: String) {
        console.textStorage?.append(NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.textColor]))
        if let storage = console.textStorage, storage.length > 1_000_000 { storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 800_000)) }
        console.scrollToEndOfDocument(nil)
    }
    @objc func runScript() {
        guard !busy else { return }
        if process == nil { startSession() }
        guard let process, process.isRunning, let input, let directory else { return }
        do {
            let script = directory.appendingPathComponent("run-" + UUID().uuidString + ".R")
            try editor.string.write(to: script, atomically: true, encoding: .utf8)
            busy = true; runButton.isEnabled = false; state.stringValue = "Running R script…"; append("\n── Run script ──\n")
            try input.fileHandleForWriting.write(contentsOf: Data((script.path + "\n").utf8))
        } catch { busy = false; runButton.isEnabled = true; state.stringValue = error.localizedDescription }
    }
    @objc func stopSession() {
        shutdown(); append("\nSession stopped. Variables cleared; Run script starts a new session.\n")
        state.stringValue = "Stopped · Run script starts a fresh R session"
    }
    func shutdown() {
        generation = UUID(); output?.fileHandleForReading.readabilityHandler = nil
        let child = process; process = nil
        try? input?.fileHandleForWriting.close(); input = nil; output = nil; pending.removeAll()
        if let child, child.isRunning { child.terminate() }
        busy = false; runButton.isEnabled = true; stopButton.isEnabled = false
    }
    @objc private func clearOutput() { console.string = "" }
    @objc func saveScript() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "analysis.R"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do { try self.editor.string.write(to: url, atomically: true, encoding: .utf8); self.savedScript = self.editor.string; self.state.stringValue = "Saved \(url.lastPathComponent)" }
            catch { self.state.stringValue = "Save failed: \(error.localizedDescription)" }
        }
    }
}
