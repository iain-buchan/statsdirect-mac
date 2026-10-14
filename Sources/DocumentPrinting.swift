import Cocoa
import WebKit

/// A separate offline page prints the complete snapshot, not a virtual grid's
/// visible canvas. The native print sheet supplies preview, page ranges and PDF.
@MainActor final class DocumentPrintView: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    init(title: String) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 900), configuration: configuration)
        super.init(); web.navigationDelegate = self
    }
    static func load(html: String, title: String) async throws -> DocumentPrintView {
        let page = DocumentPrintView(title: title)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            page.continuation = continuation
            page.web.loadHTMLString("""
            <!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><style>
            body { color:#000; background:#fff; font:11pt -apple-system, sans-serif; }
            h1 {font-size:14pt;} table {border-collapse:collapse;width:100%;table-layout:fixed;}
            th,td {border:1px solid #999;padding:4px 6px;overflow-wrap:anywhere;white-space:pre-wrap;text-align:left;vertical-align:top;}
            thead {display:table-header-group;} tr {break-inside:avoid;} section+section {break-before:page;}
            pre {font:10pt Menlo,monospace;white-space:pre-wrap;overflow-wrap:anywhere;}
            </style></head><body>\(html)</body></html>
            """, baseURL: nil)
        }
        return page
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.webView(webView, didFail: navigation, withError: error) }
    func print(in window: NSWindow) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        // The operation retains its view for the lifetime of the print sheet.
        web.printOperation(with: info).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
extension Viewer {
    func documentPrintHTML(_ doc: Document) async throws -> String {
        if let pane = doc.rPane { return "<h1>\(htmlEscape(doc.title))</h1><pre>\(htmlEscape(pane.editor.string))</pre>" }
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectGrid"
        let value = try await doc.web.evaluateJavaScript("window.\(bridge).printHTML()")
        guard let html = value as? String else { throw LegacyReportError("The worksheet is still loading.") }
        return html
    }
}
