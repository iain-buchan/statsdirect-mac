import Cocoa
import WebKit

/// Untrusted report HTML is only ever parsed in this unprivileged, offline WebView.
/// The normal report bridge is installed after sanitized content has been returned.
@MainActor final class ReportImporter: NSObject, WKNavigationDelegate {
    private var web: WKWebView!
    private var continuation: CheckedContinuation<[String: Any], Error>?
    private var keepAlive: ReportImporter?
    private var timeout: DispatchWorkItem?
    private var payload: [String: Any] = [:]
    private var script = ""

    static func convert(html: String, pictures: [LegacyPicture] = [], legacy: Bool = false, tableRows: [[Int]] = [], resources: URL) async throws -> [String: Any] {
        let importer = ReportImporter()
        importer.script = try String(contentsOf: resources.appendingPathComponent("Report/import.js"), encoding: .utf8)
        importer.payload = ["html": html, "pictures": pictures.map(\.payload), "legacy": legacy, "tableRows": tableRows]
        return try await withCheckedThrowingContinuation { importer.start($0) }
    }
    private func start(_ continuation: CheckedContinuation<[String: Any], Error>) {
        self.continuation = continuation; keepAlive = self
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        web.navigationDelegate = self
        let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(LegacyReportError("Report conversion timed out. Try a smaller report."))) }
        timeout = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timer)
        web.loadHTMLString("<!doctype html><html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\"></head><body></body></html>", baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript(script + "\nreturn await StatsDirectReportImport.convert(payload);", arguments: ["payload": payload], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.continuation != nil else { return }
            do {
                guard let json = try result.get() as? String, let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], value["html"] is String else { throw LegacyReportError("The report could not be converted.") }
                self.finish(.success(value))
            } catch { self.finish(.failure(error)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<[String: Any], Error>) {
        guard let completion = continuation else { return }; continuation = nil
        timeout?.cancel(); web?.stopLoading(); web?.navigationDelegate = nil; web = nil
        completion.resume(with: result); keepAlive = nil
    }
}

extension Viewer {
    func openReportURL(_ url: URL) {
        status.stringValue = "Opening \(url.lastPathComponent)…"
        Task { @MainActor in
            do { _ = try await importReport(url) }
            catch { showError("The report could not be opened: " + error.localizedDescription) }
        }
    }

    @discardableResult func importReport(_ url: URL) async throws -> Document {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30_000_000 else { throw LegacyReportError("This report is larger than the 30 MB import limit.") }
        let data = try Data(contentsOf: url)
        let legacy = url.pathExtension.lowercased() == "rtf"
        let source: LegacyReport
        if legacy { source = try LegacyReport.read(data) }
        else {
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw LegacyReportError("The HTML report's text encoding could not be read.") }
            source = LegacyReport(html: html, pictures: [])
        }
        let converted = try await ReportImporter.convert(html: source.html, pictures: source.pictures, legacy: legacy, tableRows: source.tableRows, resources: root)
        guard let convertedHTML = converted["html"] as? String, convertedHTML.utf8.count <= 30_000_000 else { throw LegacyReportError("The converted report is larger than 30 MB. Split it into smaller reports in the Windows application.") }
        let doc = newDocument(kind: "report", title: url.deletingPathExtension().lastPathComponent)
        doc.reportSourceURL = url
        doc.reportImportNotice = legacy ? "Imported from RTF. Save a copy as HTML, PDF or Word; the original RTF is unchanged." : nil
        if (converted["metafiles"] as? Int ?? 0) > 0 {
            doc.reportImportNotice = (doc.reportImportNotice ?? "") + " Windows charts have been converted to SVG; font substitutions and complex drawing effects may differ."
        }
        let warnings = converted["warnings"] as? [String] ?? []
        let warningHTML = warnings.isEmpty ? "" : "<aside class='report-import-warning'><strong>Import notes</strong><ul>" + warnings.map { "<li>\(htmlEscape($0))</li>" }.joined() + "</ul></aside>"
        doc.reportEntries = [ReportEntry(id: UUID().uuidString, title: doc.title, operation: "", body: warningHTML + convertedHTML, rPlan: nil)]
        activeReportID = doc.id; renderReport(doc)
        status.stringValue = "Opened \(url.lastPathComponent)" + (warnings.isEmpty ? "" : " · Review the import notes in the report")
        return doc
    }
}
