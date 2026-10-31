import Cocoa
import WebKit
import UniformTypeIdentifiers

private final class RChartWebView: WKWebView {
    var chartMenu: ((NSMenu) -> Void)?
    var zoomKey: ((NSEvent) -> Bool)?
    var zoomChanged: (() -> Void)?
    override var magnification: CGFloat {
        didSet { zoomChanged?() }
    }
    override func setMagnification(_ magnification: CGFloat, centeredAt point: CGPoint) {
        super.setMagnification(magnification, centeredAt: point)
        zoomChanged?()
    }
    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        zoomChanged?()
    }
    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        zoomChanged?()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if zoomKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
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
    private let zoomOutButton = NSButton(title: "−", target: nil, action: nil)
    private let zoomPercentButton = NSButton(title: "100%", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let zoomFitButton = NSButton(title: "Fit", target: nil, action: nil)
    private var zoomObservation: NSKeyValueObservation?
    private var zoomGestureMonitor: Any?
    private var chartReady = false
    private static let minimumZoom: CGFloat = 0.25
    private static let maximumZoom: CGFloat = 8
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
        web.allowsMagnification = true
        web.translatesAutoresizingMaskIntoConstraints = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("StatsDirectRConsoleSVG")
        window.title = title
        window.minSize = NSSize(width: 450, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        web.navigationDelegate = self
        chartWeb.chartMenu = { [weak self] menu in self?.prepareChartMenu(menu) }
        chartWeb.zoomKey = { [weak self] event in self?.handleZoomKey(event) ?? false }
        chartWeb.zoomChanged = { [weak self] in self?.refreshNativeZoom() }
        // Trackpad events can be handled by WebKit's internal content view,
        // bypassing the outer view's responder methods and KVO notifications.
        zoomGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .smartMagnify]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      self.web.bounds.contains(self.web.convert(event.locationInWindow, from: nil)) else { return }
                self.refreshNativeZoom()
                if event.type == .smartMagnify || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateZoomControls() }
                }
            }
            return event
        }
        installZoomControls(in: window)
        zoomObservation = web.observe(\.magnification, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateZoomControls() }
        }

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

    private func installZoomControls(in window: NSWindow) {
        guard let content = window.contentView else { return }
        let label = NSTextField(labelWithString: "Zoom")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let controls: [(NSButton, String, String, Selector)] = [
            (zoomOutButton, "RChartZoomOut", "Zoom out (⌘−)", #selector(zoomOut)),
            (zoomPercentButton, "RChartZoomPercent", "Reset zoom to 100%", #selector(fitChart)),
            (zoomInButton, "RChartZoomIn", "Zoom in (⌘+)", #selector(zoomIn)),
            (zoomFitButton, "RChartZoomFit", "Fit chart to window (⌘0)", #selector(fitChart))
        ]
        for (button, identifier, help, action) in controls {
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
            button.target = self; button.action = action
            button.controlSize = .small; button.bezelStyle = .rounded
            button.toolTip = help; button.setAccessibilityLabel(help)
            button.isEnabled = false
        }
        zoomOutButton.keyEquivalent = "-"; zoomOutButton.keyEquivalentModifierMask = .command
        zoomInButton.keyEquivalent = "+"; zoomInButton.keyEquivalentModifierMask = .command
        zoomFitButton.keyEquivalent = "0"; zoomFitButton.keyEquivalentModifierMask = .command
        zoomPercentButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [label, zoomOutButton, zoomPercentButton, zoomInButton, zoomFitButton, spacer])
        bar.orientation = .horizontal; bar.alignment = .centerY; bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox(); separator.boxType = .separator; separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar); content.addSubview(separator); content.addSubview(web)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            bar.heightAnchor.constraint(equalToConstant: 24),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            separator.heightAnchor.constraint(equalToConstant: 1),
            web.topAnchor.constraint(equalTo: separator.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func handleZoomKey(_ event: NSEvent) -> Bool {
        guard !closed, chartReady,
              event.modifierFlags.intersection([.command, .control, .option]) == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case "+", "=": zoomIn()
        case "-", "_": zoomOut()
        case "0": fitChart()
        default: return false
        }
        return true
    }

    @objc func zoomIn() { setChartZoom(web.magnification * 1.25) }
    @objc func zoomOut() { setChartZoom(web.magnification / 1.25) }
    @objc func fitChart() { setChartZoom(1) }

    private func setChartZoom(_ value: CGFloat) {
        guard !closed, chartReady, value.isFinite else { return }
        web.layoutSubtreeIfNeeded()
        let zoom = min(Self.maximumZoom, max(Self.minimumZoom, value))
        web.setMagnification(zoom, centeredAt: NSPoint(x: web.bounds.midX, y: web.bounds.midY))
        updateZoomControls()
    }

    private func refreshNativeZoom() {
        updateZoomControls()
        // The native gesture completes after its local event monitor fires.
        DispatchQueue.main.async { [weak self] in self?.updateZoomControls() }
    }

    private func updateZoomControls() {
        guard !closed else { return }
        let value = web.magnification
        guard value.isFinite else { return }
        let bounded = min(Self.maximumZoom, max(Self.minimumZoom, value))
        if value != bounded, chartReady { setChartZoom(bounded); return }
        zoomPercentButton.title = "\(Int((bounded * 100).rounded()))%"
        zoomOutButton.isEnabled = chartReady && bounded > Self.minimumZoom
        zoomInButton.isEnabled = chartReady && bounded < Self.maximumZoom
        zoomPercentButton.isEnabled = chartReady; zoomFitButton.isEnabled = chartReady
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed else { return }
        chartReady = loadError == nil
        fitChart()
        updateZoomControls()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }

    func windowWillClose(_ notification: Notification) {
        closed = true; zoomObservation?.invalidate(); zoomObservation = nil
        if let zoomGestureMonitor { NSEvent.removeMonitor(zoomGestureMonitor) }
        zoomGestureMonitor = nil
        onClose?()
    }
}
