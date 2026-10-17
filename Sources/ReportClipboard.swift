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
            guard let value = try await doc.web.evaluateJavaScript("(()=>{const picture=!!StatsDirectReportEditor.selectedPicture(),value=StatsDirectReportEditor.prepareClipboard(\(command == "cut"));return value?{...value,picture}:null;})()") as? [String: Any] else { return false }
            if value["handled"] as? Bool == true { return true }
            guard let html = value["html"] as? String, let text = value["text"] as? String, let token = value["token"] as? String else { return true }
            guard let exported = try await reportScript(doc, method: "clipboard", fragment: html, nativeImage: value["picture"] as? Bool == true),
                  let office = try JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any], let publicHTML = office["html"] as? String else { throw LegacyReportError("The selection could not be prepared for the clipboard.") }
            let item = NSPasteboardItem()
            item.setString(html, forType: Self.reportFragmentType)
            item.setString(publicHTML, forType: .html)
            item.setString(text, forType: .string)
            if let image = office["image"] as? [String: String], let source = image["png"], source.hasPrefix("data:image/png;base64,"),
               let data = Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count))) {
                guard data.count <= ReportImageClipboard.maximumBytes else { throw LegacyReportError("The clipboard picture is too large.") }
                item.setData(data, forType: .png)
                if let svg = image["svg"] {
                    let vector = Data(svg.utf8)
                    guard vector.count <= ReportImageClipboard.maximumBytes else { throw LegacyReportError("The clipboard picture is too large.") }
                    item.setData(vector, forType: ReportImageClipboard.svgTypes[0])
                }
            }
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
        // Image-copy commands may provide raster HTML for Office as well as
        // SVG. Prefer the vector, but retain our exact private rich fragment.
        var html = pasteboard.string(forType: Self.reportFragmentType)
        if html == nil { html = try ReportImageClipboard.svgHTML(from: pasteboard) }
        if html == nil { html = pasteboard.string(forType: .html) }
        let text = pasteboard.string(forType: .string) ?? ""
        if html == nil, let rtf = pasteboard.data(forType: .rtf) {
            guard rtf.count <= 30_000_000 else { throw LegacyReportError("The clipboard content is too large. Copy a smaller selection.") }
            let source = try LegacyReport.read(rtf)
            let converted = try await ReportImporter.convert(html: source.html, pictures: source.pictures, tableRows: source.tableRows, resources: root)
            html = converted["html"] as? String
        }
        if html == nil { html = try ReportImageClipboard.rasterHTML(from: pasteboard) }
        guard (html?.utf8.count ?? 0) <= 30_000_000, text.utf8.count <= 30_000_000 else { throw LegacyReportError("The clipboard content is too large. Copy a smaller selection.") }
        let payload = ["html": html ?? "", "text": text]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let inserted = try await doc.web.evaluateJavaScript("StatsDirectReportEditor.pastePrepared(\(jsString(token)),\(json))") as? Bool ?? false
        if inserted { status.stringValue = "Pasted report content" }
        return true
    }
}
