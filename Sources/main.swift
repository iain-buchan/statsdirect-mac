import Cocoa
import WebKit
import UniformTypeIdentifiers

@MainActor
final class Viewer: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var status: NSTextField!
    var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Content") }
    var allowedRoot: URL!
    var testStage = 0
    let test = CommandLine.arguments.contains("--self-test")
    var testDirectory: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIEWER_TEST_DIR"] ?? NSTemporaryDirectory()) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "StatsDirect · Reports & Help"
        window.minSize = NSSize(width: 720, height: 480)
        let container = NSView()
        window.contentView = container
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        for (title, action) in [("Report example", #selector(report)), ("Help library", #selector(help)), ("Open HTML…", #selector(openFile)), ("Back", #selector(back)), ("Forward", #selector(forward)), ("Reload", #selector(reload)), ("Save PDF…", #selector(savePDF))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            bar.addArrangedSubview(button)
        }
        status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        for view in [bar, web!, status!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12), bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12), web.leadingAnchor.constraint(equalTo: container.leadingAnchor), web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            status.topAnchor.constraint(equalTo: web.bottomAnchor, constant: 8), status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), status.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        setupMenu()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        report()
        if test { DispatchQueue.main.asyncAfter(deadline: .now() + 45) { self.finishTest(false, "Timed out") } }
    }
    func setupMenu() {
        let main = NSMenu()
        func menu(_ title: String, _ entries: [(String, Selector, String)]) {
            let item = NSMenuItem(); main.addItem(item)
            let sub = NSMenu(title: title); item.submenu = sub
            for (label, action, key) in entries {
                let entry = NSMenuItem(title: label, action: action, keyEquivalent: key)
                if [#selector(openFile), #selector(savePDF), #selector(printPage), #selector(report), #selector(help), #selector(reload)].contains(action) { entry.target = self }
                sub.addItem(entry)
            }
        }
        menu("StatsDirect Viewer", [("Quit StatsDirect Viewer", #selector(NSApplication.terminate(_:)), "q")])
        menu("File", [("Open HTML…", #selector(openFile), "o"), ("Save PDF…", #selector(savePDF), "s"), ("Print…", #selector(printPage), "p"), ("Close", #selector(NSWindow.performClose(_:)), "w")])
        menu("Edit", [("Copy", #selector(NSText.copy(_:)), "c"), ("Select All", #selector(NSText.selectAll(_:)), "a")])
        menu("View", [("Report example", #selector(report), "1"), ("Help library", #selector(help), "2"), ("Reload", #selector(reload), "r")])
        NSApp.mainMenu = main
    }
    func load(_ url: URL, root access: URL) {
        allowedRoot = access.standardizedFileURL
        web.loadFileURL(url, allowingReadAccessTo: access)
        status.stringValue = "Loading \(url.lastPathComponent)…"
    }
    @objc func report() { load(root.appendingPathComponent("report.html"), root: root) }
    @objc func help() { load(root.appendingPathComponent("help-index.html"), root: root) }
    @objc func back() { web.goBack() }
    @objc func forward() { web.goForward() }
    @objc func reload() { web.reload() }
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.load(url, root: url.deletingLastPathComponent()) }
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let path = filenames.first { let url = URL(fileURLWithPath: path); load(url, root: url.deletingLastPathComponent()) }
    }
    @objc func printPage() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let operation = web.printOperation(with: info)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "StatsDirect report.pdf"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.web.createPDF { result in
                    do { try result.get().write(to: url); self.status.stringValue = "Saved \(url.lastPathComponent) · Use Print for paginated paper output" }
                    catch { self.showError(error.localizedDescription) }
                }
            }
        }
    }
    func showError(_ message: String) {
        status.stringValue = message
        if test { finishTest(false, message); return }
        let alert = NSAlert(); alert.messageText = "Unable to display or export this document"; alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error.localizedDescription) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL {
            let path = url.resolvingSymlinksInPath().path
            let base = allowedRoot.resolvingSymlinksInPath().path
            decisionHandler(path == base || path.hasPrefix(base + "/") ? .allow : .cancel)
        } else if url.scheme == "about" { decisionHandler(.allow) }
        else {
            if action.navigationType == .linkActivated && ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.isFileURL { load(url, root: allowedRoot) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.title = "StatsDirect · Viewer prototype"
        webView.evaluateJavaScript("document.title") { value, _ in
            if let title = value as? String, !title.isEmpty { self.window.title = "\(title) · Viewer prototype" }
        }
        status.stringValue = webView.url?.path ?? "Ready"
        if test { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.runTest() } }
    }
    func runTest() {
        let script: String
        switch testStage {
        case 0: script = "document.querySelectorAll('table tr').length > 10 && document.body.innerText.includes('299.8524') && document.querySelector('svg') !== null"
        case 1: script = "document.body.innerText.includes('Univariate') && [...document.images].every(i => i.complete && i.naturalWidth > 0)"
        default: script = "document.body.innerText.includes('Reference')"
        }
        web.evaluateJavaScript(script) { result, error in
            guard error == nil, result as? Bool == true else { self.finishTest(false, "DOM/image check failed at stage \(self.testStage): \(String(describing: error))"); return }
            let stage = self.testStage
            self.web.takeSnapshot(with: nil) { picture, error in
                if let data = picture?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.testDirectory.appendingPathComponent("stage-\(stage).png"))
                }
                if stage == 0 {
                    self.web.createPDF { result in
                        do {
                            let data = try result.get()
                            guard data.starts(with: Data("%PDF".utf8)) else { self.finishTest(false, "Invalid PDF"); return }
                            try data.write(to: self.testDirectory.appendingPathComponent("report.pdf"))
                            self.testStage = 1
                            self.web.evaluateJavaScript("document.querySelector('#help-link').click()", completionHandler: nil)
                        } catch { self.finishTest(false, error.localizedDescription) }
                    }
                } else if stage == 1 {
                    self.testStage = 2
                    self.web.evaluateJavaScript("document.querySelector('a[href*=reference_list]').click()", completionHandler: nil)
                } else { self.finishTest(true, "Report table, SVG, PDF, help images and cross-topic link passed") }
            }
        }
    }
    func finishTest(_ success: Bool, _ message: String) {
        try? "\(success ? "PASS" : "FAIL"): \(message)\n".write(to: testDirectory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(success ? 0 : 1)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = Viewer()
    app.delegate = delegate
    app.run()
}
