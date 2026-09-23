import Cocoa
import WebKit
import UniformTypeIdentifiers

struct GridPairedData: Decodable {
    let before: [Double?]
    let after: [Double?]
    let labels: [String]
    let range: String
    let agreement: Bool?
}

extension Viewer: WKScriptMessageHandler {
    @objc func showGrid() {
        if let existing = documents.first(where: { $0.kind == "grid" }) { tabs.selectTabViewItem(existing.item); return }
        newDocument(kind: "grid", title: "Data grid · PEFR", url: root.appendingPathComponent("Grid/index.html"))
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "statsDirectOperation" { handleOperation(message); return }
        if message.name == "statsDirectAnalysis" { handleAnalysis(message); return }
        guard message.name == "statsDirectGrid", message.frameInfo.isMainFrame, let web = message.webView, let doc = document(for: web), doc.kind == "grid",
              web.url?.standardizedFileURL == root.appendingPathComponent("Grid/index.html").standardizedFileURL,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            if doc.pendingCSV != nil { loadPendingCSV(doc) } else { loadPendingWorkbook(doc) }
        case "openCSV": openCSV()
        case "openRData": openRData()
        case "saveRDS": saveRData(doc, format: "rds")
        case "saveRData": saveRData(doc, format: "RData")
        case "openExcel": openExcel()
        case "openExample": openExampleWorkbook()
        case "saveExcel": saveExcel(doc)
        case "changed": doc.gridDirty = true; doc.gridVersion += 1
        case "run": runPairedFromGrid(doc)
        case "save": saveGrid(doc)
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                gridStatus(doc, "Selection copied to clipboard")
            }
        case "paste":
            if let text = NSPasteboard.general.string(forType: .string) {
                web.evaluateJavaScript("window.statsDirectGrid.pasteText(\(jsString(text)))")
            } else { gridStatus(doc, "The clipboard does not contain text to paste.") }
        default: break
        }
    }
    func jsString(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
    func gridStatus(_ doc: Document, _ text: String) {
        doc.web.evaluateJavaScript("window.statsDirectGrid?.setStatus(\(jsString(text)))")
    }
    func runPairedFromGrid(_ doc: Document) {
        guard !running else { return }
        running = true
        doc.web.evaluateJavaScript("JSON.stringify(window.statsDirectGrid?.pairedData())") { value, error in
            guard error == nil, let json = value as? String, let bytes = json.data(using: .utf8) else {
                self.endRun(); self.showError("The data grid is still loading. Please try again."); return
            }
            if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let message = object["error"] as? String {
                self.endRun(); self.showError(message); return
            }
            guard let input = try? JSONDecoder().decode(GridPairedData.self, from: bytes), input.before.count == input.after.count, input.labels.count == 2 else {
                self.endRun(); self.showError("The selected grid columns could not be read."); return
            }
            self.status.stringValue = "Running paired t test from the data grid…"
            self.calculate(before: input.before.map { $0 ?? .nan }, after: input.after.map { $0 ?? .nan }, labels: input.labels, source: "Data grid · " + input.range, agreement: input.agreement ?? false)
        }
    }
    @objc func openCSV() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.openCSVURL(url) }
        }
    }
    func openCSVURL(_ url: URL) {
        status.stringValue = "Opening " + url.lastPathComponent + "…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try CSVFileIO.read(url) }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error): self.showError(error.localizedDescription)
                case .success(let text):
                    let doc = self.newDocument(kind: "grid", title: url.lastPathComponent, url: self.root.appendingPathComponent("Grid/index.html"))
                    doc.workbookName = url.lastPathComponent
                    doc.csvSaveName = url.deletingPathExtension().lastPathComponent + "-edited.csv"
                    doc.pendingCSV = text
                }
            }
        }
    }
    func loadPendingCSV(_ doc: Document) {
        guard let text = doc.pendingCSV else { return }
        doc.web.evaluateJavaScript("window.statsDirectGrid.loadCSV(\(jsString(text)),\(jsString(doc.workbookName)))") { _, error in
            guard self.documents.contains(where: { $0 === doc }) else { return }
            doc.pendingCSV = nil
            if let error {
                self.remove(doc)
                self.showError("CSV import failed: " + error.localizedDescription)
            } else { self.status.stringValue = "Opened " + doc.workbookName }
        }
    }
    func saveGrid(_ doc: Document) {
        guard !doc.fileBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = doc.csvSaveName ?? (doc.workbookName as NSString).deletingPathExtension + ".csv"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let version = doc.gridVersion; doc.fileBusy = true
            // Read after the dialog closes so the snapshot includes the latest edits.
            doc.web.evaluateJavaScript("window.statsDirectGrid.csvSnapshot()") { value, error in
                guard error == nil, let snapshot = value as? [String: Any], let csv = snapshot["text"] as? String else {
                    doc.fileBusy = false; self.showError("The grid could not be saved as CSV. " + (error?.localizedDescription ?? "The worksheet is still loading.")); return
                }
                let completeDocument = snapshot["canSaveDocument"] as? Bool == true && doc.workbookID == nil
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try CSVFileIO.write(csv, to: url) }
                    DispatchQueue.main.async {
                        doc.fileBusy = false
                        switch result {
                        case .failure(let error): self.showError(error.localizedDescription)
                        case .success:
                            if completeDocument {
                                doc.csvSaveName = url.lastPathComponent; doc.rDataFormat = nil
                                if doc.gridVersion == version { doc.gridDirty = false }
                            }
                            self.gridStatus(doc, "Saved current worksheet to " + url.lastPathComponent)
                            self.status.stringValue = "Saved " + url.lastPathComponent
                        }
                    }
                }
            }
        }
    }
    func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
