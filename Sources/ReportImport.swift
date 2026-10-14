import Cocoa
import WebKit

/// Untrusted report HTML is only ever parsed in this unprivileged, offline WebView.
/// The normal report bridge is installed after sanitized content has been returned.
@MainActor final class ReportImporter: NSObject, WKNavigationDelegate {
    private var web: WKWebView!
    private var continuation: CheckedContinuation<Any, Error>?
    private var keepAlive: ReportImporter?
    private var timeout: DispatchWorkItem?
    private var payload: [String: Any] = [:]
    private var script = ""
    private var reportCSS = ""
    private var tail = ""

    private init(resources: URL) throws {
        script = try String(contentsOf: resources.appendingPathComponent("Report/import.js"), encoding: .utf8)
        reportCSS = try String(contentsOf: resources.appendingPathComponent("Mac/report.css"), encoding: .utf8)
        super.init()
    }

    static func convert(html: String, pictures: [LegacyPicture] = [], legacy: Bool = false, tableRows: [[Int]] = [], resources: URL) async throws -> [String: Any] {
        let importer = try ReportImporter(resources: resources)
        importer.payload = ["html": html, "pictures": pictures.map(\.payload), "legacy": legacy, "tableRows": tableRows]
        importer.tail = "\nreturn await StatsDirectReportImport.convert(payload);"
        let value = try await withCheckedThrowingContinuation { importer.start($0) }
        guard let result = value as? [String: Any], result["html"] is String else { throw LegacyReportError("The report could not be converted.") }
        return result
    }
    /// Each result of a saved report converted on its own, in the order given: the saved page with only that result's block (its
    /// styles then resolve as they did on the page), or, when the page no longer holds the block (a report saved by Windows), the
    /// markup kept with the result in the page's metadata. Each converts as `convert(html:)` does.
    static func convert(page: String, entries: [[String: String]], resources: URL) async throws -> [[String: Any]] {
        let importer = try ReportImporter(resources: resources)
        importer.payload = ["html": page, "entries": entries]
        importer.tail = """

        const page=new DOMParser().parseFromString(payload.html,'text/html'),out=[];
        for(const entry of payload.entries){
          const clone=page.cloneNode(true),blocks=[...clone.querySelectorAll('article.report-entry')],id='result-'+entry.id;
          if(blocks.some(a=>a.id===id)){for(const a of blocks)if(a.id!==id)a.remove();}
          else{clone.body.replaceChildren();const div=clone.createElement('div');div.className='report-body';div.innerHTML=entry.html;clone.body.append(div);}
          out.push(JSON.parse(await StatsDirectReportImport.convert({html:'<!doctype html>'+clone.documentElement.outerHTML,pictures:[],legacy:false,tableRows:[]})));
        }
        return JSON.stringify(out);
        """
        let value = try await withCheckedThrowingContinuation { importer.start($0) }
        guard let results = value as? [[String: Any]], results.count == entries.count, results.allSatisfy({ $0["html"] is String }) else { throw LegacyReportError("The report's results could not be converted.") }
        return results
    }
    private func start(_ continuation: CheckedContinuation<Any, Error>) {
        self.continuation = continuation; keepAlive = self
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        web.navigationDelegate = self
        let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(LegacyReportError("Report conversion timed out. Try a smaller report."))) }
        timeout = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timer)
        web.loadHTMLString("<!doctype html><html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\"><style>\(reportCSS)</style></head><body class='engine-report'></body></html>", baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript(script + tail, arguments: ["payload": payload], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.continuation != nil else { return }
            do {
                guard let json = try result.get() as? String else { throw LegacyReportError("The report could not be converted.") }
                self.finish(.success(try JSONSerialization.jsonObject(with: Data(json.utf8))))
            } catch { self.finish(.failure(error)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Any, Error>) {
        guard let completion = continuation else { return }; continuation = nil
        timeout?.cancel(); web?.stopLoading(); web?.navigationDelegate = nil; web = nil
        completion.resume(with: result); keepAlive = nil
    }
}

extension Viewer {
    func openReportURL(_ url: URL) {
        status.stringValue = "Opening \(url.lastPathComponent)…"
        Task { @MainActor in
            do { let doc = try await importReport(url); didOpenDocument(doc, url: url) }
            catch { showError("The report could not be opened: " + error.localizedDescription) }
        }
    }

    /// The results a saved report's metadata block describes (`statsdirect-report-data`, written by this program and by the Windows
    /// report alike), or nil when the page has no such block.
    static func savedReport(in html: String) -> (entries: [RunRecordR.SavedEntry], unreadableRecords: Int)? {
        guard let pattern = try? NSRegularExpression(pattern: "<script\\s+type=\"application/json\"\\s+id=\"statsdirect-report-data\">(.*?)</script>", options: [.dotMatchesLineSeparators]),
              let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else { return nil }
        return RunRecordR.savedEntries(block: String(html[range]))
    }
    /// A result's help page from a saved report, kept only when it names a page of the bundled help.
    func savedHelpPath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("Help/") else { return nil }
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.appendingPathComponent("Help").standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return path
    }

    @discardableResult func importReport(_ url: URL) async throws -> Document {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30_000_000 else { throw LegacyReportError("This report is larger than the 30 MB import limit.") }
        let data = try Data(contentsOf: url)
        let legacy = url.pathExtension.lowercased() == "rtf"
        let source: LegacyReport
        if legacy { source = try LegacyReport.read(data) }
        else if url.pathExtension.lowercased() == "txt" {
            var text = try CSVFileIO.read(url)
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            source = LegacyReport(html: "<pre style='white-space:pre-wrap'>\(htmlEscape(text))</pre>", pictures: [])
        } else {
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw LegacyReportError("The HTML report's text encoding could not be read.") }
            source = LegacyReport(html: html, pictures: [])
        }
        let title = url.deletingPathExtension().lastPathComponent
        var results: [(title: String, operation: String, body: String, record: String?, helpPath: String?)] = []
        var warnings: [String] = []
        var metafiles = 0
        // A report saved by this program or by Windows carries its results in a metadata block: each is converted on its own and
        // keeps its title, help page and the record of its run, so Continue in R works after reopening. Any other page is one result.
        if !legacy, let saved = Self.savedReport(in: source.html) {
            let converted = try await ReportImporter.convert(page: source.html, entries: saved.entries.map { ["id": $0.id, "html": $0.html] }, resources: root)
            for (entry, result) in zip(saved.entries, converted) {
                results.append((entry.title, entry.operation, result["html"] as? String ?? "", entry.record, savedHelpPath(entry.helpPath)))
                for warning in result["warnings"] as? [String] ?? [] where !warnings.contains(warning) { warnings.append(warning) }
                metafiles += result["metafiles"] as? Int ?? 0
            }
            if saved.unreadableRecords > 0 { warnings.append(saved.unreadableRecords == 1 ? "A result's run record was not readable, so it cannot continue in R." : "\(saved.unreadableRecords) results' run records were not readable, so they cannot continue in R.") }
        } else {
            let converted = try await ReportImporter.convert(html: source.html, pictures: source.pictures, legacy: legacy, tableRows: source.tableRows, resources: root)
            results.append((title, "", converted["html"] as? String ?? "", nil, nil))
            warnings = converted["warnings"] as? [String] ?? []
            metafiles = converted["metafiles"] as? Int ?? 0
        }
        guard results.reduce(0, { $0 + $1.body.utf8.count }) <= 30_000_000 else { throw LegacyReportError("The converted report is larger than 30 MB. Split it into smaller reports in the Windows application.") }
        let doc = newDocument(kind: "report", title: title)
        doc.reportSourceURL = url
        doc.reportImportNotice = legacy ? "Imported from RTF. Save a copy as HTML, PDF or Word; the original RTF is unchanged." : nil
        if metafiles > 0 {
            doc.reportImportNotice = (doc.reportImportNotice ?? "") + " Windows charts have been converted to SVG; font substitutions and complex drawing effects may differ."
        }
        let warningHTML = warnings.isEmpty ? "" : "<aside class='report-import-warning'><strong>Import notes</strong><ul>" + warnings.map { "<li>\(htmlEscape($0))</li>" }.joined() + "</ul></aside>"
        doc.reportEntries = results.enumerated().map { index, result in
            ReportEntry(id: UUID().uuidString, title: result.title, operation: result.operation, body: (index == 0 ? warningHTML : "") + result.body, record: result.record,
                        recipe: result.record != nil && recipeAvailable(for: result.operation), helpPath: result.helpPath)
        }
        activeReportID = doc.id; renderReport(doc)
        status.stringValue = "Opened \(url.lastPathComponent)" + (warnings.isEmpty ? "" : " · Review the import notes in the report")
        return doc
    }
}
