import Cocoa
import UniformTypeIdentifiers
import PDFKit

/// Remember the text pane even when keyboard focus moves to the More button.
final class ScriptTextView: NSTextView {
    var didFocus: (() -> Void)?
    var copyPicture: ((Int, NSPasteboard) -> Bool)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { didFocus?() }
        return accepted
    }
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        if range.length == 1, copyPicture?(range.location, .general) == true { return }
        super.copy(sender)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard copyPicture != nil, let layout = layoutManager, let container = textContainer, layout.numberOfGlyphs > 0 else { return menu }
        let point = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs else { return menu }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < (textStorage?.length ?? 0), textStorage?.attribute(.attachment, at: index, effectiveRange: nil) != nil,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return menu }
        let result = menu ?? NSMenu()
        let item = NSMenuItem(title: "Copy image", action: #selector(copyPictureItem(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = index
        result.insertItem(item, at: 0)
        return result
    }
    @objc private func copyPictureItem(_ sender: NSMenuItem) {
        if let index = sender.representedObject as? Int { _ = copyPicture?(index, .general) }
    }
}

final class RPaneView: NSView {
    weak var split: NSSplitView?
    weak var toolbar: DocumentToolbar?
    private var positioned = false
    override func layout() {
        super.layout()
        toolbar?.refresh()
        if !positioned, let split, split.bounds.height > 300 {
            positioned = true
            split.setPosition(split.bounds.height * 0.42, ofDividerAt: 0)
        }
    }
}

/// Keep plot previews inside the text column as the output pane is resized.
private final class RPlotAttachment: NSTextAttachment {
    var svgData: Data?
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let availableHeight = max(1, (textContainer?.textView?.enclosingScrollView?.contentView.bounds.height ?? 600) - 72)
        let width = min(900, max(1, lineFrag.width - 2 * (textContainer?.lineFragmentPadding ?? 0)), availableHeight * image.size.width / image.size.height)
        return NSRect(x: 0, y: 0, width: width, height: width * image.size.height / image.size.width)
    }
}

/// An independent, persistent R process per tab. Opening a file never runs it;
/// a report's Continue in R action explicitly runs its generated script once.
@MainActor
final class RPane: NSObject, NSTextViewDelegate {
    let view = RPaneView()
    let editor = ScriptTextView()
    // Plot attachments use TextKit 1's attachmentBounds/layout invalidation API.
    // Build that text system explicitly: TextKit 2 can throw an NSTextRange
    // exception when scrolling newly appended attachments in an inactive tab.
    let console: ScriptTextView = {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        return ScriptTextView(frame: .zero, textContainer: container)
    }()
    let state = NSTextField(labelWithString: "Ready · Choose Run to execute the script")
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop / Reset", target: nil, action: nil)
    private let installButton = NSButton(title: "Install R…", target: nil, action: nil)
    // The folder the session runs in, where the files a script writes go (as the Windows script window's Output folder).
    private let folderButton = NSButton(title: "Output folder", target: nil, action: nil)
    /// The name the script is saved under by Open in R (the window's title, as on Windows: "Script 1_ Paired t test.R").
    var scriptName = "Script"
    /// Told where Save put the script, so the document takes the file's name.
    var scriptSaved: ((URL) -> Void)?
    /// Whether Open in R starts RStudio or R after saving the script (the native checks save alone).
    nonisolated(unsafe) static var opensExternally = true
    /// Where Open in R keeps its files: the program's own folder, as the Windows script window's StatsDirect/R folder.
    static var scriptsFolder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect Viewer/R Scripts", isDirectory: true) }
    private let installer: RInstaller
    private let executable: () -> String?
    private var requestingInstallation = false
    private var runAfterInstallation = false
    private var openExternallyAfterInstallation = false
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var directory: URL?
    private var pending = Data()
    private var generation = UUID()
    private var marker = ""
    private weak var editingFocus: NSTextView?
    private var busy = false
    private var savedScript = ""
    var scriptFileName = "analysis.R"
    private(set) var language = "R"
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languageLabel = NSTextField(labelWithString: "R script · Variables persist between runs. Stop / Reset clears the session.")
    var runManagedScript: ((String, String) -> Void)?
    var cancelManagedScript: (() -> Void)?
    var languageChanged: ((String) -> Void)?
    var showAI: (() -> Void)?
    var showHelp: (() -> Void)?
    private let resources: URL
    private struct PlotStamp: Equatable { let modified: Date; let size: Int }
    private var plotsBefore: [URL: PlotStamp] = [:]
    private var filesBefore: [URL: PlotStamp] = [:]
    var outputFolder: URL? { directory }
    var hasUnsavedChanges: Bool { editor.string != savedScript }
    var isRunning: Bool { busy }

    init(script: String = "", saved: Bool = false, resources: URL = Bundle.main.resourceURL!.appendingPathComponent("Content"), installer: RInstaller? = nil, executable: @escaping () -> String? = { RRuntime.executable() }) {
        self.resources = resources
        self.installer = installer ?? .shared; self.executable = executable
        super.init()
        editor.string = script
        savedScript = saved ? script : ""
        editor.delegate = self
        editor.didFocus = { [weak self] in guard let self else { return }; self.editingFocus = self.editor; self.refreshToolbar() }
        console.didFocus = { [weak self] in guard let self else { return }; self.editingFocus = self.console; self.refreshToolbar() }
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 14, height: 12)
        editor.setAccessibilityLabel("R script editor")
        console.isEditable = false; console.isRichText = true; console.isSelectable = true
        console.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        console.textContainerInset = NSSize(width: 14, height: 12)
        console.setAccessibilityLabel("R output: text and plots")
        console.copyPicture = { [weak self] index, pasteboard in
            guard let self else { return false }
            do { return try self.copyPlot(at: index, to: pasteboard) }
            catch { self.state.stringValue = error.localizedDescription; return true }
        }
        runButton.target = self; runButton.action = #selector(runScript)
        runButton.keyEquivalent = "\r"; runButton.keyEquivalentModifierMask = [.command]
        runButton.toolTip = "Run this script (⌘Return). Results and charts appear below."
        stopButton.target = self; stopButton.action = #selector(stopSession)
        installButton.target = self; installButton.action = #selector(prepareSession)
        installButton.isHidden = true; stopButton.isEnabled = false
        folderButton.target = self; folderButton.action = #selector(openOutputFolder); folderButton.isEnabled = false
        folderButton.toolTip = "Open the folder the script runs in, where the files it writes go"
        let save = NSButton(title: "Save script…", target: self, action: #selector(saveScript))
        save.toolTip = "Save script (⌘S)"
        let openInR = NSButton(title: "Open in R", target: self, action: #selector(openInR))
        openInR.toolTip = "Open the script in RStudio, or run it in a new R application session with results and charts"
        let clear = NSButton(title: "Clear output", target: self, action: #selector(clearOutput))
        let ai = NSButton(title: "AI assistance", target: self, action: #selector(openAI))
        ai.toolTip = "Ask your AI for help with this script. You choose whether to share data and code."
        let help = NSButton(title: "Method Help", target: self, action: #selector(openHelp))
        help.toolTip = "Help for this script’s analysis, or the help library"
        let find = NSButton(title: "Find", target: self, action: #selector(showFind))
        find.toolTip = "Find in the script (⌘F)"
        func style(_ button: NSButton, _ glyph: String, labelled: Bool = false) -> NSButton {
            button.image = DocumentToolbarIcons.image(glyph, resources: resources)
            button.imagePosition = labelled ? .imageLeading : .imageOnly
            button.setAccessibilityLabel(button.title)
            if button.toolTip == nil { button.toolTip = button.title }
            return button
        }
        let editing = [("undo", "Undo", "⌘Z"), ("redo", "Redo", "⇧⌘Z"),
                       ("cut", "Cut", "⌘X"), ("copy", "Copy", "⌘C"), ("paste", "Paste", "⌘V")].map { command, title, shortcut in
            let button = NSButton(title: title, target: self, action: #selector(editScript(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(command); button.toolTip = "\(title) (\(shortcut))"
            return style(button, command)
        }
        languageButton.addItems(withTitles: ["R", "C#", "Visual Basic"])
        languageButton.target = self; languageButton.action = #selector(changeLanguage)
        languageButton.setAccessibilityLabel("Script language")
        let toolbar = DocumentToolbar(items: [
            .init(button: style(save,"save"), priority: 0),
            .init(button: editing[0], priority: 10, groupStart: true), .init(button: editing[1], priority: 10),
            .init(button: editing[2], priority: 10, groupStart: true), .init(button: editing[3], priority: 10), .init(button: editing[4], priority: 10),
            .init(button: style(find,"find"), priority: 20, groupStart: true),
            .init(button: languageButton, priority: 0, groupStart: true),
            .init(button: style(runButton,"run",labelled: true), priority: 0),
            .init(button: style(stopButton,"stop"), priority: 20),
            .init(button: style(clear,"clear"), priority: 70), .init(button: style(folderButton,"folder"), priority: 60),
            .init(button: style(help,"help"), priority: 25, groupStart: true),
            .init(button: style(ai,"ai"), priority: 25),
            .init(button: style(openInR,"rPlus"), priority: 25),
            .init(button: style(installButton,"install",labelled: true), priority: 0)
        ], resources: resources)
        toolbar.validate = { [weak self] in
            guard let self else { return }
            openInR.isEnabled = self.language == "R"
            self.languageButton.isEnabled = !self.busy
            let output = self.editingFocus === self.console
            let selection = (output ? self.console : self.editor).selectedRange().length > 0
            editing[0].isEnabled = !output && self.editor.undoManager?.canUndo == true
            editing[1].isEnabled = !output && self.editor.undoManager?.canRedo == true
            editing[2].isEnabled = !output && selection
            editing[3].isEnabled = selection
            editing[4].isEnabled = !output && NSPasteboard.general.availableType(from: [.string]) != nil
        }
        view.toolbar = toolbar
        NotificationCenter.default.addObserver(self, selector: #selector(refreshToolbar), name: NSTextView.didChangeSelectionNotification, object: editor)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshToolbar), name: NSTextView.didChangeSelectionNotification, object: console)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshToolbar), name: NSApplication.didBecomeActiveNotification, object: nil)
        let label = languageLabel
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        let split = NSSplitView(); split.isVertical = false; split.dividerStyle = .thin
        view.split = split
        for text in [editor, console] {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; split.addArrangedSubview(scroll)
            if text === console {
                scroll.contentView.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(outputResized), name: NSView.frameDidChangeNotification, object: scroll.contentView)
            }
        }
        for child in [toolbar, label, split, state] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            toolbar.heightAnchor.constraint(equalToConstant: 40), label.heightAnchor.constraint(equalToConstant: 18), state.heightAnchor.constraint(equalToConstant: 16),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), label.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), label.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            split.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10), split.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), split.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            state.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 8), state.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), state.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), state.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            split.arrangedSubviews[0].heightAnchor.constraint(greaterThanOrEqualToConstant: 150), split.arrangedSubviews[1].heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        state.font = .systemFont(ofSize: 11); state.lineBreakMode = .byTruncatingMiddle
        showReadyState()
    }

    private func showReadyState() {
        // Opening a script is passive, including C#/VB documents. Start R only
        // for an explicit Run, setup request or external handoff.
        installButton.isHidden = language != "R" || executable() != nil
        state.stringValue = installButton.isHidden ? "Ready · Choose Run to execute the script" : "R is not installed. Choose Install R to download and set it up."
        refreshToolbar()
    }

    @objc private func refreshToolbar() { view.toolbar?.refresh() }
    func textDidChange(_ notification: Notification) { refreshToolbar() }
    @objc func showFind() {
        view.window?.makeFirstResponder(editor)
        let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.performFindPanelAction(item)
    }
    @objc private func openHelp() { showHelp?() }
    @objc private func openAI() { showAI?() }

    @objc private func editScript(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        // A selection in read-only output must never cut or replace an old,
        // unrelated selection left behind in the script editor.
        if editingFocus === console && ["undo", "redo", "cut", "paste"].contains(command) { return }
        // Copy can also copy selected results; editing always targets the script.
        let target = command == "copy" && editingFocus === console ? console : editor
        view.window?.makeFirstResponder(target)
        switch command {
        case "undo": target.undoManager?.undo()
        case "redo": target.undoManager?.redo()
        case "cut": target.cut(sender)
        case "copy": target.copy(sender)
        case "paste": target.paste(sender)
        default: break
        }
        refreshToolbar()
    }

    private func startSession() {
        guard process == nil else { return }
        guard let executable = executable() else {
            installButton.isHidden = false; stopButton.isEnabled = false
            view.needsLayout = true
            state.stringValue = "R is not installed. Choose Install R to download and set it up."
            return
        }
        installButton.isHidden = true
        view.needsLayout = true
        let token = UUID(); generation = token; marker = "STATSDIRECT_R_DONE_" + token.uuidString
        do {
            let folder = try workingDirectory(fresh: true)
            let script = resources.appendingPathComponent("R/session.R")
            guard FileManager.default.isReadableFile(atPath: script.path) else { throw CocoaError(.fileReadNoSuchFile) }
            let child = Process(), incoming = Pipe(), outgoing = Pipe()
            child.executableURL = URL(fileURLWithPath: executable); child.arguments = ["--vanilla", script.path, marker]
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
                    self.showNewPlots(); self.listWrittenFiles()
                }
                // Retain files the user's R scripts create in the session working directory.
            }
            try child.run()
            process = child; input = incoming; output = outgoing; directory = folder
            stopButton.isEnabled = true; folderButton.isEnabled = true; state.stringValue = "Ready · \(executable)"
        } catch {
            state.stringValue = "Could not start R: \(error.localizedDescription)"
            append(state.stringValue + "\n")
        }
    }
    @objc func prepareSession() {
        guard language == "R" else { return }
        if executable() == nil { requestInstallation(run: false) }
        else { startSession() }
    }
    private func requestInstallation(run: Bool, openExternally: Bool = false) {
        runAfterInstallation = runAfterInstallation || run
        openExternallyAfterInstallation = openExternallyAfterInstallation || openExternally
        guard !requestingInstallation else { return }
        requestingInstallation = true; installButton.isEnabled = false
        let request = generation
        state.stringValue = "R setup is open. Your script will be kept here."
        installer.ensureInstalled { [weak self] installed in
            guard let self, self.generation == request else { return }
            let run = self.runAfterInstallation
            let external = self.openExternallyAfterInstallation
            self.requestingInstallation = false; self.runAfterInstallation = false; self.openExternallyAfterInstallation = false; self.installButton.isEnabled = true
            if installed { self.startSession(); if run { self.runScript() }; if external { self.openInR() } }
            else { self.state.stringValue = "R setup was postponed. Choose Install R when you are ready." }
        }
    }
    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                showNewPlots(); listWrittenFiles()
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
    @objc private func outputResized() {
        guard let storage = console.textStorage, storage.containsAttachments else { return }
        console.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        console.needsDisplay = true
    }
    // Every file in the session folder with its stamp; the scripts the pane writes for each run are not the user's files.
    private func sessionFiles() -> [URL: PlotStamp] {
        guard let directory, let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [:] }
        var result: [URL: PlotStamp] = [:]
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]), values.isRegularFile == true,
                  !(url.lastPathComponent.hasPrefix("run-") && url.pathExtension == "R") else { continue }
            result[url] = PlotStamp(modified: values.contentModificationDate ?? .distantPast, size: values.fileSize ?? 0)
        }
        return result
    }
    private func plotFiles() -> [URL: PlotStamp] {
        sessionFiles().filter { ["svg", "pdf", "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff"].contains($0.key.pathExtension.lowercased()) }
    }
    /// The charts the last run drew in the pane: a chart's caption is its link, so the list of files written names the others only.
    private var chartsShown: Set<URL> = []
    // The other files a run wrote as links the user can open, as the Windows script window lists them; nothing when there are none.
    private func listWrittenFiles() {
        let files = sessionFiles()
        let written = files.keys.filter { files[$0] != filesBefore[$0] && !chartsShown.contains($0) }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        filesBefore = files; chartsShown = []
        guard !written.isEmpty, let storage = console.textStorage else { return }
        append("\nFiles written, to open with a click:\n")
        for url in written { storage.append(NSAttributedString(string: url.lastPathComponent + "\n", attributes: [.link: url, .font: NSFont.systemFont(ofSize: 12)])) }
        console.scrollToEndOfDocument(nil)
    }
    @objc private func openOutputFolder() {
        guard let directory else { return }
        NSWorkspace.shared.open(directory)
    }
    private func showNewPlots() {
        let files = plotFiles()
        let changed = files.keys.filter { files[$0] != plotsBefore[$0] }.sorted {
            let left = files[$0]!.modified, right = files[$1]!.modified
            return left == right ? $0.path < $1.path : left < right
        }
        chartsShown = []
        for url in changed {
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    guard bounds.width > 0, bounds.height > 0 else { continue }
                    let scale = 1800 / max(bounds.width, bounds.height)
                    let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
                    appendPlot(page.thumbnail(of: size, for: .mediaBox), url: url, label: pdf.pageCount > 1 ? "\(url.lastPathComponent) · page \(index + 1)" : url.lastPathComponent)
                }
            } else if let image = NSImage(contentsOf: url), image.size.width > 0 {   // an SVG as it is, a raster file as an image
                appendPlot(image, url: url, label: url.lastPathComponent)
            }
        }
        plotsBefore = files
    }
    /// A chart in the pane under its caption, which names the file and is its one link (as the Windows script window shows a chart).
    private func appendPlot(_ image: NSImage, url: URL, label: String) {
        guard let storage = console.textStorage else { return }
        append("\n")
        storage.append(NSAttributedString(string: "Chart: \(label)\n", attributes: [.link: url, .font: NSFont.systemFont(ofSize: 12)]))
        let attachment = RPlotAttachment(); attachment.image = image
        // Snapshot the vector bytes now: a later R run may overwrite this file.
        if url.pathExtension.lowercased() == "svg" { attachment.svgData = try? Data(contentsOf: url) }
        storage.append(NSAttributedString(attachment: attachment))
        append("\n")
        chartsShown.insert(url)
        console.scrollToEndOfDocument(nil)
    }
    @discardableResult func copyPlot(at index: Int, to pasteboard: NSPasteboard) throws -> Bool {
        guard let storage = console.textStorage, index >= 0, index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? RPlotAttachment,
              let image = attachment.image else { return false }
        try ReportImageClipboard.write(image: image, svg: attachment.svgData, to: pasteboard)
        return true
    }
    @objc func runScript() {
        if language != "R" {
            guard !busy else { return }
            busy = true; stopButton.isEnabled = true; state.stringValue = "Running script…"; refreshToolbar()
            runManagedScript?(editor.string, language); return
        }
        // Run while a run is going stops that run and runs the edited script, as the Windows script window does
        // (a dropped click looked like the unedited answers); the session starts afresh.
        if busy { shutdown(); append("\nRun stopped; the edited script runs in a fresh R session.\n") }
        if executable() == nil { requestInstallation(run: true); return }
        if process == nil { startSession() }
        guard let process, process.isRunning, let input, let directory else { return }
        do {
            filesBefore = sessionFiles(); plotsBefore = plotFiles()
            let script = directory.appendingPathComponent("run-" + UUID().uuidString + ".R")
            try editor.string.write(to: script, atomically: true, encoding: .utf8)
            busy = true; state.stringValue = "Running R script… Run script again stops this run and runs the edited script"; append("\n── Run script ──\n")
            try input.fileHandleForWriting.write(contentsOf: Data((script.path + "\n").utf8))
        } catch { busy = false; runButton.isEnabled = true; state.stringValue = error.localizedDescription }
    }
    @objc func stopSession() {
        if language != "R" { cancelManagedScript?(); state.stringValue = "Cancelling at the next engine checkpoint…"; return }
        shutdown(); append("\nSession stopped. Variables cleared; Run script starts a new session.\n")
        state.stringValue = "Stopped · Run script starts a fresh R session"
    }
    func shutdown() {
        if language != "R", busy { cancelManagedScript?() }
        generation = UUID(); output?.fileHandleForReading.readabilityHandler = nil
        requestingInstallation = false; runAfterInstallation = false; openExternallyAfterInstallation = false; installButton.isEnabled = true
        // Keep this tab's files accessible through Output folder after Reset.
        let child = process; process = nil
        try? input?.fileHandleForWriting.close(); input = nil; output = nil; pending.removeAll()
        if let child, child.isRunning { child.terminate() }
        busy = false; runButton.isEnabled = true; stopButton.isEnabled = false
    }
    @objc private func clearOutput() { console.string = "" }
    private func workingDirectory(fresh: Bool = false) throws -> URL {
        if let directory, !fresh { return directory }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect Viewer/R Sessions/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        return folder
    }
    /// This copy lives beside this session's output; it never overwrites a user's
    /// opened file or another tab's script and does not mark unsaved edits saved.
    func writeExternalScript() throws -> URL {
        let url = try workingDirectory().appendingPathComponent(scriptFileName)
        try editor.string.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    /// Open in R, as the Windows script window offers it: the script saved as an R file named after the window in the program's R Scripts
    /// folder, then opened in RStudio when installed, otherwise run in a new R.app session.
    @discardableResult @objc func openInR() -> URL? {
        guard language == "R" else { return nil }
        let folder = Self.scriptsFolder
        let name = scriptName.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        let url = folder.appendingPathComponent((name.isEmpty ? "Script" : name) + ".R")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try editor.string.write(to: url, atomically: true, encoding: .utf8); savedScript = editor.string
        } catch { state.stringValue = "Open in R failed: \(error.localizedDescription)"; return nil }
        guard Self.opensExternally else { state.stringValue = "Saved \(url.lastPathComponent) in R Scripts"; return url }
        guard executable() != nil else { requestInstallation(run: false, openExternally: true); return url }
        let workspace = NSWorkspace.shared
        let completed: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.state.stringValue = "Open in R failed: \(error.localizedDescription). Your script is saved in R Scripts." }
                else { self.state.stringValue = "Opened \(url.lastPathComponent) in \(application?.localizedName ?? "R")" }
            }
        }
        if let rstudio = workspace.urlForApplication(withBundleIdentifier: "org.rstudio.RStudio") ?? workspace.urlForApplication(withBundleIdentifier: "com.rstudio.desktop") {
            state.stringValue = "Opening script in RStudio…"
            workspace.open([url], withApplicationAt: rstudio, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completed)
        } else if let r = workspace.urlForApplication(withBundleIdentifier: "org.R-project.R") {
            do {
                let directory = try workingDirectory().appendingPathComponent("External R-" + UUID().uuidString, isDirectory: true)
                let session = try RExternalSession(script: url, directory: directory)
                state.stringValue = "Starting R and running the script…"
                // Supplying a fresh directory also prevents R.app restoring a
                // workspace from its default working directory at GUI startup.
                workspace.open([session.directory], withApplicationAt: r, configuration: session.configuration(), completionHandler: completed)
            } catch { state.stringValue = "Open in R failed: \(error.localizedDescription)" }
        }
        else { state.stringValue = "Saved \(url.lastPathComponent) in R Scripts; install RStudio or R to open it" }
        return url
    }
    @objc private func changeLanguage() {
        setLanguage(["R", "CSharp", "VB"][languageButton.indexOfSelectedItem])
    }
    func setLanguage(_ value: String) {
        guard !busy, ["R", "CSharp", "VB"].contains(value) else { return }
        if value != language { shutdown() }
        language = value; languageChanged?(value); languageButton.selectItem(at: ["R", "CSharp", "VB"].firstIndex(of: value)!)
        scriptFileName = (scriptFileName as NSString).deletingPathExtension + (value == "R" ? ".R" : value == "VB" ? ".vb" : ".cs")
        languageLabel.stringValue = value == "R" ? "R script · Variables persist between runs. Stop / Reset clears the session." : "\(languageButton.titleOfSelectedItem ?? value) · StatsDirect engine host available as host. Stop cancels at the next engine checkpoint."
        editor.setAccessibilityLabel("\(value) script editor")
        console.setAccessibilityLabel(value == "R" ? "R output: text and plots" : "\(value) script output")
        showReadyState()
    }
    func finishManagedScript(_ text: String, error: String? = nil, cancelled: Bool = false) {
        append("\n── Run script ──\n" + text + (error.map { "\n" + $0 + "\n" } ?? ""))
        busy = false; stopButton.isEnabled = false
        state.stringValue = cancelled ? "Script cancelled" : error == nil ? "Script complete" : "Script failed"
        refreshToolbar()
    }
    @objc func saveScript() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = scriptFileName
        panel.allowedContentTypes = [UTType(filenameExtension: language == "CSharp" ? "cs" : language == "VB" ? "vb" : "R") ?? .plainText]
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do { try self.editor.string.write(to: url, atomically: true, encoding: .utf8); self.savedScript = self.editor.string; self.scriptFileName = url.lastPathComponent; self.state.stringValue = "Saved \(url.lastPathComponent)"; (NSApp.delegate as? Viewer)?.noteRecentDocument(url); self.scriptSaved?(url) }
            catch { self.state.stringValue = "Save failed: \(error.localizedDescription)" }
        }
    }
}
