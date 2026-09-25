import Cocoa
import WebKit
import UniformTypeIdentifiers

extension Viewer: WKScriptMessageHandler {
    @objc func newWorksheet() {
        worksheetNumber += 1
        let title = worksheetNumber == 1 ? "Untitled" : "Untitled \(worksheetNumber)"
        let doc = newDocument(kind: "grid", title: title, url: root.appendingPathComponent("Grid/index.html"))
        doc.workbookName = title + ".xlsx"
        doc.pendingWorkbook = ["name": title, "formulaCount": 0, "sheets": [["name": "Sheet 1", "rows": 100, "columns": 8, "headerRow": false, "cells": []]]]
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "statsDirectLearn" { handleLearning(message); return }
        if message.name == "statsDirectReport" { handleReport(message); return }
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
