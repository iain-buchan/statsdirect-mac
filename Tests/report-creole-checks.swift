import Cocoa
import PDFKit

extension ReportExportTests {
    @MainActor static func creolePresentation(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Every presentation tag emitted by CreoleHtmlReportRenderer. Expected
        // values come from the Windows report defaults, without injecting CSS.
        let html = """
        <h1>Creole title</h1><h2>Creole subtitle</h2><p>Creole body</p>
        <p><span class="ci">Confidence interval</span><br><span class="pval">P value</span><br>
        <span class="score">Test score</span><br><span class="warn">Warning</span><br>
        <span class="subtotal">Subtotal</span><br><span class="model">Model</span><br>
        <span class="grandtotal">Grand total</span></p>
        <p><b>Bold</b> <i>Italic</i> <u>Underline</u> x<sub>Subscript</sub> x<sup>Superscript</sup></p>
        <pre>Preformatted  text</pre>
        <table><thead><tr><th colspan="2">Creole table header</th></tr></thead>
        <tbody><tr><td>Value</td><td>12.500</td></tr></tbody></table>
        <p><span class="ci" style="color:#663399;font-family:Georgia;font-size:18pt">User override</span></p>
        """
        let report = v.makeReport()
        let operation = v.newDocument(kind: "operation", title: "Host form title")
        operation.operationName = "TPaired"
        v.finishOperationReport(operation, ["html": html], frames: [], note: nil)
        try await settled(report)
        precondition(report.reportEntries?.count == 1)
        precondition(try await report.web.evaluateJavaScript("document.querySelectorAll('.report-body h1').length===1&&!document.querySelector('.report-body .eyebrow')") as? Bool == true, "use the engine title once, without a generic host heading")
        let snapshot = """
        (()=>{const root=document.querySelector('.report-body')||document.body;
          return Object.fromEntries([...root.querySelectorAll('h1,h2,p,span,b,i,u,sub,sup,pre,th,td')].filter(e=>e.children.length===0).map(e=>{
            const s=getComputedStyle(e);return [e.textContent,{font:s.fontFamily.split(',')[0].replaceAll('"',''),size:Math.round(parseFloat(s.fontSize)*100)/100,weight:s.fontWeight,style:s.fontStyle,color:s.color,decoration:s.textDecorationLine,align:s.textAlign,border:s.borderBottomStyle,background:s.backgroundColor,padding:s.paddingRight,margin:s.marginTop,vertical:s.verticalAlign}];
          }));})()
        """
        let expected = try await report.web.evaluateJavaScript(snapshot) as! [String: [String: Any]]
        func value(_ text: String, _ property: String) -> String { expected[text]?[property] as? String ?? "" }
        precondition(value("Creole body", "font") == "Arial" && expected["Creole body"]?["size"] as? Double == 13.33 && value("Creole body", "color") == "rgb(0, 0, 0)" && value("Creole body", "margin") == "0px", "Arial 10pt black body and compact paragraph spacing")
        precondition(value("Creole title", "weight") == "700" && value("Creole title", "decoration") == "underline" && expected["Creole title"]?["size"] as? Double == 13.33 && value("Creole subtitle", "weight") == "400" && value("Creole subtitle", "decoration") == "underline", "Creole title and subtitle typography")
        for (label, color) in ["Confidence interval":"rgb(0, 0, 255)", "P value":"rgb(0, 127, 0)", "Test score":"rgb(0, 127, 127)", "Warning":"rgb(255, 0, 0)", "Subtotal":"rgb(127, 0, 0)", "Model":"rgb(0, 0, 127)", "Grand total":"rgb(0, 0, 127)"] {
            precondition(value(label, "color") == color, "Windows Creole colour for \(label): \(value(label, "color"))")
        }
        precondition(value("Bold", "weight") == "700" && value("Italic", "style") == "italic" && value("Underline", "decoration") == "underline" && value("Subscript", "vertical") == "sub" && value("Superscript", "vertical") == "super")
        precondition(value("Preformatted  text", "font") == "Courier New" && expected["Preformatted  text"]?["size"] as? Double == 13.33)
        precondition(value("Creole table header", "weight") == "400" && value("Creole table header", "decoration") == "underline" && value("Creole table header", "background") == "rgba(0, 0, 0, 0)")
        precondition(value("12.500", "align") == "left" && value("12.500", "border") == "none" && value("12.500", "padding") == "9px" && expected["12.500"]?["size"] as? Double == 13.33)
        precondition(try await report.web.evaluateJavaScript("document.querySelector('.report-body table').getBoundingClientRect().width < document.querySelector('.report-body').clientWidth/2") as? Bool == true, "Creole table sizes to content")
        precondition(value("User override", "font") == "Georgia" && value("User override", "color") == "rgb(102, 51, 153)" && expected["User override"]?["size"] as? Double == 24, "user formatting overrides Creole defaults")
        precondition(try await report.web.evaluateJavaScript("[...document.querySelectorAll('.report-toolbar button svg')].every(s=>Math.abs(s.getBoundingClientRect().width-20)<1||s.getBoundingClientRect().width===0)") as? Bool == true, "report defaults do not resize toolbar symbols")
        print("PASS: every Creole style matches Windows, plain compact tables, one engine title, inline overrides and compact toolbar symbols"); fflush(stdout)

        func same(_ doc: Document, _ message: String) async throws {
            let actual = try await doc.web.evaluateJavaScript(snapshot) as! [String: [String: Any]]
            precondition(NSDictionary(dictionary: actual).isEqual(to: expected), message + "\n" + String(describing: actual))
        }
        // Exercise the real instant-answer bridge rather than a separate CSS fixture.
        operation.web.loadHTMLString("<script>window.statsDirectOperation={showResult(result){window.preview=result.page;}}</script>", baseURL: v.root)
        try await settled(operation)
        v.previewResult(report.reportEntries![0], in: operation)
        let preview = try await operation.web.evaluateJavaScript("window.preview") as! String
        operation.web.loadHTMLString(preview, baseURL: v.root); try await settled(operation)
        try await same(operation, "instant answers must match the report")
        for format in ReportFormat.allCases {
            let data = try await v.reportExportData(report, format: format)
            try data.write(to: output.appendingPathComponent("creole-report." + format.rawValue))
            if format == .pdf {
                let pdf = PDFDocument(data: data)!
                precondition(pdf.string!.contains("Creole title") && pdf.string!.contains("12.500"))
                let fonts = pdf.findString("Creole body", withOptions: []).compactMap { $0.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont }
                precondition(fonts.contains { $0.fontName.contains("Arial") }, "PDF uses the report font")
            }
        }
        let reopened = try await v.importReport(output.appendingPathComponent("creole-report.html")); try await settled(reopened)
        try await same(reopened, "HTML reopening must retain Creole styles")
        try await v.reportExportData(reopened, format: .docx).write(to: output.appendingPathComponent("creole-reopened.docx"))
        // Bare engine markup and Windows HTML use the same defaults in the
        // isolated importer before classes are removed during sanitizing.
        let raw = output.appendingPathComponent("creole-raw.html")
        try html.write(to: raw, atomically: true, encoding: .utf8)
        let imported = try await v.importReport(raw); try await settled(imported)
        try await same(imported, "bare Creole HTML must not lose its classes' presentation on import")
        let windowsCSS = try String(contentsOfFile: "FullEngine/Upstream/StatsDirectUI/Assets/ReportEditor/windows.css", encoding: .utf8)
        try ("<html><head><style>" + windowsCSS + "</style></head><body class='engine-report'>" + html + "</body></html>").write(to: raw, atomically: true, encoding: .utf8)
        let windows = try await v.importReport(raw); try await settled(windows)
        try await same(windows, "Windows styled HTML must match Mac report content")

        v.tabs.selectTabViewItem(report.item)
        try await report.web.evaluateJavaScript("document.querySelector('.report-body').focus();getSelection().selectAllChildren(document.querySelector('.report-body'))")
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        _ = try await v.transferReportClipboard(report, command: "copy", pasteboard: board)
        let clipboard = board.string(forType: .html)!
        try clipboard.write(to: output.appendingPathComponent("creole-clipboard.html"), atomically: true, encoding: .utf8)
        let pasted = v.makeReport()
        try await settled(pasted)
        try await pasted.web.evaluateJavaScript("const r=document.querySelector('.report-body');r.focus();getSelection().selectAllChildren(r)")
        // Public Office HTML exercises both presentation inlining and import.
        board.clearContents(); board.setString(clipboard, forType: .html)
        _ = try await v.transferReportClipboard(pasted, command: "paste", pasteboard: board); try await settled(pasted)
        let colors = try await pasted.web.evaluateJavaScript("[...document.querySelectorAll('.report-body span')].filter(s=>s.textContent==='P value').map(s=>getComputedStyle(s).color)") as! [String]
        precondition(colors.contains("rgb(0, 127, 0)"), "public clipboard preserves the Creole palette")
        precondition(pasted.reportUndo.count == 1, "pasting remains a single undo")
        for doc in [pasted, windows, imported, reopened, operation, report] { v.remove(doc) }
        print("PASS: Creole instant answers, HTML/PDF/DOCX export, HTML/Windows import and public clipboard; Word styles checked separately"); fflush(stdout)
    }
}
