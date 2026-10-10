import Cocoa
import WebKit

extension Viewer {
    static let reportFragmentType = NSPasteboard.PasteboardType("com.statsdirect.report-fragment.html")

    func reportClipboardCommand(_ doc: Document, command: String) {
        Task { @MainActor in
            do {
                if try await !transferReportClipboard(doc, command: command) {
                    NSApp.sendAction(NSSelectorFromString(command + ":"), to: nil, from: self)
                }
            } catch { showError("The report content could not be \(command == "paste" ? "pasted" : "copied"): " + error.localizedDescription) }
        }
    }

    // The private HTML representation keeps SVG and exact report formatting;
    // public HTML has Office-compatible pictures/tables and plain text is also
    // available. Cut deletes only after the pasteboard write has succeeded.
    @discardableResult func transferReportClipboard(_ doc: Document, command: String, pasteboard: NSPasteboard = .general) async throws -> Bool {
        guard !doc.web.isLoading else { return true }
        if command == "copy" || command == "cut" {
            guard let value = try await doc.web.evaluateJavaScript("StatsDirectReportEditor.prepareClipboard(\(command == "cut"))") as? [String: Any] else { return false }
            if value["handled"] as? Bool == true { return true }
            guard let html = value["html"] as? String, let text = value["text"] as? String, let token = value["token"] as? String else { return true }
            guard let exported = try await reportScript(doc, method: "clipboard", fragment: html),
                  let office = try JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: String], let publicHTML = office["html"] else { throw LegacyReportError("The selection could not be prepared for the clipboard.") }
            let item = NSPasteboardItem()
            item.setString(html, forType: Self.reportFragmentType)
            item.setString(publicHTML, forType: .html)
            item.setString(text, forType: .string)
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { throw LegacyReportError("The clipboard could not be written. The selected content has not been removed.") }
            if command == "cut" {
                let removed = try await doc.web.evaluateJavaScript("StatsDirectReportEditor.cutPrepared(\(jsString(token)))") as? Bool ?? false
                if removed { status.stringValue = "Cut report selection" }
            } else { status.stringValue = "Copied report selection" }
            return true
        }
        guard command == "paste" else { return false }
        guard let target = try await doc.web.evaluateJavaScript("StatsDirectReportEditor.preparePaste()") as? [String: Any] else { return false }
        guard let token = target["token"] as? String else { return true }
        var html = pasteboard.string(forType: Self.reportFragmentType) ?? pasteboard.string(forType: .html)
        let text = pasteboard.string(forType: .string) ?? ""
        if html == nil, let rtf = pasteboard.data(forType: .rtf) {
            guard rtf.count <= 30_000_000 else { throw LegacyReportError("The clipboard content is too large. Copy a smaller selection.") }
            let source = try LegacyReport.read(rtf)
            let converted = try await ReportImporter.convert(html: source.html, pictures: source.pictures, tableRows: source.tableRows, resources: root)
            html = converted["html"] as? String
        }
        guard (html?.utf8.count ?? 0) <= 30_000_000, text.utf8.count <= 30_000_000 else { throw LegacyReportError("The clipboard content is too large. Copy a smaller selection.") }
        let payload = ["html": html ?? "", "text": text]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let inserted = try await doc.web.evaluateJavaScript("StatsDirectReportEditor.pastePrepared(\(jsString(token)),\(json))") as? Bool ?? false
        if inserted { status.stringValue = "Pasted report content" }
        return true
    }
}
