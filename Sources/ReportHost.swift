import Cocoa
import WebKit

struct ReportEntry {
    let id: String
    let title: String
    let operation: String
    let body: String
    let rPlan: RScriptPlan?
    var editedBody: String?
    var annotation = ""
    var hiddenCharts: Set<Int> = []
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
    var bytes: Int { edits.reduce(0) { $0 + ($1.before?.utf8.count ?? 0) + ($1.after?.utf8.count ?? 0) } + (removed + added).reduce(0) { $0 + $1.bytes } }
}

extension Viewer {
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
        guard let entries = doc.reportEntries else { return }
        doc.rScriptPlan = entries.last?.rPlan
        doc.operationName = entries.last?.operation
        let body = "<div id='report-empty' class='report-controls' \(entries.isEmpty ? "" : "hidden")><p class='muted'>New analysis results will be collected here. Use Add text to write in this report.</p></div><div id='report-results' tabindex='-1'>" + entries.map { reportEntryHTML($0) }.joined() + "</div>"
        doc.hasSVG = body.contains("<svg")
        let notice = doc.reportImportNotice.map { "<p class='report-controls report-import-notice'>\(htmlEscape($0))</p>" } ?? ""
        let editor = (try? String(contentsOf: root.appendingPathComponent("Report/editor.js"), encoding: .utf8)) ?? ""
        let bootstrap = "<script>" + editor + "\nStatsDirectReportEditor.start({editing:\(doc.reportEditing),undo:\(!doc.reportUndo.isEmpty),redo:\(!doc.reportRedo.isEmpty)});</script>"
        doc.web.loadHTMLString(page(doc.title, reportToolbar(doc) + notice + body + bootstrap), baseURL: root)
    }

    func reportEntryHTML(_ entry: ReportEntry) -> String {
        let body=entry.editedBody ?? entry.body
        let hidden=entry.hiddenCharts.sorted().map(String.init).joined(separator: ",")
        return "<article class='report-entry' id='result-\(entry.id)'>" + "<div class='report-body' data-result-id='\(entry.id)' data-hidden-charts='\(hidden)' role='textbox' aria-label=\"Report content for \(htmlEscape(entry.title))\">" + body + "</div><div class='report-controls'><label>Report notes</label></div><div class='report-annotation' contenteditable='plaintext-only' role='textbox' aria-label=\"Notes for \(htmlEscape(entry.title))\" data-placeholder='Add your interpretation or notes…' oninput=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'annotate',resultID:'\(entry.id)',text:this.innerText})\">\(htmlEscape(entry.annotation))</div></article>"
    }
    func editReport(_ doc: Document, _ body: [String:Any]) {
        guard let action=body["action"] as? String else { return }
        if action == "transferNotice", let text = body["text"] as? String { status.stringValue = text; return }
        if action == "clipboard", let command = body["command"] as? String, ["copy", "cut", "paste"].contains(command) { reportClipboardCommand(doc, command: command); return }
        if action == "editing" { doc.reportEditing = body["value"] as? Bool ?? false; return }
        if action == "addText" {
            let entry = ReportEntry(id: UUID().uuidString, title: "Text", operation: "", body: "<p>Enter your text here.</p>", rPlan: nil)
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
        guard let id=body["resultID"] as? String,let index=doc.reportEntries?.firstIndex(where:{$0.id==id}) else { return }
        if action == "editBody" {
            if let html = body["html"] as? String { recordReportEdits(doc, edits: [["id": id, "html": html]], typing: body["typing"] as? Bool ?? false) }; return
        }
        if action == "annotate" {
            if let text=body["text"] as? String,text.utf8.count<=100_000 {
                if doc.reportEntries?[index].annotation != text { doc.reportRevision += 1 }
                doc.reportEntries?[index].annotation=text
            };return
        }
    }

    // A drag between result sections is one transaction, including both the
    // removal and insertion. Validate all sections before changing any of them.
    func recordReportEdits(_ doc: Document, edits: [[String: String]], removing: [String] = [], typing: Bool) {
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
        doc.rScriptPlan = entries.last?.rPlan; doc.operationName = entries.last?.operation
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
        add(menu,"Edit Report","toggle");menu.addItem(.separator())
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
        func button(_ name: String, _ label: String, _ value: String? = nil) -> String {
            let parameter = value.map { ",&quot;\(htmlEscape($0))&quot;" } ?? ""
            return "<button type='button' data-command='\(name)' onclick='StatsDirectReportEditor.command(&quot;\(name)&quot;\(parameter))'>\(label)</button>"
        }
        return """
        <div id='report-toolbar' class='report-controls report-toolbar' role='toolbar' aria-label='Report editing'>
        <button id='report-edit-toggle' onclick="StatsDirectReportEditor.command('toggle')">Edit report</button>
        \(button("addText", "Add text"))
        <div id='report-format-tools' hidden>
        </div></div>
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
        report.rScriptPlan = entry.rPlan; report.operationName = entry.operation
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
        let preview = page(entry.title, "<style>.report-links{display:none}body{padding:12px 18px}</style>" + entry.body)
        doc.web.evaluateJavaScript("window.\(bridge)?.showResult({id:\(jsString(entry.id)),page:\(jsString(preview))})")
        status.stringValue = "\(entry.title) complete · Add to report to keep these results"
    }

    func keepResult(_ doc: Document, id: String?) {
        guard let entry = doc.pendingResult, entry.id == id else { return }
        let report = appendReport(entry)
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        doc.web.evaluateJavaScript("window.\(bridge)?.resultKept(\(jsString(report.title)))")
    }
}
