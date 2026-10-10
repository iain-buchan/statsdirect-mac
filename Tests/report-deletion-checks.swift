import Cocoa
import PDFKit
import WebKit

extension ReportExportTests {
    @MainActor static func deletions(_ v: Viewer, output: URL) async throws {
        let report = v.makeReport()
        let first = ReportEntry(id: "delete-first", title: "First result", operation: "TPaired", body: """
        <h1 id="delete-heading">First result</h1><p id="delete-text">Alpha <strong>formatted finding</strong> Omega</p>
        <table id="delete-table"><tbody><tr><th colspan="2">Merged heading</th></tr><tr><td>Label A</td><td>12.5</td></tr><tr><td>Keep B</td><td>27</td></tr></tbody></table>
        <svg id="delete-svg" viewBox="0 0 300 150" width="300" height="150" style="width:240px;height:auto"><text x="20" y="70">Vector chart</text></svg>
        <p id="delete-tail">Unselected ending</p>
        """, rPlan: RScriptPlan(script: "# Deletion regression\nx <- 1", hasRecipe: true, detail: "Retained analysis recipe"), annotation: "Keep these notes")
        let middle = ReportEntry(id: "delete-middle", title: "Middle result", operation: "Example", body: "<h1 id='middle-heading'>Middle result</h1><p id='middle-text'>Middle finding</p>", rPlan: nil)
        let last = ReportEntry(id: "delete-last", title: "Last result", operation: "", body: "<h1 id='last-heading'>Last result</h1><p id='last-text'>Last finding retained</p><img id='delete-raster' width='1' height='1' src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='>", rPlan: nil)
        func js(_ script: String) async throws -> Any { try await report.web.evaluateJavaScript(script) ?? NSNull() }
        func check(_ expression: String, _ message: String) async throws {
            let ok = try await js(expression) as? Bool == true
            if !ok { print("Deletion failure:", message, try await js("document.getElementById('report-results').innerHTML")); fflush(stdout) }
            precondition(ok, message)
        }
        func reset(_ entries: [ReportEntry]? = nil) async throws {
            report.reportEntries = entries ?? [first, middle, last]; report.reportUndo = []; report.reportRedo = []; report.reportEditing = true
            v.renderReport(report); try await settled(report)
        }
        func key(_ name: String, modifiers: String = "") async throws {
            _ = try await js("document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:\(v.jsString(name)),bubbles:true,cancelable:true\(modifiers)}))")
            try await settled(report)
        }
        func undo() async throws { _ = try await js("StatsDirectReportEditor.command('undo')"); try await settled(report) }
        func redo() async throws { _ = try await js("StatsDirectReportEditor.command('redo')"); try await settled(report) }
        func select(_ selector: String, caret: Bool? = nil) async throws {
            _ = try await js("(()=>{const p=document.querySelector(\(v.jsString(selector)));p.closest('.report-body').focus();const r=document.createRange();r.selectNodeContents(p);\(caret.map { "r.collapse(\($0));" } ?? "")const s=getSelection();s.removeAllRanges();s.addRange(r);})()")
        }
        func click(_ selector: String, shift: Bool = false) async throws {
            _ = try await js("document.querySelector(\(v.jsString(selector))).dispatchEvent(new MouseEvent('click',{bubbles:true,shiftKey:\(shift)}))")
        }
        func nativeBackspace() async throws {
            v.window.makeKeyAndOrderFront(nil)
            v.window.makeFirstResponder(report.web)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: v.window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
            v.window.sendEvent(event); try await settled(report)
        }
        try await reset()
        try await check("![...document.querySelectorAll('button')].some(b=>/Remove result|Remove plot|Undo removal/.test(b.textContent))", "Obsolete removal controls remain")
        try await click("#delete-svg"); try await nativeBackspace()
        try await check("!document.getElementById('delete-svg')&&!!document.getElementById('delete-table')", "Native Backspace did not delete the selected SVG")
        precondition(report.reportUndo.count == 1)
        // A real Edit menu undo must route to the same history.
        let menu = NSMenuItem(title: "Undo", action: #selector(Viewer.editCommand(_:)), keyEquivalent: "z"); menu.representedObject = "undo"
        v.editCommand(menu); try await settled(report)
        try await check("document.getElementById('delete-svg').style.width==='240px'", "Menu undo did not restore SVG sizing")
        try await redo(); try await undo()
        try await click("#delete-raster"); try await key("Delete")
        try await check("!document.getElementById('delete-raster')", "Forward Delete did not remove raster")
        try await undo()
        for backward in [true, false] {
            _ = try await js("(()=>{const p=document.getElementById('delete-svg').closest('.report-media'),r=document.createRange();r.selectNode(p);r.collapse(\(!backward));const s=getSelection();p.closest('.report-body').focus();s.removeAllRanges();s.addRange(r);})()")
            try await key(backward ? "Backspace" : "Delete")
            try await check("!document.getElementById('delete-svg')", "Adjacent-caret chart deletion failed")
            try await undo()
        }
        try await select("#delete-tail", caret: true); try await key("Backspace")
        try await check("!document.getElementById('delete-svg')", "Backspace at the following paragraph did not delete the adjacent chart")
        try await undo()
        // A word between the caret and the chart prevents atomic chart removal.
        try await select("#delete-tail", caret: false); let count = report.reportUndo.count
        try await key("Backspace"); precondition(report.reportUndo.count == count)
        try await check("!!document.getElementById('delete-svg')", "Caret deletion skipped intervening text")
        print("PASS: selected SVG/raster Delete, real native Backspace, adjacent carets and native menu undo"); fflush(stdout)

        try await reset()
        try await select("#delete-text strong"); try await key("Delete")
        try await click("#middle-heading"); try await key("Backspace")
        precondition(report.reportEntries!.map(\.id) == [first.id, last.id] && report.reportUndo.count == 2)
        v.appendReport(ReportEntry(id: "delete-later", title: "Later output", operation: "Later", body: "<h1>Later output</h1><p>New engine result</p>", rPlan: nil)); try await settled(report)
        try await undo()
        precondition(report.reportEntries!.map(\.id) == [first.id, middle.id, last.id, "delete-later"])
        try await check("!document.getElementById('delete-text').textContent.includes('formatted finding')", "Undo removal also undid earlier text edit")
        try await undo()
        try await check("document.getElementById('delete-text').textContent.includes('formatted finding')&&document.body.textContent.includes('New engine result')", "Undo text lost later engine output")
        try await redo(); try await redo(); try await undo(); try await undo()
        try await click("#delete-heading"); try await click("#last-heading", shift: true); try await key("Backspace")
        precondition(report.reportEntries!.map(\.id) == ["delete-later"])
        try await undo()
        precondition(report.reportEntries!.map(\.id) == [first.id, middle.id, last.id, "delete-later"])
        precondition(report.reportEntries!.first!.annotation == first.annotation && report.reportEntries!.first!.operation == first.operation)
        let restoredPlan = report.reportEntries!.first!.rPlan!
        precondition(restoredPlan.script == first.rPlan!.script && restoredPlan.hasRecipe == first.rPlan!.hasRecipe && restoredPlan.detail == first.rPlan!.detail)
        print("PASS: chronological text/result undo/redo, grouped heading selection, original order/metadata and later engine output"); fflush(stdout)

        try await reset()
        _ = try await js("(()=>{const t=document.getElementById('delete-table'),r=document.createRange();t.closest('.report-body').focus();r.setStart(t.rows[1].cells[0].firstChild,6);r.setEnd(t.rows[1].cells[1].firstChild,2);const s=getSelection();s.removeAllRanges();s.addRange(r);})()")
        try await key("Delete")
        try await check("(()=>{const t=document.getElementById('delete-table');return t.rows.length===3&&t.rows[0].cells[0].colSpan===2&&t.rows[1].cells[0].textContent==='Label '&&t.rows[1].cells[1].textContent==='.5'&&t.rows[2].textContent==='Keep B27';})()", "Partial table deletion damaged unselected or merged cells")
        try await undo()
        _ = try await js("(()=>{const a=document.getElementById('delete-tail').firstChild,b=document.getElementById('last-text').firstChild,r=document.createRange();a.parentElement.closest('.report-body').focus();r.setStart(a,11);r.setEnd(b,5);const s=getSelection();s.removeAllRanges();s.addRange(r);})()")
        try await key("Backspace")
        precondition(report.reportEntries!.map(\.id) == [first.id, last.id] && report.reportUndo.count == 1 && report.reportUndo.last!.edits.count == 2)
        try await check("document.getElementById('delete-tail').textContent==='Unselected '&&document.getElementById('last-text').textContent==='finding retained'&&!!document.getElementById('delete-table')", "Cross-result deletion damaged the surviving edges")
        try await undo(); try await redo(); try await undo()
        try await select("#delete-tail", caret: false); try await key("a", modifiers: ",metaKey:true"); try await key("Delete")
        precondition(report.reportEntries!.isEmpty)
        try await check("document.activeElement.id==='report-results'&&!document.getElementById('report-empty').hidden", "All-deleted report lost its keyboard focus or empty state")
        let empty = String(decoding: try await v.reportExportData(report, format: .html), as: UTF8.self)
        precondition(!empty.contains("First result") && !empty.contains("Middle finding") && !empty.contains("New analysis results"))
        try await key("z", modifiers: ",metaKey:true")
        precondition(report.reportEntries!.map(\.id) == [first.id, middle.id, last.id])
        try await key("z", modifiers: ",metaKey:true,shiftKey:true")
        precondition(report.reportEntries!.isEmpty); try await undo()
        try await reset([ReportEntry(id: "empty-result", title: "Empty", operation: "", body: "", rPlan: nil)])
        try await select(".report-body"); try await key("a", modifiers: ",metaKey:true"); try await key("Delete")
        precondition(report.reportEntries!.isEmpty); try await key("z", modifiers: ",metaKey:true")
        precondition(report.reportEntries!.first!.id == "empty-result")
        print("PASS: partial/merged tables, mixed deletion across results, Command-A, all-deleted and initially empty reports, keyboard undo/redo"); fflush(stdout)

        try await reset()
        try await select("#delete-text strong")
        _ = try await js("document.activeElement.dispatchEvent(new InputEvent('beforeinput',{inputType:'deleteContentForward',bubbles:true,cancelable:true}))")
        try await settled(report); precondition(report.reportUndo.count == 1)
        try await check("!document.getElementById('delete-text').textContent.includes('formatted finding')", "Contextual/accessibility deletion failed")
        try await select("#delete-tail")
        try await key("Backspace", modifiers: ",isComposing:true"); precondition(report.reportUndo.count == 1)
        _ = try await js("document.querySelector('[data-format=fontSize]').focus()")
        try await key("z", modifiers: ",metaKey:true"); try await key("Backspace"); precondition(report.reportUndo.count == 1)
        try await check("!StatsDirectReportEditor.menuCommand('undo')&&!StatsDirectReportEditor.menuCommand('selectAll')", "Toolbar input commands escaped into report history")
        _ = try await js("document.querySelector('.report-annotation').focus()")
        try await key("z", modifiers: ",metaKey:true"); precondition(report.reportUndo.count == 1)
        try await check("!StatsDirectReportEditor.menuCommand('undo')", "Notes input undo escaped into report history")
        _ = try await js("StatsDirectReportEditor.setEditing(false)")
        try await select("#delete-tail"); try await key("Backspace"); try await key("z", modifiers: ",metaKey:true")
        precondition(report.reportUndo.count == 1)
        try await check("document.getElementById('delete-tail').textContent==='Unselected ending'", "Read-only selection was deleted")
        _ = try await js("StatsDirectReportEditor.setEditing(true)")
        try await click("#middle-heading"); try await key("Delete"); try await undo()
        v.editReport(report, ["action": "annotate", "resultID": middle.id, "text": "Updated notes"])
        try await redo(); try await undo()
        precondition(report.reportEntries!.first(where: { $0.id == middle.id })!.annotation == "Updated notes")
        // Add text is structural editing too, with the same chronology.
        v.editReport(report, ["action": "addText"]); try await settled(report)
        let addedID = report.reportEntries!.last!.id
        try await undo(); precondition(!report.reportEntries!.contains { $0.id == addedID })
        try await redo(); precondition(report.reportEntries!.last!.id == addedID)
        print("PASS: beforeinput deletion, composition/read-only/input guards, updated notes across redo, and Add text undo"); fflush(stdout)

        try await reset()
        try await click("#middle-heading"); try await key("Delete")
        for format in ReportFormat.allCases { try await v.reportExportData(report, format: format).write(to: output.appendingPathComponent("selection-deleted." + format.rawValue)) }
        let html = try String(contentsOf: output.appendingPathComponent("selection-deleted.html"), encoding: .utf8)
        precondition(html.contains("First result") && html.contains("Last finding retained") && !html.contains("Middle finding") && html.contains("<svg") && html.contains("colspan=\"2\""))
        let pdf = PDFDocument(url: output.appendingPathComponent("selection-deleted.pdf"))!
        precondition(pdf.string!.contains("First result") && !pdf.string!.contains("Middle finding"))
        let reopened = try await v.importReport(output.appendingPathComponent("selection-deleted.html")); try await settled(reopened)
        let visible = try await reopened.web.evaluateJavaScript("document.getElementById('report-results').textContent") as! String
        precondition(visible.contains("Last finding retained") && !visible.contains("Middle finding") && !reopened.reportDirty)
        v.remove(reopened); v.tabs.selectTabViewItem(report.item)
        print("PASS: deleted results stay absent in HTML/PDF/DOCX and reopened HTML; surviving tables and vector charts remain"); fflush(stdout)
    }
}
