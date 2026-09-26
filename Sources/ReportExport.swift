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
    func copyReportSelection(_ doc: Document) {
        Task { @MainActor in
            do {
                guard let payload=try await reportScript(doc,method:"clipboard"),
                      let data=payload.data(using:.utf8),
                      let values=try JSONSerialization.jsonObject(with:data) as? [String:String],
                      let html=values["html"],let text=values["text"] else { return }
                let item=NSPasteboardItem();item.setString(html,forType:.html);item.setString(text,forType:.string)
                NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects([item])
                self.status.stringValue="Copied report selection"
            } catch { self.showError("The selection could not be copied: " + error.localizedDescription) }
        }
    }
    func reportScript(_ doc: Document, method: String, format: String = "html") async throws -> String? {
        let script=try String(contentsOf:root.appendingPathComponent("Report/export.js"),encoding:.utf8)
        let options=["title":doc.title,"helpRoot":root.appendingPathComponent("Help",isDirectory:true).absoluteString,"format":format]
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

    func saveReport(_ doc: Document, format: ReportFormat? = nil) {
        guard !doc.fileBusy else { return }
        guard !doc.web.isLoading else { showError("Wait for the report to finish loading, then save it."); return }
        let panel=NSSavePanel()
        panel.title="Save Report"; panel.prompt="Save"
        panel.nameFieldStringValue=doc.title.replacingOccurrences(of:"/",with:"-")
        let picker=ReportFormatPicker(panel:panel,format:format ?? ReportFormat(rawValue:UserDefaults.standard.string(forKey:"reportSaveFormat") ?? "") ?? .html)
        panel.beginSheetModal(for:window) { [picker] response in
            guard response == .OK, let url=panel.url else { return }
            let format=picker.format
            doc.fileBusy=true; self.status.stringValue="Saving \(format.rawValue.uppercased()) report…"
            Task { @MainActor in
                defer { doc.fileBusy=false }
                do {
                    let data=try await self.reportExportData(doc,format:format)
                    try data.write(to:url,options:.atomic)
                    UserDefaults.standard.set(format.rawValue,forKey:"reportSaveFormat")
                    self.status.stringValue="Saved " + url.lastPathComponent
                } catch { self.showError("The report could not be saved: " + error.localizedDescription) }
            }
        }
    }
    func reportExportData(_ doc: Document, format: ReportFormat) async throws -> Data {
        guard doc.kind=="report", !doc.web.isLoading else { throw ReportExportError("Wait for the report to finish loading, then try again.") }
        // An isolated JS world prevents imported HTML from replacing the export code or receiving native messages.
        guard let value=try await reportScript(doc,method:"capture",format:format == .docx ? "docx":"html") else { throw ReportExportError("The report returned no exportable content.") }
        switch format {
        case .html: return Data(value.utf8)
        case .docx:
            guard let data=Data(base64Encoded:value), data.starts(with:[0x50,0x4b]) else { throw ReportExportError("The Word document could not be created.") }
            return data
        case .pdf: return try await ReportPDFPrinter.render(value)
        }
    }
}

/// WebKit's print pipeline paginates tables and retains vector charts. createPDF alone produces a single tall page.
@MainActor private final class ReportPDFPrinter: NSObject, WKNavigationDelegate {
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
