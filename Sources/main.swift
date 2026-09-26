import Cocoa
import WebKit
import UniformTypeIdentifiers
import Darwin

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
    var rScriptPlan: RScriptPlan?
    var gridDirty = false
    var gridVersion = 0
    var workbookID: String?
    var workbookName = "Untitled.xlsx"
    var pendingWorkbook: [String: Any]?
    var pendingCSV: String?
    var csvSaveName: String?
    var rDataFormat: String?
    var fileBusy = false
    var analysisJobID: String?
    var analysisCancelled = false
    var operationName: String?
    var operationReady = false
    var operationClosing = false
    var operationStarting = false
    var operationRevision = 0
    var learningTask: Task<Void, Never>?
    var learningRequestID: String?
    var learningState: [String: Any]?
    var initialLearningView: String?
    var initialOperationSource: [String: Any]?
    var operationSourceID: String?
    var reportEntries: [ReportEntry]?
    var pendingResult: ReportEntry?
    var scrollToResultID: String?
    var hasSVG = false
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
    var closeApproved = false
    var tabs: NSTabView!
    let documentTabs = NSStackView()
    let documentTabScroll = NSScrollView()
    var status: NSTextField!
    var documents: [Document] = []
    var windowsMenu: NSMenu!
    var running = false
    var reportNumber = 0
    var activeReportID: String?
    var checkingUpdates = false
    var updateTimer: Timer?
    var rNumber = 0
    var libraryHandle: UnsafeMutableRawPointer?
    var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Content") }
    var engineVersion: String {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("engine-info.json")),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return "unknown" }
        return info["version"] ?? "unknown"
    }
    var active: Document? { documents.first { $0.item === tabs.selectedTabViewItem } }
    var worksheetNumber = 0
    var analysisCatalog: [String: [String: Any]] = [:]
    var analysisSourceID: String?
    func nextAnalysisTitle(_ title: String) -> String {
        let openTitles = Set(documents.filter { $0.kind == "operation" || $0.kind == "analysis" }.map(\.title))
        if !openTitles.contains(title) { return title }
        var number = 2
        while openTitles.contains("\(title) · \(number)") { number += 1 }
        return "\(title) · \(number)"
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "StatsDirect · Mac prototype"
        window.delegate = self
        window.minSize = NSSize(width: 850, height: 520)
        let container = NSView(); window.contentView = container
        let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 4
        let symbol = NSImageView(); symbol.image = NSImage(contentsOf: root.appendingPathComponent("Brand/statsdirect.png")); symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.setAccessibilityLabel("StatsDirect"); symbol.widthAnchor.constraint(equalToConstant:26).isActive = true; symbol.heightAnchor.constraint(equalToConstant:26).isActive = true; bar.addArrangedSubview(symbol)
        for title in ["File", "Edit", "Data", "Analysis", "Graphics", "R", "Help", "Window"] {
            let button = NSButton(title: title + " ▾", target: self, action: #selector(showDropdown(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(title)
            button.isBordered = false; button.refusesFirstResponder = true
            button.font = .systemFont(ofSize: 13)
            button.setAccessibilityLabel(title + " menu")
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            bar.addArrangedSubview(button)
        }
        tabs = NSTabView(); tabs.tabViewType = .noTabsNoBorder; tabs.delegate = self
        documentTabs.orientation = .horizontal; documentTabs.alignment = .centerY; documentTabs.spacing = 4
        documentTabScroll.documentView = documentTabs
        documentTabScroll.hasHorizontalScroller = true; documentTabScroll.autohidesScrollers = true
        documentTabScroll.scrollerStyle = .overlay; documentTabScroll.drawsBackground = false
        status = NSTextField(labelWithString: "Ready")
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        for view in [bar, documentTabScroll, tabs!, status!] { view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view) }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 32), status.heightAnchor.constraint(equalToConstant: 16),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4), bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            documentTabScroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            documentTabScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8), documentTabScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8), documentTabScroll.heightAnchor.constraint(equalToConstant: 36),
            tabs.topAnchor.constraint(equalTo: documentTabScroll.bottomAnchor, constant: 2), tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8), tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            status.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 7), status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), status.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        if let icon = NSImage(contentsOf: root.appendingPathComponent("Brand/statsdirect.png")) { NSApp.applicationIconImage = icon }
        setupMenu()
        newWorksheet()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        startUpdateChecks()
    }
    @objc func showDropdown(_ sender: NSButton) {
        guard let title = sender.identifier?.rawValue,
              let source = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == title })?.submenu,
              let menu = source.copy() as? NSMenu else { return }
        // Copy at opening so document names, selection and command validation stay current.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
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
        add(app, "About StatsDirect", #selector(showAbout))
        app.addItem(.separator())
        add(app, "Hide StatsDirect", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp)
        app.items.last?.keyEquivalentModifierMask = [.command, .option]
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator())
        add(app, "Quit StatsDirect", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = menu("File")
        add(file, "New Worksheet", #selector(newWorksheet), "n")
        add(file, "New Report", #selector(newReport))
        add(file, "New R Session", #selector(newRTab), "r")
        file.addItem(.separator())
        add(file, "Open…", #selector(openFile), "o")
        file.addItem(.separator())
        add(file, "Save…", #selector(savePDF), "s")
        let export = NSMenu(title: "Export")
        let exportItem = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        exportItem.submenu = export; file.addItem(exportItem)
        add(export, "Excel Workbook (.xlsx)…", #selector(saveActiveExcel))
        add(export, "Current Worksheet as CSV…", #selector(exportActiveCSV))
        add(export, "Current Worksheet as RDS…", #selector(saveActiveRDS))
        add(export, "All Worksheets as RData…", #selector(saveActiveRData))
        export.addItem(.separator())
        add(export, "Chart as SVG…", #selector(saveChartSVG))
        add(file, "Print…", #selector(printPage), "p")
        file.addItem(.separator()); add(file, "Close Document", #selector(closeTab), "w")
        let edit = menu("Edit")
        for (title, command, key) in [("Undo", "undo", "z"), ("Redo", "redo", "z"), ("Cut", "cut", "x"), ("Copy", "copy", "c"), ("Paste", "paste", "v"), ("Select All", "selectAll", "a")] {
            if command == "cut" { edit.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: #selector(editCommand(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = command
            if command == "redo" { item.keyEquivalentModifierMask = [.command, .shift] }
            edit.addItem(item)
        }
        for title in ["Data", "Analysis", "Graphics"] { populateOperationMenu(menu(title)) }
        let rMenu = menu("R")
        add(rMenu, "New R Session", #selector(newRTab), "")
        add(rMenu, "Continue Report in R", #selector(continueActiveReportInR))
        rMenu.addItem(.separator())
        add(rMenu, "Run Script", #selector(runRScript), "\r")
        add(rMenu, "Stop / Reset Session", #selector(stopRSession))
        add(rMenu, "Save Script…", #selector(saveRScript))
        let help = menu("Help")
        add(help, "Learning", #selector(openLearning))
        add(help, "Learning Options…", #selector(openLearningOptions))
        help.addItem(.separator())
        add(help, "StatsDirect Help", #selector(helpLibrary), "?")
        add(help, "Help for Current Analysis", #selector(currentMethodHelp))
        let examples = NSMenu(title: "Examples")
        let examplesItem = NSMenuItem(title: "Examples", action: nil, keyEquivalent: "")
        examplesItem.submenu = examples; help.addItem(examplesItem)
        add(examples, "StatsDirect Example Workbook", #selector(openExampleWorkbook))
        help.addItem(.separator())
        add(help, "Back", #selector(back))
        add(help, "Forward", #selector(forward))
        help.addItem(.separator())
        add(help, "About StatsDirect", #selector(showAbout))
        add(help, "Check for Updates…", #selector(checkUpdates))
        add(help, "Automatically Check for Updates", #selector(toggleAutomaticUpdates))
        windowsMenu = menu("Window")
        NSApp.mainMenu = main
        updateWindowMenu()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkUpdates) { return !checkingUpdates && window.attachedSheet == nil }
        if menuItem.action == #selector(toggleAutomaticUpdates) { menuItem.state = automaticUpdates ? .on : .off; return true }
        if menuItem.action == #selector(currentMethodHelp) { return active?.operationName != nil || active?.kind == "analysis" }
        if menuItem.action == #selector(editCommand(_:)) { return active != nil }
        if menuItem.action == #selector(back) { return active?.web.canGoBack == true }
        if menuItem.action == #selector(forward) { return active?.web.canGoForward == true }
        if menuItem.action == #selector(saveChartSVG) { return active?.hasSVG == true }
        if [#selector(saveActiveExcel), #selector(exportActiveCSV), #selector(saveActiveRDS), #selector(saveActiveRData)].contains(menuItem.action) { return active?.kind == "grid" }
        if menuItem.action == #selector(continueActiveReportInR) { menuItem.title = active?.rScriptPlan?.hasRecipe == false ? "Open Report Data in R" : "Continue Report in R"; return active?.rScriptPlan != nil }
        if menuItem.action == #selector(runRScript) { return active?.rPane != nil && active?.rPane?.isRunning == false }
        if [#selector(stopRSession), #selector(saveRScript)].contains(menuItem.action) { return active?.rPane != nil }
        if menuItem.action == #selector(printPage) { return active != nil && active?.kind != "operation" && active?.kind != "r" && active?.kind != "grid" && active?.kind != "analysis" }
        if menuItem.action == #selector(savePDF) { menuItem.title = active?.kind == "learn" ? "Export Learning Record…" : active?.kind == "r" ? "Save R Script…" : active?.kind == "grid" ? (active?.rDataFormat != nil ? "Save R Data…" : active?.csvSaveName == nil ? "Save Excel…" : "Save CSV…") : active?.kind == "analysis" ? "Save Table…" : "Save PDF…"; return active != nil && active?.kind != "operation" }
        if [#selector(closeTab), #selector(printPage), #selector(savePDF)].contains(menuItem.action) { return active != nil }
        return true
    }
    func updateWindowMenu() {
        updateDocumentTabs()
        windowsMenu.removeAllItems()
        for (name, action, key) in [("Next Document", #selector(nextTab), "]"), ("Previous Document", #selector(previousTab), "[")] {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self
            item.keyEquivalentModifierMask = [.command, .shift]; windowsMenu.addItem(item)
        }
        windowsMenu.addItem(.separator())
        for doc in documents {
            let item = NSMenuItem(title: doc.title, action: #selector(selectDocument(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = doc.id; item.state = active === doc ? .on : .off; windowsMenu.addItem(item)
        }
    }
    func updateDocumentTabs() {
        for view in documentTabs.arrangedSubviews { documentTabs.removeArrangedSubview(view); view.removeFromSuperview() }
        var width: CGFloat = 0
        var selected: NSView?
        for doc in documents {
            let group = NSStackView(); group.orientation = .horizontal; group.spacing = 0
            group.wantsLayer = true; group.layer?.cornerRadius = 6
            group.layer?.backgroundColor = (active === doc ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor).cgColor
            group.layer?.borderColor = NSColor.separatorColor.cgColor; group.layer?.borderWidth = 0.5
            let select = NSButton(title: doc.title, target: self, action: #selector(selectDocumentTab(_:)))
            select.identifier = NSUserInterfaceItemIdentifier(doc.id); select.isBordered = false
            select.font = .systemFont(ofSize: 12, weight: active === doc ? .semibold : .regular)
            select.cell?.lineBreakMode = .byTruncatingTail; select.toolTip = doc.title
            select.setAccessibilityLabel(doc.title + (active === doc ? ", selected document" : ", document"))
            let titleWidth = min(240, max(90, (doc.title as NSString).size(withAttributes: [.font: select.font!]).width + 20))
            group.widthAnchor.constraint(equalToConstant: titleWidth + 26).isActive = true
            select.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true
            let close = NSButton(title: "×", target: self, action: #selector(closeDocumentTab(_:)))
            close.identifier = NSUserInterfaceItemIdentifier(doc.id); close.isBordered = false
            close.font = .systemFont(ofSize: 17); close.toolTip = "Close " + doc.title
            close.setAccessibilityLabel("Close " + doc.title); close.widthAnchor.constraint(equalToConstant: 26).isActive = true
            for button in [select, close] { button.refusesFirstResponder = true; group.addArrangedSubview(button) }
            group.heightAnchor.constraint(equalToConstant: 30).isActive = true
            documentTabs.addArrangedSubview(group); width += titleWidth + 30
            if active === doc { selected = group }
        }
        documentTabs.frame = NSRect(x: 0, y: 0, width: max(1, width), height: 32)
        documentTabs.layoutSubtreeIfNeeded()
        if let selected { selected.scrollToVisible(selected.bounds) }
    }
    @objc func selectDocumentTab(_ sender: NSButton) {
        if let doc = documents.first(where: { $0.id == sender.identifier?.rawValue }) { tabs.selectTabViewItem(doc.item) }
    }
    @objc func closeDocumentTab(_ sender: NSButton) {
        if let doc = documents.first(where: { $0.id == sender.identifier?.rawValue }) { closeDocument(doc) }
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
        if let doc = active, doc.kind == "grid" { analysisSourceID = doc.id }
        if let doc = active, doc.reportEntries != nil { activeReportID = doc.id }
        window.title = "\(active?.title ?? "StatsDirect") · Mac prototype"
        status.stringValue = running ? "Running analysis…" : "\(documents.count) open documents · \(active?.kind.capitalized ?? "Ready")"
        if windowsMenu != nil { updateWindowMenu() }
    }
    @discardableResult
    func newDocument(kind: String, title: String, url: URL? = nil, html: String? = nil, access: URL? = nil) -> Document {
        let doc = Document(kind: kind, title: title, access: access ?? root)
        if kind == "report" && url == nil { doc.web.configuration.userContentController.add(self, name: "statsDirectReport") }
        if kind == "grid" { doc.web.configuration.userContentController.add(self, name: "statsDirectGrid") }
        if kind == "operation" { doc.web.configuration.userContentController.add(self, name: "statsDirectOperation") }
        if kind == "learn" { doc.web.configuration.userContentController.add(self, name: "statsDirectLearn") }
        if kind == "analysis" { doc.web.configuration.userContentController.add(self, name: "statsDirectAnalysis") }
        doc.hasSVG = html?.contains("<svg") == true
        doc.initialURL = url; doc.web.navigationDelegate = self; doc.web.uiDelegate = self
        documents.append(doc)
        tabs.addTabViewItem(doc.item)
        tabs.selectTabViewItem(doc.item)
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
    @objc func currentMethodHelp() {
        if let doc = active, let operation = doc.operationName, let path = analysisCatalog[operation]?["help"] as? String {
            openHelp(root.appendingPathComponent(path), title: doc.title)
        } else if active?.kind == "analysis" { chiSquareHelp() }
    }
    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "StatsDirect",
            .applicationIcon: NSImage(contentsOf: root.appendingPathComponent("Brand/statsdirect.png")) ?? NSApp.applicationIconImage!,
            .applicationVersion: "\(version) · macOS prototype",
            .version: "",
            .credits: NSAttributedString(string: "Calculation engine: StatsDirect \(engineVersion)\nA development preview for macOS.", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        ])
    }
    @objc func editCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        let fallback = { NSApp.sendAction(NSSelectorFromString(command + ":"), to: nil, from: self) }
        guard let doc = active, doc.kind == "grid" else { _ = fallback(); return }
        let clipboard = command == "paste" ? NSPasteboard.general.string(forType: .string) ?? "" : ""
        doc.web.evaluateJavaScript("window.statsDirectGrid?.editCommand(\(jsString(command)),\(jsString(clipboard)))") { handled, error in
            if error != nil || handled as? Bool != true { _ = fallback() }
        }
    }
    @objc func newRTab() {
        rNumber += 1
        let number = rNumber
        let doc = newDocument(kind: "r", title: "R · Session \(number)")
        let pane = RPane()
        doc.rPane = pane; doc.item.view = pane.view
    }
    @objc func runRScript() { active?.rPane?.runScript() }
    @objc func stopRSession() { active?.rPane?.stopSession() }
    @objc func saveRScript() { active?.rPane?.saveScript() }
    @objc func closeTab() {
        guard let doc = active else { return }
        closeDocument(doc)
    }
    func closeDocument(_ doc: Document) {
        if doc.fileBusy { showError("Please wait for the file save to finish."); return }
        if let id = doc.analysisJobID {
            if doc.kind == "operation" {
                doc.operationClosing = true; doc.analysisCancelled = true
                if !doc.operationStarting { operationRequest(["action": "cancel", "id": id], doc: doc, id: id) }
            } else { doc.operationClosing = true; cancelAnalysis(doc) }
            return
        }
        if doc.kind == "analysis" && doc.gridDirty {
            let alert = NSAlert(); alert.messageText = "Close the contingency table?"
            alert.informativeText = "Unsaved counts and labels will be discarded. Use Save Table to keep a CSV copy. Reports remain open."
            alert.addButton(withTitle: "Close Table"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { self.remove(doc) } }
        } else if let pane = doc.rPane, pane.hasUnsavedChanges || pane.isRunning {
            let alert = NSAlert(); alert.messageText = "Close this R session?"
            alert.informativeText = "Unsaved script edits and R variables will be discarded. Any running script will stop."
            alert.addButton(withTitle: "Close R Session"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { self.remove(doc) } }
        } else if doc.gridDirty {
            let alert = NSAlert(); alert.messageText = "Close the data grid?"; alert.informativeText = doc.rDataFormat != nil ? "Unsaved R table edits will be discarded. Save RDS for one table or RData for all tables." : doc.csvSaveName != nil ? "Unsaved CSV edits will be discarded. Use Save CSV to keep them." : "Unsaved worksheet edits will be discarded. Use Save Excel to keep all worksheets, or Save CSV for a single data table."
            alert.addButton(withTitle: "Close Grid"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { self.remove(doc) } }
        } else { remove(doc) }
    }
    func remove(_ doc: Document) {
        if let id = doc.workbookID { workbookRequest(["action": "close", "id": id]) { _ in } }
        doc.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectReport")
        doc.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectGrid")
        doc.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectAnalysis")
        doc.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectOperation")
        doc.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectLearn")
        doc.learningTask?.cancel(); doc.learningTask = nil
        doc.rPane?.shutdown()
        doc.web.stopLoading(); documents.removeAll { $0 === doc }
        tabs.removeTabViewItem(doc.item)
        updateWindowMenu(); status.stringValue = "\(documents.count) open documents"
    }
    @objc func back() { active?.web.goBack() }
    @objc func forward() { active?.web.goForward() }
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["xlsx", "csv", "rds", "rdata", "rda", "html", "htm"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Open Excel, CSV or R data, or an HTML report."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            for url in panel.urls {
                switch url.pathExtension.lowercased() {
                case "xlsx": self.openExcelURL(url)
                case "csv": self.openCSVURL(url)
                case "rds", "rdata", "rda": self.openRDataURL(url)
                default: self.newDocument(kind: "report", title: "Report · \(url.deletingPathExtension().lastPathComponent)", url: url, access: url.deletingLastPathComponent())
                }
            }
        }
    }
    func endRun() { running = false }
    func number(_ value: Double, places: Int = 6) -> String {
        if !value.isFinite { return "—" }
        if value != 0 && abs(value) < pow(10, -Double(places)) { return String(format: "%.4g", value) }
        return String(format: "%.*f", places, value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
    func page(_ title: String, _ body: String) -> String {
        let css = (try? String(contentsOf: root.appendingPathComponent("workspace.css"), encoding: .utf8)) ?? ""
        return "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>\(title)</title><style>\(css)</style></head><body>\(body)</body></html>"
    }
    @objc func printPage() {
        guard active?.kind != "r" && active?.kind != "grid" && active?.kind != "analysis" else { return }
        guard let web = active?.web else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        web.printOperation(with: info).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func savePDF() {
        if let pane = active?.rPane { pane.saveScript(); return }
        guard let doc = active else { return }
        if doc.kind == "learn" { doc.web.evaluateJavaScript("window.statsDirectLearn?.exportRecord()"); return }
        if doc.kind == "grid" { if let format = doc.rDataFormat { saveRData(doc, format: format) } else if doc.csvSaveName != nil { saveGrid(doc) } else { saveExcel(doc) }; return }
        if doc.kind == "analysis" { saveAnalysisTable(doc); return }
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
        if let id = doc.scrollToResultID {
            doc.scrollToResultID = nil
            webView.evaluateJavaScript("document.getElementById(\(jsString("result-" + id)))?.scrollIntoView()")
        }
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
        if documents.contains(where: { $0.fileBusy }) { showError("Please wait for the file save to finish."); return .terminateCancel }
        if running { showError("Please wait for the running analysis to finish, or cancel it from its form."); return .terminateCancel }
        if closeApproved { return .terminateNow }
        if documents.contains(where: { $0.rPane?.hasUnsavedChanges == true || $0.rPane?.isRunning == true || $0.gridDirty || $0.analysisJobID != nil }) {
            let alert = NSAlert(); alert.messageText = "Quit with unsaved work?"
            alert.informativeText = "Unsaved worksheet and R script edits will be lost. Open analyses and R sessions will stop."
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
