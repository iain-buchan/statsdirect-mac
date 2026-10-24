import Cocoa
import WebKit
import UniformTypeIdentifiers
import PDFKit

private struct ReportExportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription=message }
}

enum ReportFormat: String, CaseIterable {
    case html, pdf, docx
    var label: String { switch self { case .html: return "HTML report (.html)"; case .pdf: return "PDF document (.pdf)"; case .docx: return "Word document (.docx)" } }
    var contentType: UTType { UTType(filenameExtension:rawValue)! }
}

@MainActor private final class ReportFormatPicker: NSObject {
    let panel: NSSavePanel
    let popup = NSPopUpButton(frame:NSRect(x:0,y:0,width:240,height:28))
    var format: ReportFormat { ReportFormat.allCases[popup.indexOfSelectedItem] }
    init(panel: NSSavePanel, format: ReportFormat) {
        self.panel=panel; super.init()
        popup.addItems(withTitles:ReportFormat.allCases.map(\.label))
        popup.selectItem(at:ReportFormat.allCases.firstIndex(of:format)!)
        popup.target=self; popup.action=#selector(changed)
        popup.setAccessibilityLabel("Report format")
        let view=NSStackView(views:[NSTextField(labelWithString:"Format:"),popup])
        view.orientation = .horizontal; view.spacing=12; view.frame=NSRect(x:0,y:0,width:320,height:36)
        panel.accessoryView=view; panel.isExtensionHidden=false
        changed()
    }
    @objc func changed() {
        let name=panel.nameFieldStringValue as NSString
        let stem=ReportFormat.allCases.contains(where:{$0.rawValue==name.pathExtension.lowercased()}) ? name.deletingPathExtension : String(name)
        panel.allowedContentTypes=[format.contentType]
        panel.nameFieldStringValue=stem+"."+format.rawValue
    }
}

extension Viewer {
    func reportScript(_ doc: Document, method: String, format: String = "html", fragment: String? = nil, nativeImage: Bool = false) async throws -> String? {
        let script=try String(contentsOf:root.appendingPathComponent("Report/export.js"),encoding:.utf8)
        var options: [String: Any] = ["title":doc.title,"helpRoot":root.appendingPathComponent("Help",isDirectory:true).absoluteString,"format":format]
        if let fragment { options["fragment"] = fragment }
        if nativeImage { options["nativeImage"] = true }
        return try await withCheckedThrowingContinuation { continuation in
            doc.web.callAsyncJavaScript(script+"\nreturn await StatsDirectReportExport."+method+"(options);",arguments:["options":options],in:nil,in:.defaultClient) { result in
                switch result {
                case .success(let value): continuation.resume(returning:value as? String)
                case .failure(let error):
                    let detail=(error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    continuation.resume(throwing:ReportExportError(detail))
                }
            }
        }
    }

    @objc func exportReportHTML() { if let doc=active, doc.kind=="report" { saveReport(doc,format:.html) } }
    @objc func exportReportPDF() { if let doc=active, doc.kind=="report" { saveReport(doc,format:.pdf) } }
    @objc func exportReportDOCX() { if let doc=active, doc.kind=="report" { saveReport(doc,format:.docx) } }

    /// Save: the report's own HTML file written again without asking once it has one, as the Windows report window saves; a report
    /// without a file, or a save with a format chosen (the Export items), goes through Save As.
    func saveReport(_ doc: Document, format: ReportFormat? = nil, completion: (() -> Void)? = nil) {
        guard !doc.fileBusy else { return }
        guard !doc.web.isLoading else { showError("Wait for the report to finish loading, then save it."); return }
        if format == nil, let url=doc.reportFileURL { writeReport(doc,to:url,format:.html,completion:completion) }
        else { saveReportAs(doc,format:format,completion:completion) }
    }
    /// Save As: the panel offers HTML, and Word and PDF copies; HTML becomes the report's own file, the others leave it where it was.
    func saveReportAs(_ doc: Document, format: ReportFormat? = nil, completion: (() -> Void)? = nil) {
        guard !doc.fileBusy else { return }
        guard !doc.web.isLoading else { showError("Wait for the report to finish loading, then save it."); return }
        let panel=NSSavePanel()
        panel.title="Save Report"; panel.prompt="Save"
        panel.nameFieldStringValue=doc.reportFileURL?.deletingPathExtension().lastPathComponent ?? doc.title.replacingOccurrences(of:"/",with:"-")
        if let folder=doc.reportFileURL?.deletingLastPathComponent() { panel.directoryURL=folder }
        let picker=ReportFormatPicker(panel:panel,format:format ?? .html)
        panel.beginSheetModal(for:window) { [picker] response in
            guard response == .OK, let url=panel.url else { return }
            guard url.pathExtension.lowercased() != "rtf" else { self.showError("Legacy RTF reports can only be read. Choose HTML, PDF or Word for the saved copy."); return }
            self.writeReport(doc,to:url,format:picker.format,completion:completion)
        }
    }
    func writeReport(_ doc: Document, to url: URL, format: ReportFormat, completion: (() -> Void)? = nil) {
        let revision=doc.reportRevision
        doc.fileBusy=true; self.status.stringValue="Saving \(format.rawValue.uppercased()) report…"
        Task { @MainActor in
            defer { doc.fileBusy=false }
            do {
                let data=try await self.reportExportData(doc,format:format)
                try data.write(to:url,options:.atomic)
                if format == .html {
                    self.noteRecentDocument(url); self.noteDocumentSaved(doc,at:url)
                    doc.reportSavedRevision=revision
                }
                self.status.stringValue="Saved " + url.lastPathComponent
                completion?()
            } catch { self.showError("The report could not be saved: " + error.localizedDescription) }
        }
    }
    func reportExportData(_ doc: Document, format: ReportFormat) async throws -> Data {
        guard doc.kind=="report", !doc.web.isLoading else { throw ReportExportError("Wait for the report to finish loading, then try again.") }
        // An isolated JS world prevents imported HTML from replacing the export code or receiving native messages.
        guard let value=try await reportScript(doc,method:"capture",format:format == .docx ? "docx":"html") else { throw ReportExportError("The report returned no exportable content.") }
        switch format {
        case .html:
            let data = Data(await reportMetadata(doc, in: value).utf8)
            guard data.count <= 30_000_000 else { throw ReportExportError("The report and its saved analysis provenance exceed the 30 MB HTML import limit. Export a smaller report or a Jupyter notebook instead.") }
            return data
        case .docx:
            guard let data=Data(base64Encoded:value), data.starts(with:[0x50,0x4b]) else { throw ReportExportError("The Word document could not be created.") }
            return data
        case .pdf: return try await ReportPDFPrinter.render(value)
        }
    }
    /// The saved HTML carries the report's results as the Windows report writes them: a format marker in the head and, before the
    /// body's end, an inert JSON block with each result's id, title, operation, help, markup and the record of its run (the engine's
    /// text as it is), so a reopened report keeps its results apart and can continue them in R. A result's `html` is the markup of its
    /// block in the exported page, with the presentation resolved as the page shows it (what the Windows report takes from each
    /// `.report-body`, and rebuilds the result from when it opens the file); the result's own markup stands in only when the export
    /// has no block for it. `<` is escaped so nothing can end the block.
    func reportMetadata(_ doc: Document, in html: String) async -> String {
        let exported = await exportedBlocks(doc, in: html)
        var records: [String: String] = [:]
        let entries = (doc.reportEntries ?? []).map { entry -> [String: Any] in
            var item: [String: Any] = ["id": entry.id, "title": entry.title, "operation": entry.operation, "helpContextId": 0, "html": exported["result-" + entry.id] ?? entry.editedBody ?? entry.body]
            if let helpPath = entry.helpPath { item["helpPath"] = helpPath }
            if let record = entry.record, (try? JSONSerialization.jsonObject(with: Data(record.utf8))) is [String: Any] {
                let token = "statsdirect-record-" + UUID().uuidString; records[token] = record; item["record"] = token
            }
            return item
        }
        var metadata: [String: Any] = ["version": 1, "entries": entries]
        // This is a JSON string on purpose: its original numeric literals and
        // run provenance survive save/open without a Foundation number rewrite.
        if let provenance = doc.notebookImportProvenance { metadata["notebookImportProvenance"] = provenance }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.withoutEscapingSlashes]) else { return html }
        var block = String(decoding: data, as: UTF8.self)
        for (token, record) in records { block = block.replacingOccurrences(of: "\"" + token + "\"", with: record) }
        block = block.replacingOccurrences(of: "<", with: "\\u003c")
        var page = html
        if let head = page.range(of: "<head[^>]*>", options: .regularExpression) { page.insert(contentsOf: "<meta name=\"statsdirect-report-format\" content=\"1\">", at: head.upperBound) }
        let script = "<script type=\"application/json\" id=\"statsdirect-report-data\">" + block + "</script>"
        if let end = page.range(of: "</body>", options: .backwards) { page.insert(contentsOf: script, at: end.lowerBound) } else { page += script }
        return page
    }
    /// The inner markup of each result's block (`article.report-entry`) in an exported page, by the block's id, parsed by the report's
    /// own web view in the isolated world the export runs in; empty when it cannot be parsed.
    func exportedBlocks(_ doc: Document, in html: String) async -> [String: String] {
        await withCheckedContinuation { continuation in
            doc.web.callAsyncJavaScript("return Object.fromEntries([...new DOMParser().parseFromString(html,'text/html').querySelectorAll('article.report-entry[id]')].map(a=>[a.id,a.innerHTML]))",
                                        arguments: ["html": html], in: nil, in: .defaultClient) { result in
                continuation.resume(returning: ((try? result.get()) as? [String: String]) ?? [:])
            }
        }
    }
}

/// WebKit's print pipeline paginates tables and retains vector charts. createPDF alone produces a single tall page.
@MainActor final class ReportPDFPrinter: NSObject, WKNavigationDelegate {
    private var web: WKWebView!
    private var continuation: CheckedContinuation<Data,Error>?
    private var keepAlive: ReportPDFPrinter?
    private var timeout: DispatchWorkItem?
    private let folder=FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-PDF-"+UUID().uuidString)
    private var file: URL { folder.appendingPathComponent("report.pdf") }
    static func render(_ html: String) async throws -> Data {
        let printer=ReportPDFPrinter()
        return try await withCheckedThrowingContinuation { printer.start(html,$0) }
    }
    private func start(_ html: String, _ continuation: CheckedContinuation<Data,Error>) {
        self.continuation=continuation; keepAlive=self
        do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
        catch { finish(.failure(error)); return }
        let config=WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript=false
        web=WKWebView(frame:NSRect(x:0,y:0,width:698,height:960),configuration:config);web.navigationDelegate=self
        let timer=DispatchWorkItem { [weak self] in self?.finish(.failure(ReportExportError("PDF preparation timed out. Try a smaller report."))) }
        timeout=timer;DispatchQueue.main.asyncAfter(deadline:.now()+60,execute:timer)
        web.loadHTMLString(html,baseURL:nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        let info=NSPrintInfo()
        info.paperSize=NSSize(width:595.28,height:841.89)
        info.topMargin=36;info.bottomMargin=36;info.leftMargin=36;info.rightMargin=36
        info.horizontalPagination = .fit;info.verticalPagination = .automatic
        info.isHorizontallyCentered=false;info.isVerticallyCentered=false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL]=file
        let operation=webView.printOperation(with:info)
        operation.showsPrintPanel=false;operation.showsProgressPanel=false
        // The asynchronous callback retains this renderer until all pages have been written.
        operation.runModal(for:NSApp.mainWindow ?? NSWindow(),delegate:self,didRun:#selector(printed(_:success:contextInfo:)),contextInfo:nil)
    }
    @objc private func printed(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard continuation != nil else { return }
        do {
            guard success else { throw ReportExportError("PDF printing did not complete.") }
            let data=try Data(contentsOf:file)
            guard let pdf=PDFDocument(data:data),pdf.pageCount>0 else { throw ReportExportError("No PDF pages were produced.") }
            finish(.success(data))
        } catch { finish(.failure(error)) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Data,Error>) {
        guard let pending=continuation else { return };continuation=nil
        timeout?.cancel();web?.stopLoading();web?.navigationDelegate=nil
        try? FileManager.default.removeItem(at:folder)
        pending.resume(with:result);keepAlive=nil
    }
}
