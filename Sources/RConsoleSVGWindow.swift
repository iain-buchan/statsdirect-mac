import Cocoa
import WebKit
import UniformTypeIdentifiers

/// A vector chart remains an SVG image; its markup never becomes active page DOM.
@MainActor final class RConsoleSVGWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let fileURL: URL
    let web: WKWebView
    private(set) var loadError: String?
    var onClose: (() -> Void)?

    init(url: URL, title: String) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "svg",
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 64 * 1024 * 1024 else {
            throw NSError(domain: "StatsDirect.RConsoleSVG", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The chart SVG is unavailable or too large to open."])
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8),
              text.range(of: "<svg(?:\\s|>)", options: .regularExpression) != nil else {
            throw NSError(domain: "StatsDirect.RConsoleSVG", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The chart file does not contain a readable SVG image."])
        }
        fileURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 850, height: 700), configuration: configuration)
        web.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("StatsDirectRConsoleSVG")
        window.title = title
        window.minSize = NSSize(width: 450, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(web)
        window.center()
        super.init(window: window)
        window.delegate = self
        web.navigationDelegate = self

        let html = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;width:100%;height:100%;background:white}body{display:flex;align-items:center;justify-content:center}img{display:block;max-width:100%;max-height:100vh;width:auto;height:auto;object-fit:contain}@media print{body{display:block;height:auto}img{max-width:100%;max-height:100vh}}</style>
        </head><body><img alt="R chart" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
        // SVG image documents cannot run scripts. Also block network/file loads
        // at the WebKit layer, before loading even the inert image wrapper.
        let rules = #"[{"trigger":{"url-filter":"^http:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ws:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file:"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "StatsDirectRConsoleSVGOffline", encodedContentRuleList: rules) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let list, error == nil else {
                    self.loadError = error?.localizedDescription ?? "The offline chart viewer could not be prepared."
                    self.web.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"></head><body>The offline chart viewer could not be prepared. Close this window and try again.</body></html>", baseURL: nil)
                    return
                }
                self.web.configuration.userContentController.add(list)
                self.web.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(url:title:)") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func saveSVG() {
        guard let owner = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "R chart.svg"
        panel.beginSheetModal(for: owner) { [weak self] response in
            guard let self, response == .OK, let target = panel.url else { return }
            do { try Data(contentsOf: self.fileURL).write(to: target, options: .atomic) }
            catch {
                let alert = NSAlert(error: error)
                alert.messageText = "The chart SVG could not be saved."
                alert.beginSheetModal(for: owner)
            }
        }
    }

    func printSVG() {
        guard let owner = window else { return }
        web.printOperation(with: NSPrintInfo.shared).runModal(for: owner, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}
