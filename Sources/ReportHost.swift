import Cocoa
import WebKit
import UniformTypeIdentifiers

struct ReportEntry {
    let id: String
    let title: String
    let operation: String
    let body: String
    // The engine's record of the run that produced this result (its JSON text: pointers to the worksheet columns, the settings and
    // the results), from which the engine writes the R script on demand; nil for text and for results without one.
    let record: String?
    // Whether the shared R recipes hold one for the operation: from the engine's snapshot, or the manifest for a reopened report.
    var recipe: Bool = false
    var editedBody: String?
    var annotation = ""
    // The method's help page for this result, offered by the context menu and F1 and written into saved reports as a link.
    var helpPath: String? = nil
}

struct ReportBodyChange {
    let id: String
    let before: String?
    var after: String?
}

struct IndexedReportEntry {
    let index: Int
    let entry: ReportEntry
    var bytes: Int { entry.body.utf8.count + (entry.editedBody?.utf8.count ?? 0) + entry.annotation.utf8.count }
}

struct ReportChange {
    var edits: [ReportBodyChange]
    var removed: [IndexedReportEntry] = []
    var added: [IndexedReportEntry] = []
    var time = Date()
    var typing: Bool
    var bytes: Int {
        var total = 0
        for edit in edits {
            total += edit.before?.utf8.count ?? 0
            total += edit.after?.utf8.count ?? 0
        }
        for frame in removed { total += frame.bytes }
        for frame in added { total += frame.bytes }
        return total
    }
}

extension Viewer {
    // Reports and instant-answer previews use the engine's Creole presentation;
    // the generic workspace page also serves other, non-report windows.
    func reportPage(_ title: String, _ body: String) -> String {
        let css = (try? String(contentsOf: root.appendingPathComponent("Mac/report.css"), encoding: .utf8)) ?? ""
        return page(title, body, bodyClass: "engine-report", additionalCSS: css)
    }

    @objc func newReport() { _ = makeReport() }

    func makeReport() -> Document {
        reportNumber += 1
        let doc = newDocument(kind: "report", title: "Report \(reportNumber)")
        doc.reportEntries = []
        activeReportID = doc.id
        renderReport(doc)
        return doc
    }

    func renderReport(_ doc: Document) {
        guard var entries = doc.reportEntries else { return }
        // Notes written in the earlier separate field become text of their result, editable with the rest.
        for index in entries.indices where !entries[index].annotation.isEmpty {
            entries[index].editedBody = (entries[index].editedBody ?? entries[index].body) + "<p class='report-note'>" + htmlEscape(entries[index].annotation) + "</p>"
            entries[index].annotation = ""
        }
        doc.reportEntries = entries
        doc.operationName = entries.last?.operation
        // The report is one editable region; each result is a block in it, identified by its id.
        let body = "<div id='report-empty' class='report-controls' \(entries.isEmpty ? "" : "hidden")><p class='muted'>Type here or run an analysis to add results.</p></div><div id='report-results' class='report-body' tabindex='-1' role='textbox' aria-label='Report' aria-multiline='true' data-draft-id='text-\(doc.id)'>" + entries.map { reportEntryHTML($0) }.joined() + "</div>"
        doc.hasSVG = body.contains("<svg")
        let notice = doc.reportImportNotice.map { "<p class='report-controls report-import-notice'>\(htmlEscape($0))</p>" } ?? ""
        let editor = (try? String(contentsOf: root.appendingPathComponent("Report/editor.js"), encoding: .utf8)) ?? ""
        let macHost = (try? String(contentsOf: root.appendingPathComponent("Mac/report-host.js"), encoding: .utf8)) ?? ""
        let toolbar = (try? String(contentsOf: root.appendingPathComponent("Mac/toolbar.js"), encoding: .utf8)) ?? ""
        let icons = (try? String(contentsOf: root.appendingPathComponent("Mac/toolbar-icons.json"), encoding: .utf8)) ?? "{}"
        let style = "<style>" + ((try? String(contentsOf: root.appendingPathComponent("Mac/toolbar.css"), encoding: .utf8)) ?? "") + "</style>"
        let bootstrap = style + "<script>window.StatsDirectToolbarIcons=" + icons + ";\n" + toolbar + "\n" + editor + "\nStatsDirectReportEditor.start({editing:\(doc.reportEditing),undo:\(!doc.reportUndo.isEmpty),redo:\(!doc.reportRedo.isEmpty)});\n" + macHost + "</script>"
        doc.web.loadHTMLString(reportPage(doc.title, reportToolbar(doc) + notice + body + bootstrap), baseURL: root)
    }

    // A result as a block of the report: its id, the help page and R availability for the context menu, and its content.
    func reportEntryHTML(_ entry: ReportEntry) -> String {
        let body=entry.editedBody ?? entry.body
        let help=entry.helpPath.map { " data-help=\"\(htmlEscape($0))\"" } ?? ""
        let r=entry.record == nil ? "" : " data-r='\(entry.recipe ? "recipe" : "data")'"
        return "<article class='report-entry' id='result-\(entry.id)' data-result-id='\(entry.id)'\(help)\(r) aria-label=\"\(htmlEscape(entry.title))\">" + body + "</article>"
    }
    func editReport(_ doc: Document, _ body: [String:Any]) {
        guard let action=body["action"] as? String else { return }
        if action == "transferNotice", let text = body["text"] as? String { status.stringValue = text; return }
        if action == "clipboard", let command = body["command"] as? String, ["copy", "cut", "paste"].contains(command) { reportClipboardCommand(doc, command: command); return }
        if action == "save" { saveReport(doc); return }
        if action == "find" { showFindBar(doc, replace: false); return }
        if action == "ai" { scriptAI.open(doc,reportResultID:body["resultID"] as? String); return }
        if action == "editing" { doc.reportEditing = body["value"] as? Bool ?? false; return }
        // What the pointer was on at a right-click, for the context menu the shell shows.
        if action == "context" {
            doc.reportContext = body
            doc.reportContext["nativeContextToken"] = UUID().uuidString
            return
        }
        if action == "addText" {
            let entry = ReportEntry(id: UUID().uuidString, title: "Text", operation: "", body: "<p>Enter your text here.</p>", record: nil)
            pushReportChange(doc, ReportChange(edits: [], added: [IndexedReportEntry(index: doc.reportEntries?.count ?? 0, entry: entry)], typing: false))
            doc.reportEntries?.append(entry)
            doc.reportEditing = true; doc.reportRevision += 1; doc.scrollToResultID = entry.id
            renderReport(doc); return
        }
        if action == "undoText" || action == "redoText" {
            let undo = action == "undoText"
            guard var change = undo ? doc.reportUndo.popLast() : doc.reportRedo.popLast() else { return }
            // Notes have their own text-field undo. Keep their latest value if
            // a restored entry is removed again by Redo (or added text by Undo).
            func latest(_ items: [IndexedReportEntry]) -> [IndexedReportEntry] {
                items.map { item in IndexedReportEntry(index: item.index, entry: doc.reportEntries?.first(where: { $0.id == item.entry.id }) ?? item.entry) }
            }
            if undo { change.added = latest(change.added); doc.reportRedo.append(change) }
            else { change.removed = latest(change.removed); doc.reportUndo.append(change) }
            let remove = undo ? change.added : change.removed, restore = undo ? change.removed : change.added
            for item in remove { doc.reportEntries?.removeAll { $0.id == item.entry.id } }
            for item in restore.sorted(by: { $0.index < $1.index }) {
                if doc.reportEntries?.contains(where: { $0.id == item.entry.id }) != true {
                    let position = min(item.index, doc.reportEntries?.count ?? 0)
                    doc.reportEntries?.insert(item.entry, at: position)
                }
            }
            for edit in change.edits {
                updateReportText(doc, id: edit.id, html: undo ? edit.before : edit.after, refresh: false)
            }
            doc.reportRevision += 1
            syncReportEntries(doc, changed: Set(change.edits.map(\.id) + restore.map { $0.entry.id }))
            reportEditHistory(doc); return
        }
        if action == "editBodies", let edits = body["edits"] as? [[String: String]] {
            recordReportEdits(doc, edits: edits, removing: body["remove"] as? [String] ?? [], typing: false); return
        }
        guard let id=body["resultID"] as? String else { return }
        if action == "editBody" {
            if let html = body["html"] as? String { recordReportEdits(doc, edits: [["id": id, "html": html]], typing: body["typing"] as? Bool ?? false) }; return
        }
    }

    // A drag between result sections is one transaction, including both the
    // removal and insertion. Validate all sections before changing any of them.
    func recordReportEdits(_ doc: Document, edits: [[String: String]], removing: [String] = [], typing: Bool) {
        if doc.reportEntries?.isEmpty == true, edits.count == 1, removing.isEmpty,
           edits[0]["id"] == "text-" + doc.id, let html = edits[0]["html"], html.utf8.count <= 30_000_000 {
            let entry = ReportEntry(id: "text-" + doc.id, title: "Text", operation: "", body: html, record: nil)
            pushReportChange(doc, ReportChange(edits: [], added: [IndexedReportEntry(index: 0, entry: entry)], typing: false))
            doc.reportEntries = [entry]; doc.reportRevision += 1; doc.hasSVG = html.contains("<svg")
            reportEditHistory(doc); return
        }
        let ids = edits.compactMap { $0["id"] } + removing
        guard !ids.isEmpty, ids.count <= (doc.reportEntries?.count ?? 0), Set(ids).count == ids.count else { return }
        var changes: [ReportBodyChange] = []
        var removed: [IndexedReportEntry] = []
        for id in removing {
            guard let index = doc.reportEntries?.firstIndex(where: { $0.id == id }), let entry = doc.reportEntries?[index] else { return }
            removed.append(IndexedReportEntry(index: index, entry: entry))
        }
        for edit in edits {
            guard let id = edit["id"], let html = edit["html"], html.utf8.count <= 30_000_000,
                  let entry = doc.reportEntries?.first(where: { $0.id == id }) else { return }
            if html != (entry.editedBody ?? entry.body) { changes.append(ReportBodyChange(id: id, before: entry.editedBody, after: html)) }
        }
        guard !changes.isEmpty || !removed.isEmpty else { return }
        let change = ReportChange(edits: changes, removed: removed, typing: typing && removed.isEmpty)
        if changes.count == 1, removed.isEmpty, let last = doc.reportUndo.last, last.edits.count == 1,
           last.edits[0].id == changes[0].id, last.typing, change.typing, Date().timeIntervalSince(last.time) < 1.0, doc.reportRedo.isEmpty {
            doc.reportUndo[doc.reportUndo.count - 1].edits[0].after = changes[0].after
            doc.reportUndo[doc.reportUndo.count - 1].time = Date()
            trimReportHistory(doc)
        } else { pushReportChange(doc, change) }
        for change in changes { updateReportText(doc, id: change.id, html: change.after, refresh: false) }
        if !removed.isEmpty {
            doc.reportEntries?.removeAll { removing.contains($0.id) }; doc.reportRevision += 1
            syncReportEntries(doc, changed: [])
        }
        doc.hasSVG = doc.reportEntries?.contains(where: { ($0.editedBody ?? $0.body).contains("<svg") }) ?? false
        reportEditHistory(doc)
    }

    func reportEditHistory(_ doc: Document) {
        doc.web.evaluateJavaScript("StatsDirectReportEditor.history(\(!doc.reportUndo.isEmpty),\(!doc.reportRedo.isEmpty))")
    }
    func trimReportHistory(_ doc: Document) {
        while doc.reportUndo.count > 50 || (doc.reportUndo.count > 1 && doc.reportUndo.reduce(0, { $0 + $1.bytes }) > 60_000_000) { doc.reportUndo.removeFirst() }
    }
    func pushReportChange(_ doc: Document, _ change: ReportChange) {
        doc.reportUndo.append(change); doc.reportRedo = []; trimReportHistory(doc)
    }
    func syncReportEntries(_ doc: Document, changed: Set<String>) {
        let entries = doc.reportEntries ?? []
        doc.operationName = entries.last?.operation
        doc.hasSVG = entries.contains { ($0.editedBody ?? $0.body).contains("<svg") }
        let replacements = entries.filter { changed.contains($0.id) }.map { ["id": $0.id, "html": reportEntryHTML($0)] }
        if let data = try? JSONSerialization.data(withJSONObject: replacements), let json = String(data: data, encoding: .utf8),
           let orderData = try? JSONSerialization.data(withJSONObject: entries.map(\.id)), let order = String(data: orderData, encoding: .utf8) {
            doc.web.evaluateJavaScript("StatsDirectReportEditor.replaceEntries(\(json),\(order))")
        }
    }
    func updateReportText(_ doc: Document, id: String, html: String?, refresh: Bool) {
        guard let index = doc.reportEntries?.firstIndex(where: { $0.id == id }) else { return }
        doc.reportEntries?[index].editedBody = html; doc.reportRevision += 1
        doc.hasSVG = doc.reportEntries?.contains(where: { ($0.editedBody ?? $0.body).contains("<svg") }) ?? false
        if refresh, let entry = doc.reportEntries?[index] {
            doc.web.evaluateJavaScript("StatsDirectReportEditor.replace(\(jsString(id)),\(jsString(reportEntryHTML(entry))))")
        }
    }
    func populateReportFormatMenu(_ menu: NSMenu) {
        func add(_ parent: NSMenu, _ title: String, _ command: String, _ value: String = "", _ key: String = "") {
            let item=NSMenuItem(title:title,action:#selector(reportFormatCommand(_:)),keyEquivalent:key)
            item.target=self;item.representedObject=["command":command,"value":value];parent.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let child=NSMenu(title:title)
            item.submenu=child;menu.addItem(item);return child
        }
        let font=submenu("Font")
        let available=Set(NSFontManager.shared.availableFontFamilies)
        for name in ["Arial","Calibri","Cambria","Courier New","Georgia","Helvetica","Menlo","Times New Roman","Trebuchet MS","Verdana"] where available.contains(name) {add(font,name,"fontName",name)}
        let size=submenu("Font Size")
        for n in [8,9,10,11,12,14,16,18,20,24,28,36,48,72] {add(size,"\(n) pt","fontSize",String(n))}
        let style=submenu("Text Style")
        for (title,command,key) in [("Bold","bold","b"),("Italic","italic","i"),("Underline","underline","u"),("Strikethrough","strikeThrough",""),("Superscript","superscript",""),("Subscript","subscript","")] {add(style,title,command,"",key)}
        let paragraph=submenu("Paragraph Style")
        for (title,value) in [("Normal","p"),("Heading 1","h1"),("Heading 2","h2"),("Heading 3","h3")] {add(paragraph,title,"formatBlock",value)}
        let lists=submenu("Lists and Indentation")
        for (title,command) in [("Bullets","insertUnorderedList"),("Numbering","insertOrderedList"),("Increase Indent","indent"),("Decrease Indent","outdent")] {add(lists,title,command)}
        let align=submenu("Alignment")
        for (title,command) in [("Left","justifyLeft"),("Centre","justifyCenter"),("Right","justifyRight"),("Justify","justifyFull")] {add(align,title,command)}
        let spacing=submenu("Line Spacing")
        for (title,value) in [("Single","1"),("1.15","1.15"),("1.5","1.5"),("Double","2")] {add(spacing,title,"lineSpacing",value)}
        for (title,command) in [("Text Colour","foreColor"),("Highlight","hiliteColor")] {
            let colours=submenu(title)
            for (name,colour) in [("Black","#000000"),("Grey","#666666"),("Red","#c00000"),("Blue","#0066cc"),("Green","#008000"),("Yellow","#ffff00"),("White","#ffffff")] {add(colours,name,command,colour)}
            if command=="hiliteColor" {add(colours,"None",command,"transparent")}
        }
        menu.addItem(.separator());add(menu,"Clear Formatting","removeFormat")
    }
    @objc func reportFormatCommand(_ sender: NSMenuItem) {
        guard let doc=active,doc.kind=="report",let values=sender.representedObject as? [String:String],let command=values["command"] else {return}
        if command=="toggle" {doc.web.evaluateJavaScript("StatsDirectReportEditor.command('toggle')");return}
        guard doc.reportEditing else {return}
        doc.web.evaluateJavaScript("StatsDirectReportEditor.menuCommand(\(jsString(command)),\(jsString(values["value"] ?? "")))")
    }

    func reportToolbar(_ doc: Document) -> String {
        return """
        <div id='report-toolbar' class='report-controls report-toolbar' role='toolbar' aria-label='Report formatting'>
        <div id='report-format-tools'></div></div>
        """
    }

    @discardableResult
    func appendReport(_ entry: ReportEntry) -> Document {
        // A repeated Add action must never duplicate an unchanged result.
        if let existing = documents.first(where: { $0.reportEntries?.contains(where: { $0.id == entry.id }) == true }) {
            tabs.selectTabViewItem(existing.item); return existing
        }
        let report = documents.first(where: { $0.id == activeReportID && $0.reportEntries != nil })
            ?? documents.last(where: { $0.reportEntries != nil }) ?? makeReport()
        report.reportEntries?.append(entry)
        report.reportRevision += 1
        // Engine output is outside edit history. Undo changes only the entries
        // recorded in its transaction, preserving any analyses appended later.
        report.operationName = entry.operation
        report.scrollToResultID = entry.id
        renderReport(report)
        tabs.selectTabViewItem(report.item)
        activeReportID = report.id
        status.stringValue = "\(entry.title) added to \(report.title)"
        return report
    }

    func previewResult(_ entry: ReportEntry, in doc: Document) {
        doc.pendingResult = entry
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        let preview = reportPage(entry.title, "<style>.report-links{display:none}body{padding:12px 18px}</style><div class='report-body'>" + entry.body + "</div>")
        doc.web.evaluateJavaScript("window.\(bridge)?.showResult({id:\(jsString(entry.id)),page:\(jsString(preview))})")
        status.stringValue = "\(entry.title) complete · Add to report to keep these results"
    }

    func keepResult(_ doc: Document, id: String?) {
        guard let entry = doc.pendingResult, entry.id == id else { return }
        let report = appendReport(entry)
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        doc.web.evaluateJavaScript("window.\(bridge)?.resultKept(\(jsString(report.title)))")
    }

    // The report's context menu: the result under the pointer and what belongs to it. The editor
    // posts the context at the right-click; WebKit opens the menu after that message has arrived.
    func extendReportMenu(_ menu: NSMenu, for doc: Document) {
        let context = doc.reportContext
        guard context["inReport"] as? Bool == true else { return }
        var items: [NSMenuItem] = []
        func add(_ title: String, _ kind: String, _ value: String = "") {
            let item = NSMenuItem(title: title, action: #selector(reportContextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["kind": kind, "value": value, "document": doc.id,
                                      "context": context["nativeContextToken"] as? String ?? "", "revision": String(doc.reportRevision)]
            items.append(item)
        }
        let id = context["resultId"] as? String
        if let help = context["help"] as? String, !help.isEmpty { add("Method Help", "help", help) }
        add("AI Assistance…", "ai", id ?? "")
        if let r = context["r"] as? String, let id { add(r == "recipe" ? "Continue in R" : "Open Data and Settings in R", "r", id) }
        if let id { add("Select Result", "selectResult", id) }
        add("Select All Results", "selectAll")
        if context["picture"] as? Bool == true, doc.reportEditing {
            add("Fit Chart to Width", "pictureFit")
            add("Chart Width…", "pictureWidth")
        }
        // A chart as a file, as the Windows report's menu offers: its own markup, or a PNG at twice its size on the page.
        if context["picture"] as? Bool == true {
            add("Copy Chart", "copyChart", context["chartKind"] as? String == "svg" ? "svg" : "png")
            if context["chartKind"] as? String == "svg" { add("Save Chart as SVG…", "saveChart", "svg") }
            add("Save Chart as PNG…", "saveChart", "png")
        }
        guard !items.isEmpty else { return }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        menu.insertItem(.separator(), at: items.count)
    }
    /// Publish SVG under Office's Mac type as well as Apple's, with PNG and
    /// the private report fragment available to other receiving applications.
    @discardableResult func copyReportChart(_ doc: Document, format: String, context: String, revision: Int,
                                            pasteboard: NSPasteboard = .general) async throws -> Bool {
        func valid() -> Bool {
            documents.contains(where: { $0 === doc }) && !doc.web.isLoading && doc.reportRevision == revision
                && !context.isEmpty && doc.reportContext["nativeContextToken"] as? String == context
        }
        guard ["svg", "png"].contains(format), valid() else { return false }
        guard let result = try await doc.web.callAsyncJavaScript("return await StatsDirectMacReportChart.image(format, 2);",
            arguments: ["format": format], in: nil, contentWorld: .page) as? [String: Any],
              let image = result["image"] as? String else { throw LegacyReportError("The selected chart could not be prepared.") }
        guard valid() else { return false }
        guard let png = result["png"] as? String, png.hasPrefix("data:image/"), let comma = png.firstIndex(of: ","),
              png[..<comma].hasSuffix(";base64"), let data = Data(base64Encoded: String(png[png.index(after: comma)...])),
              data.count <= ReportImageClipboard.maximumBytes, let raster = NSImage(data: data) else {
            throw LegacyReportError("The selected chart could not be copied as PNG.")
        }
        try ReportImageClipboard.write(image: raster, svg: format == "svg" ? Data(image.utf8) : nil,
            to: pasteboard, reportFragment: result["fragment"] as? String)
        status.stringValue = format == "svg" ? "Copied chart as SVG and PNG" : "Copied chart as PNG"
        return true
    }
    func saveReportChart(_ doc: Document, format: String) {
        let png = format == "png"
        let panel = NSSavePanel(); panel.title = png ? "Save Chart as PNG" : "Save Chart as SVG"; panel.prompt = "Save"
        panel.nameFieldStringValue = png ? "chart.png" : "chart.svg"
        panel.allowedContentTypes = [png ? UTType.png : UTType.svg]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            doc.web.callAsyncJavaScript("return await StatsDirectReportEditor.chartImage(format, scale)", arguments: ["format": format, "scale": 2], in: nil, in: .page) { result in
                switch result {
                case .failure(let error):
                    self.showError("The chart could not be saved: " + (((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription))
                case .success(let value):
                    guard let text = value as? String else { self.showError("The chart could not be saved."); return }
                    do {
                        let prefix = "data:image/png;base64,"
                        if png {
                            guard text.hasPrefix(prefix), let data = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { self.showError("The chart could not be drawn."); return }
                            try data.write(to: url, options: .atomic)
                        } else { try Data(text.utf8).write(to: url, options: .atomic) }
                        self.status.stringValue = "Chart saved as " + url.lastPathComponent
                    } catch { self.showError("The chart could not be saved: " + error.localizedDescription) }
                }
            }
        }
    }
    @objc func reportContextAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String], let kind = info["kind"], let doc = documents.first(where: { $0.id == info["document"] }) else { return }
        let value = info["value"] ?? ""
        switch kind {
        case "copyChart":
            let context = info["context"] ?? "", revision = Int(info["revision"] ?? "") ?? -1
            Task { @MainActor in
                do { _ = try await self.copyReportChart(doc, format: value, context: context, revision: revision) }
                catch {
                    if self.documents.contains(where: { $0 === doc }) { self.showError("The chart could not be copied: " + error.localizedDescription) }
                }
            }
        case "help": openHelp(root.appendingPathComponent(value), title: doc.title)
        case "ai": scriptAI.open(doc,reportResultID:value.isEmpty ? nil:value)
        case "r": continueResultInR(doc, id: value)
        case "selectResult": doc.web.evaluateJavaScript("StatsDirectReportEditor.selectResult(\(jsString(value)))")
        case "selectAll": doc.web.evaluateJavaScript("StatsDirectReportEditor.selectAll()")
        case "pictureFit": doc.web.evaluateJavaScript("StatsDirectReportEditor.command('pictureFit')")
        case "saveChart": saveReportChart(doc, format: value)
        case "pictureWidth": doc.web.evaluateJavaScript("(()=>{const more=document.getElementById('report-more-tools'),toggle=document.getElementById('report-more-toggle');if(more&&toggle){more.hidden=false;toggle.setAttribute('aria-expanded','true');}document.querySelector('[data-format=pictureWidth]')?.focus();})()")
        default: break
        }
    }
}
