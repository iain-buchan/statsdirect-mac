import Cocoa
import WebKit
import UniformTypeIdentifiers

struct GridPairedData: Decodable {
    let before: [Double?]
    let after: [Double?]
    let labels: [String]
    let range: String
}

extension Viewer: WKScriptMessageHandler {
    @objc func showGrid() {
        if let existing = documents.first(where: { $0.kind == "grid" }) { tabs.selectTabViewItem(existing.item); return }
        newDocument(kind: "grid", title: "Data grid · PEFR", url: root.appendingPathComponent("Grid/index.html"))
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let web = message.webView, let doc = document(for: web), doc.kind == "grid",
              web.url?.standardizedFileURL == root.appendingPathComponent("Grid/index.html").standardizedFileURL,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "changed": doc.gridDirty = true
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
        running = true; runButton.isEnabled = false
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
            self.calculate(before: input.before.map { $0 ?? .nan }, after: input.after.map { $0 ?? .nan }, labels: input.labels, source: "Data grid · " + input.range)
        }
    }
    func saveGrid(_ doc: Document) {
        doc.web.evaluateJavaScript("window.statsDirectGrid?.csvData()") { value, error in
            guard error == nil, let csv = value as? String else { self.showError("The grid could not be exported."); return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "StatsDirect data.csv"
            panel.beginSheetModal(for: self.window) { response in
                guard response == .OK, let url = panel.url else { return }
                do { try csv.write(to: url, atomically: true, encoding: .utf8); doc.gridDirty = false; self.gridStatus(doc, "Saved " + url.lastPathComponent) }
                catch { self.showError(error.localizedDescription) }
            }
        }
    }
    func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
