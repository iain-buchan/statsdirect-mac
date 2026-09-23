import Cocoa
import WebKit
import UniformTypeIdentifiers
import Darwin

typealias PairedFunction = @convention(c) (UnsafePointer<Double>?, UnsafePointer<Double>?, Int32, Double, UnsafeMutablePointer<Double>?, Int32) -> Int32

typealias ReportFunction = @convention(c) (UnsafeMutablePointer<CChar>?, Int32) -> Int32

struct PairedExample: Decodable {
    let title: String
    let labels: [String]
    let before: [Double]
    let after: [Double]
    let confidence: Double
}

@MainActor
final class Document {
    let id = UUID().uuidString
    let kind: String
    let web: WKWebView
    let item: NSTabViewItem
    var title: String
    var access: URL
    var initialURL: URL?
    var rPane: RPane?
    init(kind: String, title: String, access: URL) {
        self.kind = kind; self.title = title; self.access = access
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: config)
        item = NSTabViewItem(identifier: id)
        item.label = title
        item.view = web
    }
}

@MainActor
final class Viewer: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSTabViewDelegate, NSMenuItemValidation, NSWindowDelegate {
    var window: NSWindow!
    var frameControls: WindowFrameControls!
    var closeApproved = false
    var tabs: NSTabView!
    var status: NSTextField!
    var runButton: NSButton!
    var exportButton: NSButton!
    var documents: [Document] = []
    var windowsMenu: NSMenu!
    var running = false
    var reportNumber = 0
    var rNumber = 0
    var libraryHandle: UnsafeMutableRawPointer?
    var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Content") }
    var active: Document? { documents.first { $0.item === tabs.selectedTabViewItem } }
    var example: PairedExample!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "StatsDirect · Mac prototype"
        window.delegate = self
        frameControls = WindowFrameControls(window: window)
        window.minSize = NSSize(width: 850, height: 520)
        let container = NSView(); window.contentView = container
        let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 10
        for (label, selector) in [("Example data", #selector(showData)), ("Run paired t test", #selector(runPaired)), ("Method help", #selector(pairedHelp)), ("Help library", #selector(helpLibrary)), ("Back", #selector(back)), ("Forward", #selector(forward)), ("Save PDF…", #selector(savePDF)), ("Close tab", #selector(closeTab))] {
            let button = NSButton(title: label, target: self, action: selector)
            button.bezelStyle = .rounded
            if selector == #selector(runPaired) { runButton = button }
            if selector == #selector(savePDF) { exportButton = button }
            bar.addArrangedSubview(button)
        }
        tabs = NSTabView(); tabs.tabViewType = .topTabsBezelBorder; tabs.delegate = self
        status = NSTextField(labelWithString: "Ready")
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        for view in [bar, tabs!, status!] { view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12), bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            tabs.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12), tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8), tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            status.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 7), status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), status.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        setupMenu()
        do { example = try JSONDecoder().decode(PairedExample.self, from: Data(contentsOf: root.appendingPathComponent("paired-example.json"))) }
        catch { showError("The example data could not be loaded: \(error.localizedDescription)") }
        helpLibrary(); showData()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func setupMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu; return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target ?? self; menu.addItem(item)
        }
        let app = menu("StatsDirect")
        add(app, "Quit StatsDirect", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = menu("File")
        add(file, "New R Tab", #selector(newRTab), "r")
        add(file, "PEFR example data", #selector(showData), "1")
        add(file, "Open HTML in New Tab…", #selector(openFile), "o")
        add(file, "Save PDF…", #selector(savePDF), "s")
        add(file, "Print…", #selector(printPage), "p")
        file.addItem(.separator()); add(file, "Close Tab", #selector(closeTab), "w")
        let edit = menu("Edit")
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        let analysis = menu("Analysis")
        let parametric = NSMenu(title: "Parametric methods")
        let group = NSMenuItem(title: "Parametric methods", action: nil, keyEquivalent: ""); group.submenu = parametric; analysis.addItem(group)
        add(parametric, "Paired t test — PEFR example", #selector(runPaired), "t")
        let rMenu = menu("R")
        add(rMenu, "New R Tab", #selector(newRTab), "")
        add(rMenu, "Run Script", #selector(runRScript), "\r")
        add(rMenu, "Stop / Reset Session", #selector(stopRSession))
        add(rMenu, "Save Script…", #selector(saveRScript))
        let help = menu("Help")
        add(help, "Help Library", #selector(helpLibrary), "2")
        add(help, "Paired Student t Test", #selector(pairedHelp), "?")
        windowsMenu = menu("Window")
        NSApp.mainMenu = main
        updateWindowMenu()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(runRScript) { return active?.rPane != nil && active?.rPane?.isRunning == false }
        if [#selector(stopRSession), #selector(saveRScript)].contains(menuItem.action) { return active?.rPane != nil }
        if menuItem.action == #selector(printPage) { return active != nil && active?.kind != "r" }
        if menuItem.action == #selector(savePDF) { menuItem.title = active?.kind == "r" ? "Save R Script…" : "Save PDF…"; return active != nil }
        if menuItem.action == #selector(runPaired) { return !running && example != nil }
        if [#selector(closeTab), #selector(printPage), #selector(savePDF)].contains(menuItem.action) { return active != nil }
        return true
    }
    func updateWindowMenu() {
        windowsMenu.removeAllItems()
        for (name, action, key) in [("Next Tab", #selector(nextTab), "]"), ("Previous Tab", #selector(previousTab), "[")] {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self
            item.keyEquivalentModifierMask = [.command, .shift]; windowsMenu.addItem(item)
        }
        windowsMenu.addItem(.separator())
        for doc in documents {
            let item = NSMenuItem(title: doc.title, action: #selector(selectDocument(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = doc.id; item.state = active === doc ? .on : .off; windowsMenu.addItem(item)
        }
    }
    @objc func selectDocument(_ sender: NSMenuItem) {
        if let doc = documents.first(where: { $0.id == sender.representedObject as? String }) { tabs.selectTabViewItem(doc.item) }
    }
    @objc func nextTab() { cycleTab(1) }
    @objc func previousTab() { cycleTab(-1) }
    func cycleTab(_ delta: Int) {
        guard let doc = active, let index = documents.firstIndex(where: { $0 === doc }), !documents.isEmpty else { return }
        tabs.selectTabViewItem(documents[(index + delta + documents.count) % documents.count].item)
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        window.title = "\(active?.title ?? "StatsDirect") · Mac prototype"
        exportButton?.title = active?.kind == "r" ? "Save script…" : "Save PDF…"
        status.stringValue = running ? "Running paired t test…" : "\(documents.count) open documents · \(active?.kind.capitalized ?? "Ready")"
        if windowsMenu != nil { updateWindowMenu() }
    }
    @discardableResult
    func newDocument(kind: String, title: String, url: URL? = nil, html: String? = nil, access: URL? = nil) -> Document {
        let doc = Document(kind: kind, title: title, access: access ?? root)
        doc.initialURL = url; doc.web.navigationDelegate = self; doc.web.uiDelegate = self
        documents.append(doc); tabs.addTabViewItem(doc.item); tabs.selectTabViewItem(doc.item)
        if let url { doc.web.loadFileURL(url, allowingReadAccessTo: doc.access) }
        else if let html { doc.web.loadHTMLString(html, baseURL: root) }
        updateWindowMenu(); return doc
    }
    func openHelp(_ url: URL, title: String) {
        if let existing = documents.first(where: { $0.kind == "help" && $0.initialURL == url }) {
            tabs.selectTabViewItem(existing.item)
            if existing.web.url != url { existing.web.loadFileURL(url, allowingReadAccessTo: existing.access) }
            return
        }
        newDocument(kind: "help", title: "Help · \(title)", url: url)
    }
    @objc func helpLibrary() { openHelp(root.appendingPathComponent("help-index.html"), title: "Library") }
    @objc func pairedHelp() { openHelp(root.appendingPathComponent("Help/parametric_methods/paired_t.htm"), title: "Paired t test") }
    @objc func showData() {
        if let doc = documents.first(where: { $0.kind == "data" }) { tabs.selectTabViewItem(doc.item); return }
        guard let example else { return }
        let rows = zip(example.before, example.after).enumerated().map { i, pair in
            "<tr><th scope='row'>\(i+1)</th><td><input aria-label='Before, subject \(i+1)' name='before' type='number' step='any' value='\(pair.0)'></td><td><input aria-label='After, subject \(i+1)' name='after' type='number' step='any' value='\(pair.1)'></td></tr>"
        }.joined()
        let body = """
        <div class="eyebrow">Example data / Paired observations</div><h1>Before and after a winter walk</h1>
        <p class="lead">Peak expiratory flow rate in nine people with asthma. Each row is one person.</p>
        <div class="note">Choose <strong>Analysis → Parametric methods → Paired t test</strong> (⌘T) to calculate a new report. You can edit these values and run it again; earlier reports stay in their own tabs.</div>
        <table class="data"><thead><tr><th>Subject</th><th>PEFR Before</th><th>PEFR After</th></tr></thead><tbody>\(rows)</tbody></table>
        <p class="muted">Difference = Before − After · 95% confidence interval · Missing pairs are omitted.</p>
        <p><a href="Help/parametric_methods/paired_t.htm">Read the method and worked example →</a></p>
        """
        newDocument(kind: "data", title: "Data · PEFR example", html: page("PEFR example", body))
    }
    @objc func newRTab() {
        rNumber += 1
        let number = rNumber
        let doc = newDocument(kind: "r", title: "R · Session \(number)")
        let pane = RPane(before: example?.before ?? [], after: example?.after ?? [])
        doc.rPane = pane; doc.item.view = pane.view
    }
    @objc func runRScript() { active?.rPane?.runScript() }
    @objc func stopRSession() { active?.rPane?.stopSession() }
    @objc func saveRScript() { active?.rPane?.saveScript() }
    @objc func closeTab() {
        guard let doc = active else { return }
        if let pane = doc.rPane, pane.hasUnsavedChanges || pane.isRunning {
            let alert = NSAlert(); alert.messageText = "Close this R session?"
            alert.informativeText = "Unsaved script edits and R variables will be discarded. Any running script will stop."
            alert.addButton(withTitle: "Close R Tab"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { self.remove(doc) } }
        } else if doc.kind == "data" {
            let alert = NSAlert(); alert.messageText = "Close the example data?"; alert.informativeText = "Any edits to the example data will be discarded. Your reports remain open."
            alert.addButton(withTitle: "Close Data"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { self.remove(doc) } }
        } else { remove(doc) }
    }
    func remove(_ doc: Document) {
        doc.rPane?.shutdown()
        doc.web.stopLoading(); documents.removeAll { $0 === doc }; tabs.removeTabViewItem(doc.item)
        updateWindowMenu(); status.stringValue = "\(documents.count) open documents"
    }
    @objc func back() { active?.web.goBack() }
    @objc func forward() { active?.web.goForward() }
    @objc func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.html]
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.newDocument(kind: "report", title: "Report · \(url.deletingPathExtension().lastPathComponent)", url: url, access: url.deletingLastPathComponent()) }
        }
    }
    @objc func runPaired() {
        guard !running, example != nil else { return }
        // Read the data document even when a report/help tab is selected.
        if !documents.contains(where: { $0.kind == "data" }) {
            showData(); running = true; runButton.isEnabled = false
            calculate(before: example.before, after: example.after)
            return
        }
        guard let dataDoc = documents.first(where: { $0.kind == "data" }) else { return }
        running = true; runButton.isEnabled = false; status.stringValue = "Running paired t test…"
        let script = "JSON.stringify({before:[...document.querySelectorAll('input[name=before]')].map(e=>e.value),after:[...document.querySelectorAll('input[name=after]')].map(e=>e.value)})"
        dataDoc.web.evaluateJavaScript(script) { value, error in
            guard error == nil, let text = value as? String, let bytes = text.data(using: .utf8), let values = try? JSONDecoder().decode([String:[String]].self, from: bytes), let a = values["before"], let b = values["after"], a.count == b.count, a.count >= 2 else { self.endRun(); self.showError("The data are still loading. Please try again."); return }
            let before = a.map { Double($0) ?? Double.nan }; let after = b.map { Double($0) ?? Double.nan }
            self.calculate(before: before, after: after)
        }
    }
    func calculate(before: [Double], after: [Double]) {
        if libraryHandle == nil {
            let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/StatsDirectEngine.dylib").path
            libraryHandle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
        }
        guard let handle = libraryHandle, let symbol = dlsym(handle, "statsdirect_paired_t") else {
            endRun(); showError("The paired-test calculation library could not be loaded. Please rebuild the application."); return
        }
        let compute = unsafeBitCast(symbol, to: PairedFunction.self)
        let readReport: ReportFunction? = dlsym(handle, "statsdirect_paired_report").map { unsafeBitCast($0, to: ReportFunction.self) }
        DispatchQueue.global(qos: .userInitiated).async {
            var result = Array(repeating: 0.0, count: 11)
            let code = before.withUnsafeBufferPointer { a in after.withUnsafeBufferPointer { b in
                result.withUnsafeMutableBufferPointer { output in compute(a.baseAddress, b.baseAddress, Int32(before.count), 0.95, output.baseAddress, 11) }
            } }
            var engineReport = ""
            if code == 0, let readReport = readReport {
                let size = readReport(nil, 0)
                if size > 0 && size < 10_000_000 {
                    var bytes = Array<CChar>(repeating: 0, count: Int(size))
                    _ = bytes.withUnsafeMutableBufferPointer { readReport($0.baseAddress, size) }
                    engineReport = String(cString: bytes)
                }
            }
            let reportHTML = engineReport
            let calculated = result
            DispatchQueue.main.async {
                self.endRun()
                guard code == 0 else {
                    let messages = [1:"The paired data or confidence level is invalid.",2:"At least two complete numeric pairs are needed.",3:"The differences must be finite and must vary. A t test cannot be calculated for constant differences in this prototype.",4:"The calculation or report generation failed.",5:"The bundled .NET engine could not be initialized."]
                    self.showError(messages[Int(code)] ?? "Calculation failed."); return
                }
                self.showResult(calculated, before: before, after: after, engineHTML: reportHTML)
            }
        }
    }
    func endRun() { running = false; runButton.isEnabled = true }
    func number(_ value: Double, places: Int = 6) -> String {
        if !value.isFinite { return "—" }
        if value != 0 && abs(value) < pow(10, -Double(places)) { return String(format: "%.4g", value) }
        return String(format: "%.*f", places, value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
    func showResult(_ r: [Double], before: [Double], after: [Double], engineHTML: String) {
        reportNumber += 1
        let unchanged = before == example.before && after == example.after
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let inputs = zip(before,after).enumerated().map { i,pair in "<tr><th>\(i+1)</th><td>\(number(pair.0))</td><td>\(number(pair.1))</td><td>\(number(pair.0-pair.1))</td></tr>" }.joined()
        let body = """
        <div class="eyebrow">Analysis / Parametric methods</div>
        <p class="lead">PEFR Before − PEFR After</p><p class="muted">Report \(reportNumber) · \(stamp) · \(unchanged ? "Original worked example" : "Edited example data")</p>
        <div class="summary"><div><span>Mean difference</span><strong>\(number(r[1],places:4))</strong></div><div><span>Two-sided P</span><strong>\(number(r[9],places:6))</strong></div><div><span>Matched pairs</span><strong>\(Int(r[0]))</strong></div></div>
        <section class="engine-report">\(engineHTML)</section>
        <p><a href="Help/parametric_methods/paired_t.htm">Paired Student t test: method and worked example →</a></p>
        <details><summary>Input data used for this report</summary><table><thead><tr><th>Subject</th><th>Before</th><th>After</th><th>Difference</th></tr></thead><tbody>\(inputs)</tbody></table></details>
        <p class="muted">95% confidence level. Incomplete pairs are excluded. The optional agreement analysis is not included. Calculated by the full StatsDirect 5.0.5 headless engine and displayed using its HTML report renderer.</p>
        """
        newDocument(kind: "report", title: "Report \(reportNumber) · Paired t test", html: page("Paired t test",body))
        status.stringValue = "Paired t test completed · \(Int(r[0])) complete pairs · Report \(reportNumber)"
    }
    func page(_ title: String, _ body: String) -> String {
        let css = (try? String(contentsOf: root.appendingPathComponent("workspace.css"), encoding: .utf8)) ?? ""
        return "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>\(title)</title><style>\(css)</style></head><body>\(body)</body></html>"
    }
    @objc func printPage() {
        guard active?.kind != "r" else { return }
        guard let web = active?.web else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        web.printOperation(with: info).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func savePDF() {
        if let pane = active?.rPane { pane.saveScript(); return }
        guard let doc = active else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "\(doc.title).pdf"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                doc.web.createPDF { result in
                    do { try result.get().write(to: url); self.status.stringValue = "Saved \(url.lastPathComponent). Use Print for paginated output." }
                    catch { self.showError(error.localizedDescription) }
                }
            }
        }
    }
    func showError(_ message: String) {
        status.stringValue = message
        let alert = NSAlert(); alert.messageText = "StatsDirect"; alert.informativeText = message; alert.beginSheetModal(for: window)
    }
    func document(for web: WKWebView) -> Document? { documents.first { $0.web === web } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let doc = document(for: webView) else { decisionHandler(.cancel); return }
        if url.isFileURL {
            let path = url.resolvingSymlinksInPath().path
            let base = doc.access.resolvingSymlinksInPath().path
            guard path == base || path.hasPrefix(base + "/") else { decisionHandler(.cancel); return }
            if doc.kind != "help" && path.hasPrefix(root.appendingPathComponent("Help").path + "/") {
                decisionHandler(.cancel)
                openHelp(url, title: url.deletingPathExtension().lastPathComponent.replacingOccurrences(of:"_",with:" "))
            } else { decisionHandler(.allow) }
        } else if url.scheme == "about" { decisionHandler(.allow) }
        else {
            if action.navigationType == .linkActivated && ["https","http","mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.isFileURL { openHelp(url, title: url.deletingPathExtension().lastPathComponent) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let doc = document(for: webView) else { return }
        if doc.kind == "help", webView.url?.lastPathComponent != "help-index.html" {
            webView.evaluateJavaScript("document.querySelector('h1')?.textContent?.trim() || document.title") { value, _ in
                if let name = value as? String, !name.isEmpty {
                    doc.title = "Help · \(name)"; doc.item.label = doc.title; self.updateWindowMenu()
                    if self.active === doc { self.window.title = "\(doc.title) · Mac prototype" }
                }
            }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let allowed = applicationShouldTerminate(NSApp) == .terminateNow
        closeApproved = allowed
        return allowed
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if closeApproved { return .terminateNow }
        if documents.contains(where: { $0.rPane?.hasUnsavedChanges == true || $0.rPane?.isRunning == true }) {
            let alert = NSAlert(); alert.messageText = "Quit with open R scripts?"
            alert.informativeText = "Unsaved R script edits and session variables will be lost. Running scripts will stop."
            alert.addButton(withTitle: "Quit"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { for doc in documents { doc.rPane?.shutdown() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let delegate = Viewer(); app.delegate = delegate; app.run()
}
