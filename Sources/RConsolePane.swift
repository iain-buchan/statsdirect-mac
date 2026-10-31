import Cocoa
import WebKit
import PDFKit
import UniformTypeIdentifiers

enum InteractiveRConsolePrototype {
    static var enabled: Bool { Bundle.main.object(forInfoDictionaryKey: "StatsDirectInteractiveConsolePrototype") as? Bool == true }
}

/// A presentation layer only: R executes in its own worker, never in WebKit.
@MainActor final class RConsolePane: NSObject, WKScriptMessageHandler {
    private weak var viewer: Viewer?
    private weak var document: Document?
    let session: RConsoleSession
    private(set) var sourceText: String
    private(set) var outputText = ""
    var scriptName: String
    private var savedSource: String
    private var autoRun: Bool
    private var rendererReady = false
    private var journal: [[String: Any]] = []
    private var journalBytes = 0
    private var sequence = -1
    private var hasExecuted = false
    private struct Plot { let url: URL; let page: Int; let mime: String }
    private var plots: [String: Plot] = [:]
    private var pdfWindows: [String: RConsolePDFWindow] = [:]
    private var svgWindows: [String: RConsoleSVGWindow] = [:]
    var isBusy: Bool { session.isBusy || session.state == "continuation" }
    var hasUnsavedChanges: Bool { sourceText != savedSource }
    var hasWorkspace: Bool { hasExecuted && session.isRunning }

    init(viewer: Viewer, document: Document, script: String, saved: Bool, autoRun: Bool) {
        self.viewer = viewer; self.document = document; sourceText = script
        savedSource = saved ? script : ""; self.autoRun = autoRun; scriptName = document.title
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        session = RConsoleSession(worker: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/RConsoleWorker"),
                                  bootstrap: viewer.root.appendingPathComponent("R/console-bootstrap.R"),
                                  workingRoot: support.appendingPathComponent("StatsDirect Console Prototype/R Sessions"))
        super.init()
        session.onEvent = { [weak self] event in self?.receive(event) }
        document.web.configuration.userContentController.add(self, name: "statsDirectRConsole")
    }

    func load() {
        guard let document, let viewer else { return }
        rendererReady = false
        let url = viewer.root.appendingPathComponent("RConsole/index.html")
        document.initialURL = url
        document.web.loadFileURL(url, allowingReadAccessTo: document.access)
    }
    func focusInput() { document?.web.evaluateJavaScript("window.StatsDirectRConsole?.focusInput()") }
    func shutdown() {
        session.onEvent = nil; session.shutdown()
        let windows = Array(pdfWindows.values); pdfWindows.removeAll()
        for window in windows { window.onClose = nil; window.close() }
        let vectorWindows = Array(svgWindows.values); svgWindows.removeAll()
        for window in vectorWindows { window.onClose = nil; window.close() }
        document?.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectRConsole")
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let document, message.webView === document.web, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], body["protocolVersion"] as? Int == 1,
              let action = body["action"] as? String else { return }
        if action == "ready" {
            rendererReady = true
            if session.generation == 0 { session.start() }
            else {
                for var event in journal {
                    if event["type"] as? String == "inputEcho" { event["origin"] = "replay" }
                    deliver(event)
                }
            }
            return
        }
        guard body["sessionId"] as? String == session.sessionId, body["generation"] as? Int == session.generation else { return }
        switch action {
        case "submit":
            if let text = body["source"] as? String { _ = session.submit(source: text, origin: body["origin"] as? String == "script" ? "script" : "console") }
        case "inputReply":
            if let id = body["requestId"] as? String, let text = body["text"] as? String { session.reply(requestId: id, text: text) }
        case "interrupt": session.interrupt()
        case "restart":
            let alert = NSAlert(); alert.messageText = "Restart R?"
            alert.informativeText = "R variables will be cleared. Your script remains available."
            alert.addButton(withTitle: "Restart R"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: viewer!.window) { [weak self] response in
                guard let self else { return }
                if response == .alertFirstButtonReturn { self.autoRun = false; self.session.restart() }
                else { self.load() } // Restore authoritative state after the cancelled restart.
            }
        case "scriptChanged":
            if let text = body["source"] as? String, text.utf8.count <= 8 * 1024 * 1024 { sourceText = text }
        case "saveScript":
            if let text = body["source"] as? String { sourceText = text }; saveScript()
        case "ai": viewer?.scriptAI.open(document)
        case "help":
            if let viewer, let path = viewer.methodHelpPath(document) { viewer.openHelp(viewer.root.appendingPathComponent(path), title: document.title) }
            else { viewer?.helpLibrary() }
        case "openPlot", "copyPlot":
            guard let id = body["plotId"] as? String, let revision = body["revision"] as? Int,
                  let plot = plots[id + ":" + String(revision)] else {
                forward(["type": "notice", "text": "This chart is no longer available in this console."]); return
            }
            if action == "openPlot" { openChart(plot) }
            else if plot.mime == "image/svg+xml" {
                do {
                    // Retained session assets survive closing/restarting R.
                    // Transfer the original file without rasterizing or
                    // rewriting SVG text, dimensions, glyphs or identifiers.
                    try ReportImageClipboard.writeSVGFile(plot.url, to: .general)
                } catch {
                    forward(["type": "notice", "text": "The SVG chart could not be copied: " + error.localizedDescription])
                    viewer?.showError("The SVG chart could not be copied: " + error.localizedDescription)
                }
            }
            else if let pdf = try? Data(contentsOf: plot.url) {
                let board = NSPasteboard.general; board.clearContents()
                board.setData(pdf, forType: .pdf)
                if let document = PDFDocument(data: pdf), let page = document.page(at: plot.page),
                   let png = preview(page, in: document) { board.setData(png, forType: .png) }
            } else {
                forward(["type": "notice", "text": "The chart PDF could not be read. Its file may have been moved or deleted."])
            }
        default: break
        }
    }
    private func openChart(_ plot: Plot) {
        let key = plot.url.path
        do {
            if plot.mime == "image/svg+xml" {
                if let existing = svgWindows[key] { existing.present(); return }
                let window = try RConsoleSVGWindow(url: plot.url, title: scriptName + " · R chart")
                window.onClose = { [weak self] in self?.svgWindows.removeValue(forKey: key) }
                svgWindows[key] = window; window.present(); return
            }
            if let existing = pdfWindows[key] { existing.present(page: plot.page); return }
            let window = try RConsolePDFWindow(url: plot.url, page: plot.page, title: scriptName + " · R chart")
            window.onClose = { [weak self] in self?.pdfWindows.removeValue(forKey: key) }
            pdfWindows[key] = window
            window.present(page: plot.page)
        } catch {
            forward(["type": "notice", "text": "The chart could not be opened: " + error.localizedDescription])
            viewer?.showError("The chart could not be opened: " + error.localizedDescription)
        }
    }

    private func receive(_ input: [String: Any]) {
        var event = input
        let type = event["type"] as? String ?? ""
        if type == "state", event["interrupting"] as? Bool == true { event["state"] = "interrupting" }
        if type == "session" {
            journal = []; journalBytes = 0; sequence = -1; plots = [:]; outputText = ""; hasExecuted = false
            event["script"] = sourceText
            event["capabilities"] = ["plotMimes": ["image/svg+xml", "application/pdf"], "ai": true, "help": true, "openPlot": true, "copyPlot": true]
        }
        if type == "inputEcho", let text = event["text"] as? String {
            hasExecuted = true
            if event["origin"] as? String == "console", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sourceText += (!sourceText.isEmpty && !sourceText.hasSuffix("\n") ? "\n" : "") + text + (text.hasSuffix("\n") ? "" : "\n")
            }
        }
        if ["output", "inputEcho", "notice"].contains(type), let text = event["text"] as? String {
            outputText = String((outputText + text + (type == "inputEcho" ? "\n" : "")).suffix(1_000_000))
        }
        if type == "plot" { previewPlot(event); return }
        forward(event)
        if type == "state", event["state"] as? String == "ready", autoRun {
            autoRun = false
            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { session.submit(source: sourceText, origin: "script") }
        }
    }
    private func forward(_ input: [String: Any]) {
        var event = input; sequence += 1
        event["seq"] = sequence; event["protocolVersion"] = 1
        event["sessionId"] = session.sessionId; event["generation"] = session.generation
        journal.append(event)
        journalBytes += (try? JSONSerialization.data(withJSONObject: event).count) ?? 0
        // Keep the session envelope for renderer recovery. Full R code is held separately.
        while journalBytes > 12 * 1024 * 1024, journal.count > 2 {
            let removed = journal.remove(at: 1)
            journalBytes -= (try? JSONSerialization.data(withJSONObject: removed).count) ?? 0
        }
        if !journal.isEmpty { journal[0]["script"] = sourceText }
        if rendererReady { deliver(event) }
    }
    private func deliver(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event), let json = String(data: data, encoding: .utf8) else { return }
        document?.web.evaluateJavaScript("window.StatsDirectRConsole?.receive(\(json))")
    }
    private func previewPlot(_ event: [String: Any]) {
        guard let path = event["path"] as? String, let directory = session.workingDirectory else { return }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(directory.resolvingSymlinksInPath().path + "/"),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024 * 1024 else { return }
        let id = event["id"] as? String ?? url.lastPathComponent
        let revision = event["revision"] as? Int ?? 1
        if url.pathExtension.lowercased() == "svg" {
            do {
                let data = try Data(contentsOf: url)
                _ = try ReportImageClipboard.svgMarkup(data)
                plots[id + ":" + String(revision)] = Plot(url: url, page: 0, mime: "image/svg+xml")
                forward(["type": "plot", "plotId": id, "revision": revision, "mime": "image/svg+xml",
                         "preview": "data:image/svg+xml;base64," + data.base64EncodedString(), "label": "R chart"])
            } catch { forward(["type": "notice", "text": "The SVG chart could not be displayed: " + error.localizedDescription]) }
            return
        }
        guard let pdf = PDFDocument(url: url) else { return }
        for index in 0..<min(pdf.pageCount, 20) {
            guard let page = pdf.page(at: index) else { continue }
            guard let png = preview(page, in: pdf) else { continue }
            let pageID = id + ":page-" + String(index + 1)
            plots[pageID + ":" + String(revision)] = Plot(url: url, page: index, mime: "application/pdf")
            forward(["type": "plot", "plotId": pageID, "revision": revision, "mime": "application/pdf",
                     "preview": "data:image/png;base64," + png.base64EncodedString(),
                     "label": "R chart" + (pdf.pageCount > 1 ? " · page \(index + 1) of \(pdf.pageCount)" : "")])
        }
        if pdf.pageCount > 20 { forward(["type": "notice", "text": "Showing the first 20 pages; Open vector PDF includes every page."]) }
    }
    private func preview(_ page: PDFPage, in document: PDFDocument) -> Data? {
        // PDFPage and lazy NSImage drawing do not retain their PDFDocument.
        // Keep it alive until the bitmap has actually been rendered.
        withExtendedLifetime(document) {
            let image = page.thumbnail(of: NSSize(width: 1000, height: 850), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
    }
    func saveScript() {
        guard let viewer else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "r")!]
        panel.nameFieldStringValue = scriptName + ".R"
        panel.beginSheetModal(for: viewer.window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.sourceText.write(to: url, atomically: true, encoding: .utf8)
                self.savedSource = self.sourceText
                if let doc = self.document { self.viewer?.noteDocumentSaved(doc, at: url) }
            } catch { self.viewer?.showError(error.localizedDescription) }
        }
    }
}

extension Viewer {
    @objc func newRConsolePrototype() { makeRConsole() }
    @discardableResult func makeRConsole(script: String = "", title: String? = nil, saved: Bool = false, autoRun: Bool = false) -> Document {
        var number = 1
        while documents.contains(where: { $0.title == "R Console \(number)" }) { number += 1 }
        let doc = newDocument(kind: "r", title: title.map { "R Console: " + $0 } ?? "R Console \(number)")
        let pane = RConsolePane(viewer: self, document: doc, script: script, saved: saved, autoRun: autoRun)
        doc.rConsolePane = pane; pane.load()
        return doc
    }
}
