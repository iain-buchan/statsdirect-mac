import Cocoa
import WebKit
import UniformTypeIdentifiers

private final class RChartWebView: WKWebView {
    var chartMenu: ((NSMenu) -> Void)?
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        chartMenu?(menu)
    }
}

/// A vector chart remains an SVG image; its markup never becomes active page DOM.
@MainActor final class RConsoleSVGWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let fileURL: URL
    let web: WKWebView
    private let originalSVG: Data
    private var closed = false
    private var copyRequest = 0
    private var saveRequest = 0
    private(set) var loadError: String?
    var onClose: (() -> Void)?

    init(url: URL, title: String) throws {
        let data = try RChartExport.svgData(from: url)
        originalSVG = data
        fileURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let chartWeb = RChartWebView(frame: NSRect(x: 0, y: 0, width: 850, height: 700), configuration: configuration)
        web = chartWeb
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
        chartWeb.chartMenu = { [weak self] menu in self?.prepareChartMenu(menu) }

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

    func prepareChartMenu(_ menu: NSMenu) {
        // WebKit's browser image actions cannot open/download this inert data
        // image. Native commands operate on its retained original SVG instead.
        menu.removeAllItems()
        for (title, action) in [
            ("Copy Chart", #selector(copySVG(_:))),
            ("Save Chart as SVG…", #selector(saveSVG)),
            ("Save Chart as PNG…", #selector(savePNG))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func copySVG(_ sender: Any?) {
        guard !closed, let owner = window else { return }
        copyRequest += 1
        let request = copyRequest, changeCount = NSPasteboard.general.changeCount
        Task { @MainActor [weak self, weak owner] in
            guard let self, let owner else { return }
            do {
                let png = try await RChartExport.pngData(fromSVG: self.originalSVG)
                guard !self.closed, self.window === owner, self.copyRequest == request,
                      NSPasteboard.general.changeCount == changeCount, let image = NSImage(data: png) else { return }
                try ReportImageClipboard.write(image: image, svg: self.originalSVG, to: .general)
            } catch {
                guard !self.closed, self.window === owner, self.copyRequest == request,
                      NSPasteboard.general.changeCount == changeCount, owner.attachedSheet == nil else { return }
                let alert = NSAlert(error: error)
                alert.messageText = "The chart SVG could not be copied."
                await alert.beginSheetModal(for: owner)
            }
        }
    }

    @objc func saveSVG() { saveChart(asPNG: false) }
    @objc func savePNG() { saveChart(asPNG: true) }

    private func saveChart(asPNG: Bool) {
        guard !closed, let owner = window, owner.attachedSheet == nil else { return }
        saveRequest += 1
        let request = saveRequest
        Task { @MainActor [weak self, weak owner] in
            guard let self, let owner else { return }
            let data: Data
            do { data = asPNG ? try await RChartExport.pngData(fromSVG: self.originalSVG) : self.originalSVG }
            catch {
                guard !self.closed, self.window === owner, self.saveRequest == request, owner.attachedSheet == nil else { return }
                let alert = NSAlert(error: error)
                alert.messageText = "The chart could not be prepared for export."
                await alert.beginSheetModal(for: owner)
                return
            }
            guard !self.closed, self.window === owner, self.saveRequest == request,
                  owner.isVisible, owner.attachedSheet == nil else { return }
            let panel = NSSavePanel()
            panel.title = asPNG ? "Save Chart as PNG" : "Save Chart as SVG"
            panel.allowedContentTypes = [asPNG ? .png : .svg]
            panel.nameFieldStringValue = asPNG ? "R chart.png" : "R chart.svg"
            panel.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard let self, let owner, !self.closed, self.window === owner, self.saveRequest == request, owner.isVisible,
                      response == .OK, let target = panel.url else { return }
                do { try data.write(to: target, options: .atomic) }
                catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = "The chart could not be saved."
                    alert.beginSheetModal(for: owner)
                }
            }
        }
    }

    @objc func printSVG() {
        guard let owner = window else { return }
        web.printOperation(with: NSPrintInfo.shared).runModal(for: owner, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }

    func windowWillClose(_ notification: Notification) { closed = true; onClose?() }
}
