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

struct ReportTextChange {
    var edits: [ReportBodyChange]
    var time = Date()
    var typing: Bool
    var bytes: Int { edits.reduce(0) { $0 + ($1.before?.utf8.count ?? 0) + ($1.after?.utf8.count ?? 0) } }
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
        let body = entries.isEmpty
            ? "<h1>\(htmlEscape(doc.title))</h1><p class='muted'>New analysis results will be collected here. Use Add to report to keep results from instant-answer forms.</p>"
            : entries.map { reportEntryHTML($0) }.joined()
        doc.hasSVG = body.contains("<svg")
        let notice = doc.reportImportNotice.map { "<p class='report-controls report-import-notice'>\(htmlEscape($0))</p>" } ?? ""
        let editor = (try? String(contentsOf: root.appendingPathComponent("Report/editor.js"), encoding: .utf8)) ?? ""
        let bootstrap = "<script>" + editor + "\nStatsDirectReportEditor.start({editing:\(doc.reportEditing),undo:\(!doc.reportTextUndo.isEmpty),redo:\(!doc.reportTextRedo.isEmpty)});</script>"
        doc.web.loadHTMLString(page(doc.title, reportToolbar(doc) + notice + body + bootstrap), baseURL: root)
    }

    func reportEntryHTML(_ entry: ReportEntry) -> String {
        let body=entry.editedBody ?? entry.body
        let hidden=entry.hiddenCharts.sorted().map(String.init).joined(separator: ",")
        return "<article class='report-entry' id='result-\(entry.id)'>" + "<div class='report-body' data-result-id='\(entry.id)' data-hidden-charts='\(hidden)' role='textbox' aria-label=\"Report content for \(htmlEscape(entry.title))\">" + body + "</div><div class='report-controls'><label>Report notes</label><button onclick=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'removeResult',resultID:'\(entry.id)'})\">Remove result</button></div><div class='report-annotation' contenteditable='plaintext-only' role='textbox' aria-label=\"Notes for \(htmlEscape(entry.title))\" data-placeholder='Add your interpretation or notes…' oninput=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'annotate',resultID:'\(entry.id)',text:this.innerText})\">\(htmlEscape(entry.annotation))</div></article>"
    }
    func editReport(_ doc: Document, _ body: [String:Any]) {
        guard let action=body["action"] as? String else { return }
        if action == "transferNotice", let text = body["text"] as? String { status.stringValue = text; return }
        if action == "clipboard", let command = body["command"] as? String, ["copy", "cut", "paste"].contains(command) { reportClipboardCommand(doc, command: command); return }
        if action == "editing" { doc.reportEditing = body["value"] as? Bool ?? false; return }
        if action == "addText" {
            let entry = ReportEntry(id: UUID().uuidString, title: "Text", operation: "", body: "<p>Enter your text here.</p>", rPlan: nil)
            doc.reportEntries?.append(entry)
            for undo in doc.reportUndo.indices { doc.reportUndo[undo].append(entry) }
            doc.reportEditing = true; doc.reportRevision += 1; doc.scrollToResultID = entry.id
            renderReport(doc); return
        }
        if action == "undoText" || action == "redoText" {
            let undo = action == "undoText"
            guard let change = undo ? doc.reportTextUndo.popLast() : doc.reportTextRedo.popLast() else { return }
            if undo { doc.reportTextRedo.append(change) } else { doc.reportTextUndo.append(change) }
            var replacements: [[String: String]] = []
            for edit in change.edits {
                updateReportText(doc, id: edit.id, html: undo ? edit.before : edit.after, refresh: false)
                if let entry = doc.reportEntries?.first(where: { $0.id == edit.id }) {
                    replacements.append(["id": edit.id, "html": reportEntryHTML(entry)])
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: replacements), let json = String(data: data, encoding: .utf8) {
                doc.web.evaluateJavaScript("StatsDirectReportEditor.replaceEntries(\(json))")
            }
            reportEditHistory(doc); return
        }
        if action == "undoReport" {
            if let previous=doc.reportUndo.popLast() { doc.reportEntries=previous;doc.reportRevision += 1;renderReport(doc) };return
        }
        if action == "editBodies", let edits = body["edits"] as? [[String: String]] {
            recordReportEdits(doc, edits: edits, typing: false); return
        }
        guard let id=body["resultID"] as? String,let index=doc.reportEntries?.firstIndex(where:{$0.id==id}) else { return }
        if action == "editBody" {
            if let html = body["html"] as? String { recordReportEdits(doc, edits: [["id": id, "html": html]], typing: body["typing"] as? Bool ?? false) }; return
        }
        if action == "annotate" {
            if let text=body["text"] as? String,text.utf8.count<=100_000 {
                if doc.reportEntries?[index].annotation != text { doc.reportRevision += 1 }
                doc.reportEntries?[index].annotation=text
                for undo in doc.reportUndo.indices {
                    if let item=doc.reportUndo[undo].firstIndex(where:{$0.id==id}) { doc.reportUndo[undo][item].annotation=text }
                }
            };return
        }
        guard action == "removeResult" || action == "hideChart" else { return }
        if action == "hideChart" { guard let chart=body["index"] as? Int,chart>=0,chart<1000 else {return} }
        doc.reportRevision += 1
        doc.reportUndo.append(doc.reportEntries!);if doc.reportUndo.count>20 {doc.reportUndo.removeFirst()}
        if action == "removeResult" {doc.reportEntries?.remove(at:index)}
        else {doc.reportEntries?[index].hiddenCharts.insert(body["index"] as! Int)}
        renderReport(doc)
    }

    // A drag between result sections is one transaction, including both the
    // removal and insertion. Validate all sections before changing any of them.
    func recordReportEdits(_ doc: Document, edits: [[String: String]], typing: Bool) {
        guard !edits.isEmpty, edits.count <= (doc.reportEntries?.count ?? 0), Set(edits.compactMap { $0["id"] }).count == edits.count else { return }
        var changes: [ReportBodyChange] = []
        for edit in edits {
            guard let id = edit["id"], let html = edit["html"], html.utf8.count <= 30_000_000,
                  let entry = doc.reportEntries?.first(where: { $0.id == id }) else { return }
            if html != (entry.editedBody ?? entry.body) { changes.append(ReportBodyChange(id: id, before: entry.editedBody, after: html)) }
        }
        guard !changes.isEmpty else { return }
        if changes.count == 1, let last = doc.reportTextUndo.last, last.edits.count == 1,
           last.edits[0].id == changes[0].id, last.typing, typing, Date().timeIntervalSince(last.time) < 1.0, doc.reportTextRedo.isEmpty {
            doc.reportTextUndo[doc.reportTextUndo.count - 1].edits[0].after = changes[0].after
            doc.reportTextUndo[doc.reportTextUndo.count - 1].time = Date()
        } else { doc.reportTextUndo.append(ReportTextChange(edits: changes, typing: typing)) }
        while doc.reportTextUndo.count > 50 || (doc.reportTextUndo.count > 1 && doc.reportTextUndo.reduce(0, { $0 + $1.bytes }) > 60_000_000) { doc.reportTextUndo.removeFirst() }
        doc.reportTextRedo = []
        for change in changes { updateReportText(doc, id: change.id, html: change.after, refresh: false) }
        doc.hasSVG = doc.reportEntries?.contains(where: { ($0.editedBody ?? $0.body).contains("<svg") }) ?? false
        reportEditHistory(doc)
    }

    func reportEditHistory(_ doc: Document) {
        doc.web.evaluateJavaScript("StatsDirectReportEditor.history(\(!doc.reportTextUndo.isEmpty),\(!doc.reportTextRedo.isEmpty))")
    }
    func updateReportText(_ doc: Document, id: String, html: String?, refresh: Bool) {
        guard let index = doc.reportEntries?.firstIndex(where: { $0.id == id }) else { return }
        doc.reportEntries?[index].editedBody = html; doc.reportRevision += 1
        doc.hasSVG = doc.reportEntries?.contains(where: { ($0.editedBody ?? $0.body).contains("<svg") }) ?? false
        for undo in doc.reportUndo.indices {
            if let item = doc.reportUndo[undo].firstIndex(where: { $0.id == id }) { doc.reportUndo[undo][item].editedBody = html }
        }
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
        <button onclick="window.webkit.messageHandlers.statsDirectReport.postMessage({action:'undoReport'})" \(doc.reportUndo.isEmpty ? "disabled" : "")>Undo removal</button>
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
        // Restoring a removal must retain analyses added since that removal.
        for undo in report.reportUndo.indices { report.reportUndo[undo].append(entry) }
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
