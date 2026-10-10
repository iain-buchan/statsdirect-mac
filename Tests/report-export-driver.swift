import Cocoa
import PDFKit

@main struct ReportExportTests {
    // A failed integration check should exit with a diagnostic, not raise a
    // Swift trap and leave a macOS "quit unexpectedly" dialog on the desktop.
    static func precondition(_ ok:Bool,_ message:String="Report check failed",file:StaticString=#fileID,line:UInt=#line) {
        guard ok else {print("FAIL: \(message) (\(file):\(line))");fflush(stdout);exit(1)}
    }

    @MainActor static func main() {
        guard CommandLine.arguments.count>1 else {
            print("Run this test host with Scripts/test-report-export.sh and an output directory.");exit(2)
        }
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let viewer=Viewer();app.delegate=viewer
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do {
                    if let index=CommandLine.arguments.firstIndex(where:{$0=="--legacy-file" || $0=="--report-file"}),index+1<CommandLine.arguments.count {
                        try await archived(viewer, url:URL(fileURLWithPath:CommandLine.arguments[index+1]), output:URL(fileURLWithPath:CommandLine.arguments[1]))
                    } else if CommandLine.arguments.contains("--deletion-only") {try await deletions(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1]))}
                    else if CommandLine.arguments.contains("--presentation-only") {try await presentation(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1]))}
                    else if CommandLine.arguments.contains("--transfer-only") {try await transfers(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1]))}
                    else if CommandLine.arguments.contains("--legacy-only") {try await legacy(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1]))} else {try await run(viewer)}
                    print("PASS: native report exports");fflush(stdout)}
                catch {print("FAIL:",error.localizedDescription,(error as NSError).userInfo);fflush(stdout);exit(1)}
                if !CommandLine.arguments.contains("--stay-open") {viewer.closeApproved=true;app.terminate(nil)}
            }
        }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func dataset(_ columns:[[Int]]) -> [String:Any] {
            ["complete":true,"rowCount":columns[0].count,"columns":columns.enumerated().map{["title":$0.offset==0 ? "Before":"After","values":$0.element,"index":$0.offset]}]
        }
        for (operation,values) in [("TPaired",[[312,242,340,388,296,254,391,402,290],[300,201,232,312,220,256,328,330,231]]),("Chi2by2",[[12,3],[8,17]])] {
            let result=try await TutorTools.run(operation:operation,dataset:dataset(values),agreement:operation=="TPaired",studyType:"neither",preferences:[:]) { request in
                try await withCheckedThrowingContinuation { c in v.analysisRequest(request,entry:"statsdirect_operation"){c.resume(with:$0)} }
            }
            let entryID=UUID().uuidString
            let plan=try RScriptGenerator.generate(operation:operation,title:operation,output:result,resources:v.root)
            let body="<section class='engine-report'>"+(result["html"] as! String)+"</section>"+v.reportLinks(plan,helpPath:v.analysisCatalog[operation]?["help"] as? String,resultID:entryID)
            v.appendReport(ReportEntry(id:entryID,title:operation,operation:operation,body:body,rPlan:plan))
        }
        // LOESS runs its script through R, and its chart is the PNG R drew: it must reach the pane and every export like the engine's SVG charts.
        do {
            func check(_ ok:Bool,_ message:String) throws { if !ok { throw NSError(domain:"ReportExportTests",code:1,userInfo:[NSLocalizedDescriptionKey:message]) } }
            let y=[12,13,11,15,14,13,12,16,15,14,13,12,11,11,13,14], x=[90,85,60,95,80,70,65,99,92,88,75,55,50,48,77,83]
            func frame(_ title:String,_ values:[Int]) -> [String:Any] { ["source":"Export test","columns":[["title":title,"values":values]]] }
            func request(_ body:[String:Any]) async throws -> [String:Any] { try await withCheckedThrowingContinuation { c in v.analysisRequest(body,entry:"statsdirect_operation"){c.resume(with:$0)} } }
            let id=UUID().uuidString
            var output=try await request(["action":"start","id":id,"operation":"LOESS"])
            let deadline=Date().addingTimeInterval(60)
            while Date()<deadline, !["complete","failed","cancelled"].contains(output["state"] as? String ?? "") {
                if output["state"] as? String=="input", let prompt=output["prompt"] as? [String:Any], let token=output["token"] {
                    try check((prompt["error"] as? String ?? "").isEmpty,"LOESS prompt error: \(prompt)")
                    let name=prompt["name"] as? String ?? "", kind=prompt["kind"] as? String ?? ""
                    let value:Any = name=="outcome" ? frame("Hgb",y) : name=="predictors" ? frame("eGFR",x) : name=="saveRScript" ? true
                        : kind=="boolean" ? (prompt["defaultValue"] as? Bool ?? false) : kind=="option" ? ((prompt["options"] as? [[String:Any]])?.first?["value"] ?? "") : (prompt["defaultValue"] ?? "")
                    output=try await request(["action":"answer","id":id,"token":token,"value":value])
                } else { try await Task.sleep(nanoseconds:50_000_000); output=try await request(["action":"poll","id":id]) }
            }
            _=try? await request(["action":"release","id":id])
            try check(output["state"] as? String=="complete","LOESS did not complete: \(output["error"] ?? "")")
            let html=output["html"] as? String ?? ""
            try check(html.contains("<svg") && html.contains("</svg>") && !html.contains("data:image/png;base64,") && html.contains("userdir &lt;-") && html.contains("Residual Standard Error"),"LOESS report lacks R's SVG chart or script")
            v.appendReport(ReportEntry(id:UUID().uuidString,title:"LOESS",operation:"LOESS",body:"<section class='engine-report'>"+html+"</section>",rPlan:nil))
            print("PASS: LOESS through R: the report carries R's chart as inline SVG and the script");fflush(stdout)
        }
        let rows=(1...65).map{"<tr><td>Observation \($0)</td><td>\($0).25</td><td>-2.5</td><td>1.2e-7</td></tr>"}.joined()
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Export table checks",operation:"",body:"<h1>Export table checks</h1><table><thead><tr><th rowspan='2'>Measurement</th><th colspan='3'>Results</th></tr><tr><th>Estimate</th><th>Difference</th><th>P value</th></tr></thead><tbody>\(rows)</tbody></table><p><strong>All report entries included</strong> — α = 0.05, 95% CI, χ<sup>2</sup> and CO<sub>2</sub>.</p>",rPlan:nil))
        let report=v.active!
        for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        let chartFonts=try await report.web.evaluateJavaScript("[...document.querySelectorAll('.engine-report svg text')].every(el=>getComputedStyle(el).fontFamily.includes('Arial'))") as! Bool
        precondition(chartFonts,"New engine SVG charts must use Arial")
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("combined-report."+format.rawValue))
            if format == .html {
                let html=String(decoding:data,as:UTF8.self)
                precondition(html.contains("56.111111")&&html.contains("8.64")&&html.contains("Observation 65"))
                precondition(html.contains("<svg")&&html.contains("https://www.statsdirect.com/help/"))
                precondition(html.contains("Residual Standard Error")&&html.contains("svglite"),"the LOESS report's inline SVG chart must survive HTML export")
                precondition(!html.contains("onclick=") && !html.contains("statsDirectReport.postMessage") && !html.contains("file:///"))
                print("PASS: HTML contains every result, inline vector charts including R's, and portable help links; no app handlers or file paths")
            }
            if format == .pdf {
                let pdf=PDFDocument(data:data)!,text=pdf.string ?? ""
                precondition(pdf.pageCount>1&&text.contains("56.111111")&&text.contains("Observation 65")&&text.contains("All report entries included"))
                for i in 0..<pdf.pageCount {let rect=pdf.page(at:i)!.bounds(for:.mediaBox);precondition(rect.height<900&&rect.width<650)}
                print("PASS: paginated PDF contains all results across \(pdf.pageCount) A4 pages")
            }
            print("Wrote",format.rawValue,data.count,"bytes");fflush(stdout)
        }
        // Exercise the actual WebKit selection path without changing the system clipboard.
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.body)")
        let copied=try await v.reportScript(report,method:"clipboard")!
        let clipboard=try JSONSerialization.jsonObject(with:Data(copied.utf8)) as! [String:String]
        precondition(clipboard["html"]!.contains("data:image/png;base64,") && !clipboard["html"]!.contains("<svg"))
        precondition(clipboard["html"]!.contains("x:str=\"Observation 65\"") && clipboard["html"]!.contains("mso-number-format"))
        precondition(clipboard["text"]!.contains("Observation 65\t65.25\t-2.5\t1.2e-7"))
        precondition(!clipboard["text"]!.contains("220240") && !clipboard["html"]!.contains("Continue in R"))
        try Data(clipboard["html"]!.utf8).write(to:output.appendingPathComponent("clipboard.html"))
        try await report.web.evaluateJavaScript("let row=document.querySelector('table').rows[1];let range=document.createRange();range.selectNodeContents(row);let sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);")
        let partial=try await v.reportScript(report,method:"clipboard")!
        let part=try JSONSerialization.jsonObject(with:Data(partial.utf8)) as! [String:String]
        precondition(part["text"]=="3\t17\t20" && part["html"]!.contains("<table"))
        try await report.web.evaluateJavaScript("window.getSelection().removeAllRanges()")
        let empty=try await v.reportScript(report,method:"clipboard")
        precondition(empty==nil)
        print("PASS: full report, partial table row and empty selection clipboard paths; numbers, labels, chart and TSV")
        // Reopened standalone HTML must support all export formats too.
        let reopened=try await v.importReport(output.appendingPathComponent("combined-report.html"))
        for _ in 0..<100 where reopened.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        let roundtrip=try await v.reportExportData(reopened,format:.docx)
        try roundtrip.write(to:output.appendingPathComponent("reopened-report.docx"))
        print("PASS: standalone HTML reopens and exports to DOCX")
        v.tabs.selectTabViewItem(report.item)
        try await editing(v, report: report, output: output)
        try await singleRegion(v, output: output)
        try await chartResizing(v, report: report, output: output)
        try await transfers(v, output: output)
        try await deletions(v, output: output)
        try await legacy(v, output: output)
        try await semanticContainers(v, output: output)
        try await stylesheetPresentation(v, output: output)
        try await presentation(v, output: output)
    }

    @MainActor static func presentation(_ v: Viewer, output: URL) async throws {
        func check(_ ok:Bool,_ message:String="Report presentation check failed") throws {
            guard ok else {throw NSError(domain:"ReportPresentation",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
        }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let report=v.makeReport()
        report.reportEntries=[ReportEntry(id:UUID().uuidString,title:"Copy/export presentation",operation:"",body:"""
        <section class="presentation-fixture">
        <h2>Custom heading</h2><p>Custom paragraph</p>
        <table class="plain"><thead><tr><th>Plain heading</th><th>Value</th></tr></thead><tbody>
        <tr><td>Precision</td><td>12.500</td></tr><tr><td>Percentage</td><td>95.00%</td></tr>
        <tr><td>Exponent</td><td>1.20e-7</td></tr><tr><td>Negative</td><td>−2.50</td></tr>
        <tr><td>Identifier</td><td>0012</td></tr><tr><td>Long identifier</td><td>1234567890123456</td></tr><tr><td>Formula text</td><td>=1+1</td></tr>
        </tbody></table>
        <table class="custom"><colgroup><col style="width:220px"><col style="width:140px"></colgroup><tbody><tr><td class="special">Custom cell</td><td>Row fill</td></tr></tbody></table>
        <pre>Preformatted  spaces\n<strong style="color:#cc0000">Bold second line</strong> <code style="font-family:Arial">Explicit code font</code></pre>
        </section>
        """,rPlan:nil)]
        v.renderReport(report);try await settled(report)
        try await report.web.evaluateJavaScript("""
        (()=>{const s=document.createElement('style');s.textContent=`
        .presentation-fixture h2{font:normal 16pt Georgia;color:#663399;margin:12px 0 8px;text-align:center}
        .presentation-fixture p{font:normal 12pt Arial;margin:8px 0 12px;line-height:1.5}
        .presentation-fixture .plain,.presentation-fixture .plain th,.presentation-fixture .plain td{font:normal 10pt Arial;color:#222222;background:transparent;border:none;text-align:left;padding:2px 4px}
        .presentation-fixture .plain thead{background:transparent}
        .presentation-fixture .plain th{text-decoration:underline}
        .presentation-fixture .custom{border:2px solid #008000}
        .presentation-fixture .custom tr{background:#ddffee}
        .presentation-fixture .custom td{border:none}
        .presentation-fixture .custom .special{font:normal 18pt Georgia;color:#663399;background:#ffff00;text-align:center;vertical-align:middle;padding:6px 10px;border-top:2px solid #cc0000;border-bottom:3px dashed #0000cc;border-left:1px dotted #660066;border-right:none}
        .presentation-fixture pre{font:normal 14pt Georgia;white-space:pre-wrap;color:#224466;margin:10px 0;line-height:1.25}
        `;document.head.append(s);})()
        """)
        let description="""
        (()=>{const names=['fontFamily','fontSize','fontWeight','fontStyle','color','backgroundColor','textAlign','textDecorationLine','verticalAlign','paddingTop','paddingRight','paddingBottom','paddingLeft','borderTopStyle','borderTopWidth','borderTopColor','borderBottomStyle','borderBottomWidth','borderBottomColor','borderLeftStyle','borderLeftWidth','borderLeftColor','borderRightStyle'];
        const cells=[...document.querySelectorAll('.report-body td,.report-body th')];return JSON.stringify(cells.map(el=>{const c=getComputedStyle(el);return [el.textContent.trim(),Object.fromEntries(names.map(n=>[n,c[n]]))]}));})()
        """
        let expected=try await report.web.evaluateJavaScript(description) as! String
        try Data(expected.utf8).write(to:output.appendingPathComponent("presentation-live.json"))
        let before=try await report.web.evaluateJavaScript("document.querySelector('.report-body').innerHTML") as! String,revision=report.reportRevision
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("presentation-report."+format.rawValue))
            if format == .pdf {
                let pdf=PDFDocument(data:data)!
                try check(pdf.string!.contains("Custom cell") && pdf.string!.contains("Bold second line"))
                let fonts=pdf.findString("Custom cell",withOptions:[]).compactMap{$0.attributedString?.attribute(.font,at:0,effectiveRange:nil) as? NSFont}
                let plainFonts=pdf.findString("Plain heading",withOptions:[]).compactMap{$0.attributedString?.attribute(.font,at:0,effectiveRange:nil) as? NSFont}
                // WebKit fits the page; PDFKit returns the scaled font. Compare
                // the original 18pt/10pt ratio, not an assumed printer scale.
                try check(!plainFonts.isEmpty && fonts.contains{$0.fontName.contains("Georgia") && abs($0.pointSize/plainFonts[0].pointSize-1.8)<0.02},"PDF changed the custom cell font or relative size")
            }
        }
        let after=try await report.web.evaluateJavaScript("document.querySelector('.report-body').innerHTML") as! String
        try check(after==before)
        try check(report.reportRevision==revision)
        let reopened=try await v.importReport(output.appendingPathComponent("presentation-report.html"));try await settled(reopened)
        let imported=try await reopened.web.evaluateJavaScript(description) as! String
        try Data(imported.utf8).write(to:output.appendingPathComponent("presentation-reopened.json"))
        try check(imported==expected,"HTML reopen changed table presentation")
        try await v.reportExportData(reopened,format:.docx).write(to:output.appendingPathComponent("presentation-reopened.docx"))
        v.remove(reopened)
        v.tabs.selectTabViewItem(report.item)
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.querySelector('.report-body'))")
        let direct=try await v.reportScript(report,method:"clipboard")!
        let directHTML=(try JSONSerialization.jsonObject(with:Data(direct.utf8)) as! [String:String])["html"]!
        try Data(directHTML.utf8).write(to:output.appendingPathComponent("presentation-direct.html"))
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true);document.querySelector('.report-body').focus();window.getSelection().selectAllChildren(document.querySelector('.report-body'))")
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        _ = try await v.transferReportClipboard(report,command:"copy",pasteboard:board)
        let publicHTML=board.string(forType:.html)!,privateHTML=board.string(forType:Viewer.reportFragmentType)!
        try Data(publicHTML.utf8).write(to:output.appendingPathComponent("presentation-clipboard.html"))
        try Data(privateHTML.utf8).write(to:output.appendingPathComponent("presentation-private.html"))
        for (name,html,kind) in [("private",privateHTML,Viewer.reportFragmentType),("public",publicHTML,NSPasteboard.PasteboardType.html),("direct",directHTML,NSPasteboard.PasteboardType.html)] {
            let target=v.makeReport();target.reportEntries=[ReportEntry(id:UUID().uuidString,title:"Paste",operation:"",body:"<p id='paste-here'><br></p>",rPlan:nil)]
            v.renderReport(target);try await settled(target)
            try await target.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true);document.querySelector('.report-body').focus();const r=document.createRange();r.selectNodeContents(document.getElementById('paste-here'));r.collapse(true);window.getSelection().removeAllRanges();window.getSelection().addRange(r)")
            board.clearContents();board.setString(html,forType:kind)
            _ = try await v.transferReportClipboard(target,command:"paste",pasteboard:board);try await settled(target)
            let pasted=try await target.web.evaluateJavaScript(description) as! String
            try Data(pasted.utf8).write(to:output.appendingPathComponent("presentation-\(name)-paste.json"))
            if name=="private" {try check(pasted==expected,"Private clipboard changed table styles or borders")}
            else {
                // Office receives the visible collapsed-border outline on its
                // outside cells. Other presentation must still match exactly.
                func withoutBorders(_ json:String) throws -> String {
                    var cells=try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [[Any]]
                    for i in cells.indices {cells[i][1]=(cells[i][1] as! [String:String]).filter{!$0.key.hasPrefix("border")}}
                    return String(decoding:try JSONSerialization.data(withJSONObject:cells,options:.sortedKeys),as:UTF8.self)
                }
                try check(try withoutBorders(pasted)==withoutBorders(expected),"Office clipboard changed text or cell presentation")
                let edges=try await target.web.evaluateJavaScript("(()=>{const t=[...document.querySelectorAll('.report-body table')].at(-1),a=getComputedStyle(t.rows[0].cells[0]),b=getComputedStyle(t.rows[0].cells[1]);return a.borderTopColor==='rgb(204, 0, 0)'&&a.borderTopWidth==='2px'&&a.borderBottomStyle==='dashed'&&a.borderBottomColor==='rgb(0, 0, 204)'&&a.borderBottomWidth==='3px'&&a.borderLeftColor==='rgb(0, 128, 0)'&&b.borderRightColor==='rgb(0, 128, 0)'&&b.borderTopWidth==='2px';})()") as! Bool
                try check(edges,"Office clipboard changed the visible collapsed table borders")
            }
            try check(target.reportUndo.count==1,"Pasting styled content should be one undo")
            try await target.web.evaluateJavaScript("StatsDirectReportEditor.command('undo')");try await settled(target)
            let count=try await target.web.evaluateJavaScript("document.querySelectorAll('.report-body table').length") as! Int
            try check(count==0)
            v.remove(target)
        }
        v.remove(report)
        print("PASS: HTML/PDF/DOCX retain report styles, private/public/direct copy preserve table fonts and per-side borders, pasted content undoes as one edit; Office values and Word properties checked separately");fflush(stdout)
    }

    @MainActor static func stylesheetPresentation(_ v: Viewer, output: URL) async throws {
        let report=v.makeReport()
        report.reportEntries=[ReportEntry(id:UUID().uuidString,title:"Stylesheet presentation",operation:"",body:"""
        <p id="fresh-default">New report default font</p>
        <p><span class="ci">CSS confidence interval</span> <span class="pval">CSS P value</span> <span class="warn">CSS warning</span></p>
        <p class="custom-face">Custom Georgia face</p><p class="custom-face" style="font-family:'Times New Roman';font-size:18.5pt;color:#c00000">Inline font override</p>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80" width="240" height="80"><text x="10" y="40" font-family="Georgia" font-size="18">Custom chart face</text></svg>
        """,rPlan:nil)]
        v.renderReport(report);try await settled(report)
        try await report.web.evaluateJavaScript("""
        (()=>{const s=document.createElement('style');s.textContent='.report-body .ci{color:#0000ff}.report-body .pval{color:#008000}.report-body .warn{color:#ff0000}.report-body .custom-face{font-family:Georgia;font-size:13.5pt;font-style:italic}';document.head.append(s);})()
        """)
        let computed=try await report.web.evaluateJavaScript("""
        (()=>{const style=s=>getComputedStyle(document.querySelector(s));return {font:style('#fresh-default').fontFamily,ci:style('.ci').color,pval:style('.pval').color,warn:style('.warn').color,custom:style('.custom-face').fontFamily,chart:style('.report-body svg text').fontFamily};})()
        """) as! [String:String]
        precondition(computed["font"]!.hasPrefix("Arial") && computed["custom"]!.contains("Georgia") && computed["chart"]!.contains("Georgia"))
        precondition(computed["ci"]=="rgb(0, 0, 255)" && computed["pval"]=="rgb(0, 128, 0)" && computed["warn"]=="rgb(255, 0, 0)")
        // The region holds content only: resizing the window and exporting change nothing in it.
        let snapshotScript="""
        (()=>{const body=document.querySelector('.report-body'),copy=body.cloneNode(true);copy.querySelectorAll('.report-controls').forEach(e=>e.remove());return {raw:body.innerHTML,content:copy.innerHTML};})()
        """
        let initial=try await report.web.evaluateJavaScript(snapshotScript) as! [String:String],revision=report.reportRevision
        let frame=v.window.frame
        v.window.setFrame(NSRect(x:frame.minX,y:frame.minY,width:frame.width+80,height:frame.height),display:true)
        try await settled(report)
        let resized=try await report.web.evaluateJavaScript(snapshotScript) as! [String:String]
        v.window.setFrame(frame,display:true);try await settled(report)
        precondition(initial["content"]==resized["content"] && report.reportRevision==revision,"Window resizing must not change report content")
        let before=try await report.web.evaluateJavaScript(snapshotScript) as! [String:String]
        for format in ReportFormat.allCases {try await v.reportExportData(report,format:format).write(to:output.appendingPathComponent("stylesheet-report."+format.rawValue))}
        let after=try await report.web.evaluateJavaScript(snapshotScript) as! [String:String]
        if before["content"] != after["content"] || report.reportRevision != revision {
            print("EXPORT DIAGNOSTICS: revision \(revision) -> \(report.reportRevision)")
            print("BEFORE: \(before["content"]!)");print("AFTER: \(after["content"]!)");fflush(stdout)
        }
        precondition(before["content"]==after["content"] && report.reportRevision==revision,"Export must not style or revise the live document")
        let reopened=try await v.importReport(output.appendingPathComponent("stylesheet-report.html"));try await settled(reopened)
        try await v.reportExportData(reopened,format:.docx).write(to:output.appendingPathComponent("stylesheet-reopened.docx"))
        let preserved=try await reopened.web.evaluateJavaScript("getComputedStyle(document.querySelector('.report-body svg text')).fontFamily.includes('Georgia')") as! Bool
        precondition(preserved,"Reopening must retain an existing custom chart font")
        v.remove(reopened);v.remove(report)
        print("PASS: new report Arial default, existing custom report/chart faces, stylesheet colours, HTML/PDF/DOCX export/reopen and unchanged live document/revision; Word styles checked separately")
    }

    @MainActor static func semanticContainers(_ v: Viewer, output: URL) async throws {
        let wrappers = ["main", "header", "footer", "aside", "nav", "figure", "figcaption", "address", "report-output"]
        let body = wrappers.map { tag in
            """
            <\(tag) style="font-family:Georgia;color:#245580">
            <h2>\(tag) heading</h2><p>\(tag) before <strong>bold</strong> and <a href="https://www.statsdirect.com/help/">help link</a>.</p>
            <table><thead><tr><th colspan="2">\(tag) merged heading</th></tr></thead><tbody><tr><td rowspan="2">\(tag) label</td><td>12.5</td></tr><tr><td>18.75</td></tr></tbody></table>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 100" width="240" height="100" aria-label="\(tag) chart"><rect x="5" y="5" width="230" height="90" fill="#e0efff"/><text x="120" y="55" text-anchor="middle">\(tag) chart</text></svg>
            <ol><li>\(tag) first step</li><li>\(tag) second step</li></ol><p>\(tag) after</p>
            </\(tag)>
            """
        }.joined()
        let report = v.makeReport()
        report.reportEntries = [ReportEntry(id: UUID().uuidString, title: "Semantic containers", operation: "", body: body, rPlan: nil)]
        v.renderReport(report); try await settled(report)
        let count = try await report.web.evaluateJavaScript("document.querySelectorAll('.report-body table').length") as! Int
        precondition(count == wrappers.count)
        for format in ReportFormat.allCases {
            let data = try await v.reportExportData(report, format: format)
            try data.write(to: output.appendingPathComponent("semantic-containers." + format.rawValue))
            if format == .pdf {
                let text = PDFDocument(data: data)?.string ?? ""
                precondition(wrappers.allSatisfy { text.contains($0 + " merged heading") && text.contains($0 + " chart") })
            }
        }
        let reopened = try await v.importReport(output.appendingPathComponent("semantic-containers.html"))
        try await settled(reopened)
        let retained = try await reopened.web.evaluateJavaScript("({main:!!document.querySelector('.report-body main'),aside:!!document.querySelector('.report-body aside'),tables:document.querySelectorAll('.report-body table').length,charts:document.querySelectorAll('.report-body svg').length})") as! [String: Any]
        precondition(retained["main"] as? Bool == true && retained["aside"] as? Bool == true && retained["tables"] as? Int == wrappers.count && retained["charts"] as? Int == wrappers.count)
        try await v.reportExportData(reopened, format: .docx).write(to: output.appendingPathComponent("semantic-containers-reopened.docx"))
        v.remove(reopened); v.remove(report)
        print("PASS: semantic HTML containers retain all tables/charts through native HTML/PDF export and import; DOCX structures checked separately")
    }

    @MainActor static func settled(_ doc: Document) async throws {
        for _ in 0..<150 where doc.web.isLoading { try await Task.sleep(nanoseconds: 100_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    @MainActor static func editing(_ v: Viewer, report: Document, output: URL) async throws {
        let id=UUID().uuidString
        var trace:[String]=[]
        func stage(_ label:String) async throws {
            let dom=try await report.web.evaluateJavaScript("(()=>{const r=document.getElementById('report-results');const all=[...r.children],from=all.findIndex(c=>c.getAttribute('aria-label')==='Editing checks');return all.slice(Math.max(0,from)).map(c=>c.outerHTML.slice(0,c.outerHTML.indexOf('>')+1)+'['+[...c.children].map(k=>k.tagName+(k.id?'#'+k.id:'')).join(',')+']').join(' | ')})()") as? String ?? "?"
            trace.append("\(label): active=\(try await report.web.evaluateJavaScript("document.activeElement?.tagName+'.'+(document.activeElement?.id||document.activeElement?.className||'')") as? String ?? "?") undo=\(report.reportUndo.count) :: \(dom.prefix(3000))")
        }
        v.appendReport(ReportEntry(id:id,title:"Editing checks",operation:"",body:"<p id='edit-note'>Original interpretation</p><p id='edit-align'>Aligned note</p><p id='edit-heading'>Editable heading</p><p id='edit-bullet'>Interpretation bullet</p><p id='edit-number'>Interpretation step</p><p id='edit-font'>Formatting sample</p><p id='edit-super'>Superscript sample</p><p id='edit-sub'>Subscript sample</p><p id='edit-clear'>Clear sample</p><p id='edit-typing'>Typing: </p><p id='edit-indent'>Indented interpretation</p><p id='edit-nested'>Nested bullet</p><table><tr><th>Measure</th><th>Value</th></tr><tr><td>Estimate</td><td>12.5</td></tr></table>",rPlan:nil))
        try await settled(report)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true);let p=document.getElementById('edit-note');document.getElementById('report-results').focus();window.getSelection().selectAllChildren(p);document.execCommand('insertText',false,'Edited interpretation');")
        try await settled(report)
        precondition(report.reportEntries!.last!.editedBody!.contains("Edited interpretation") && report.reportDirty)
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.getElementById('edit-note'));StatsDirectReportEditor.command('bold');StatsDirectReportEditor.command('underline');")
        try await settled(report)
        let formatted=report.reportEntries!.last!.editedBody!
        precondition(formatted.contains("Edited interpretation") && (formatted.contains("<b>") || formatted.contains("bold")) && (formatted.contains("<u>") || formatted.contains("underline")))
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('undo');")
        try await settled(report)
        precondition(report.reportEntries!.last!.editedBody != formatted)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('redo');")
        try await settled(report)
        precondition(report.reportEntries!.last!.editedBody == formatted)
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.getElementById('edit-align'));StatsDirectReportEditor.command('justifyCenter');")
        try await settled(report)
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.getElementById('edit-heading'));StatsDirectReportEditor.command('formatBlock','h2');window.getSelection().selectAllChildren(document.getElementById('edit-bullet'));StatsDirectReportEditor.command('insertUnorderedList');window.getSelection().selectAllChildren(document.getElementById('edit-number'));StatsDirectReportEditor.command('insertOrderedList');")
        try await settled(report)
        let structure=report.reportEntries!.last!.editedBody!
        precondition(structure.contains("<h2") && structure.contains("<ul") && structure.contains("<ol"))
        // Exercise the real focus change into font controls, not only direct commands.
        let controls=try await report.web.evaluateJavaScript("""
        (()=>{
          const editor=StatsDirectReportEditor,sel=window.getSelection(),p=document.getElementById('edit-font');
          p.closest('.report-body').focus();sel.selectAllChildren(p);
          const font=document.querySelector('[data-format=fontName]');font.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));font.focus();font.value='Times New Roman';font.dispatchEvent(new Event('change'));
          const size=document.querySelector('[data-format=fontSize]');size.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));size.focus();size.value='18.5';size.dispatchEvent(new Event('change'));
          editor.command('italic');editor.command('strikeThrough');editor.command('foreColor','#c00000');editor.command('hiliteColor','#ffff00');editor.command('lineSpacing','2');
          const leaf=[...p.querySelectorAll('*')].findLast(el=>el.textContent==='Formatting sample')||p,c=getComputedStyle(leaf);
          return {font:c.fontFamily,size:c.fontSize,color:c.color,background:[...p.querySelectorAll('*'),p].map(el=>getComputedStyle(el).backgroundColor).find(c=>c!=='rgba(0, 0, 0, 0)'),line:p.style.lineHeight,selection:sel.toString()};
        })()
        """) as! [String:Any]
        print("Editor formatting:",controls);fflush(stdout)
        try await stage("controls")
        precondition((controls["font"] as! String).contains("Times New Roman") && abs(Double((controls["size"] as! String).replacingOccurrences(of:"px",with:""))!-24.6667)<0.02)
        precondition(controls["color"] as! String=="rgb(192, 0, 0)" && controls["background"] as! String=="rgb(255, 255, 0)" && controls["line"] as! String=="2" && controls["selection"] as! String=="Formatting sample")
        try await settled(report)
        let sized=report.reportEntries!.last!.editedBody!
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('undo');")
        try await settled(report)
        precondition(report.reportEntries!.last!.editedBody != sized)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('redo');")
        try await settled(report)
        precondition(report.reportEntries!.last!.editedBody == sized)
        try await stage("sized undo/redo")
        try await report.web.evaluateJavaScript("""
        (()=>{
          const e=StatsDirectReportEditor,s=window.getSelection();
          s.selectAllChildren(document.getElementById('edit-super'));e.command('superscript');
          s.selectAllChildren(document.getElementById('edit-sub'));e.command('subscript');
          s.selectAllChildren(document.getElementById('edit-clear'));e.command('bold');e.command('foreColor','#c00000');e.command('removeFormat');
          s.selectAllChildren(document.getElementById('edit-indent'));e.command('indent');e.command('outdent');e.command('indent');
          s.selectAllChildren(document.getElementById('edit-nested'));e.command('insertUnorderedList');e.command('indent');
          const p=document.getElementById('edit-typing');s.selectAllChildren(p);s.collapseToEnd();e.command('fontSize','20');document.execCommand('insertText',false,'Larger typing');
        })()
        """)
        try await settled(report)
        let typed=try await report.web.evaluateJavaScript("getComputedStyle(document.getElementById('edit-typing').lastElementChild).fontSize") as! String
        precondition(abs(Double(typed.replacingOccurrences(of:"px",with:""))!-26.6667)<0.02)
        try await stage("second batch")
        // Native Format dispatch uses the same selection as the toolbar.
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.getElementById('edit-align'))")
        let menu=NSMenuItem(title:"Right",action:#selector(Viewer.reportFormatCommand(_:)),keyEquivalent:"");menu.representedObject=["command":"justifyRight","value":""]
        precondition(v.validateMenuItem(menu));v.reportFormatCommand(menu);try await settled(report)
        let right=try await report.web.evaluateJavaScript("document.getElementById('edit-align').style.textAlign") as! String
        precondition(right=="right")
        try await stage("justifyRight")
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('justifyCenter');")
        try await settled(report)
        try await stage("justifyCenter")
        let chartHTML=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').outerHTML") as! String
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.querySelector('.report-entry'));StatsDirectReportEditor.command('fontSize','48');")
        let chartAfter=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').outerHTML") as! String
        precondition(chartHTML==chartAfter,"formatting a result must leave its chart unchanged")
        try await stage("fontSize 48")
        let noteBefore=try await report.web.evaluateJavaScript("document.getElementById('edit-note')?.outerHTML ?? 'missing'") as! String
        let modelBefore=report.reportEntries!.first(where:{$0.id==id})?.editedBody ?? "nil"
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Later result",operation:"",body:"<p>Later result retained</p>",rPlan:nil))
        try await settled(report)
        if !(report.reportEntries!.first(where:{$0.id==id})?.editedBody ?? "").contains("Edited interpretation") {
            print("Editing entry before append (DOM):", noteBefore); print("Editing entry before append (model):", modelBefore.prefix(600))
            print("Editing entry after append (model):", (report.reportEntries!.first(where:{$0.id==id})?.editedBody ?? "nil").prefix(600)); print("Entries:", report.reportEntries!.map{$0.id}, "undo:", report.reportUndo.count)
            try await stage("append"); for line in trace {print(line)}; fflush(stdout)
        }
        precondition(report.reportEntries!.first(where:{$0.id==id})!.editedBody!.contains("Edited interpretation"))
        let visible=try await report.web.evaluateJavaScript("document.body.innerText") as! String
        precondition(visible.contains("Edited interpretation") && visible.contains("Later result retained"))
        // Selected chart deletion uses the same history as text formatting.
        try await report.web.evaluateJavaScript("(()=>{const picture=document.querySelector('.report-body svg');picture.dispatchEvent(new MouseEvent('click',{bubbles:true}));document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',bubbles:true,cancelable:true}));})()")
        try await settled(report)
        let hiddenHTML=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
        // The deleted picture is the engine's agreement chart; the LOESS chart R drew (an inline SVG too) stays.
        precondition(hiddenHTML.components(separatedBy:"<svg").count==2 && hiddenHTML.contains("svglite"),"only the agreement chart should be gone; the LOESS SVG stays")
        v.editReport(report,["action":"undoText"]);try await settled(report)
        precondition(try await report.web.evaluateJavaScript("document.querySelectorAll('#report-results svg').length") as? Int==2,"undo did not restore the deleted chart in the report pane")
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("edited-report."+format.rawValue))
            if format == .html { let html=String(decoding:data,as:UTF8.self);precondition(html.contains("Edited interpretation") && html.contains("<svg") && !html.contains("contenteditable=") && !html.contains("id=\"report-toolbar\"")) }
            if format == .pdf { precondition(PDFDocument(data:data)!.string!.contains("Edited interpretation")) }
        }
        let reopened=try await v.importReport(output.appendingPathComponent("edited-report.html"));try await settled(reopened)
        let reopenedText=try await reopened.web.evaluateJavaScript("document.body.innerText") as! String
        precondition(reopenedText.contains("Edited interpretation"))
        let restored=try await reopened.web.evaluateJavaScript("(()=>{const p=[...document.querySelectorAll('.report-body p')].find(el=>el.textContent==='Formatting sample'),leaf=[...p.querySelectorAll('*')].at(-1)||p,c=getComputedStyle(leaf);return {font:c.fontFamily,size:c.fontSize,color:c.color,line:getComputedStyle(p).lineHeight}})()") as! [String:Any]
        precondition((restored["font"] as! String).contains("Times New Roman") && restored["color"] as! String=="rgb(192, 0, 0)" && abs(Double((restored["size"] as! String).replacingOccurrences(of:"px",with:""))!-24.6667)<0.02)
        precondition(reopened.reportEntries != nil && !reopened.reportDirty)
        print("PASS: report typing, formatting, native undo/redo, append preservation, plot removal/restore, edited HTML/PDF/DOCX and editable HTML reopen");fflush(stdout)
    }

    // The report is one editable region: results are blocks in it, selection and commands cross them,
    // Clear formatting works as a word processor's, and help, R and chart sizing live in the host's menus.
    @MainActor static func singleRegion(_ v: Viewer, output: URL) async throws {
        let report=v.makeReport(),a="region-a",b="region-b"
        report.reportEntries=[
            ReportEntry(id:a,title:"Alpha",operation:"TPaired",body:"<h1 id='sr-a-h'>Alpha</h1><p id='sr-a1'>Alpha one</p><p id='sr-a2' style='text-align:right;font-size:18pt'><b>Alpha</b> <span style='color:#ff0000'>two</span></p>",rPlan:RScriptPlan(script:"x <- 1",hasRecipe:true,detail:"Recipe"),helpPath:"Help/parametric_methods/paired_t.htm"),
            ReportEntry(id:b,title:"Beta",operation:"",body:"<h1 id='sr-b-h'>Beta heading</h1><p id='sr-b1' style='font-style:italic'>Beta <u>one</u></p><svg id='sr-svg' viewBox='0 0 100 40' width='100' height='40'><text x='5' y='25'>Chart</text></svg><p id='sr-b2'>Beta two</p>",rPlan:nil)]
        report.reportEditing=true;v.renderReport(report);try await settled(report)
        func js(_ script:String) async throws -> Any {try await report.web.evaluateJavaScript(script) ?? NSNull()}
        func check(_ expression:String,_ reason:String) async throws {
            let ok=try await js(expression) as? Bool == true
            if !ok {print("Region failure:",reason,try await js("document.getElementById('report-results').innerHTML"));fflush(stdout)}
            precondition(ok,reason)
        }
        try await check("(()=>{const r=document.getElementById('report-results');return r.isContentEditable&&r.classList.contains('report-body')&&document.querySelectorAll('#report-results [contenteditable=\"true\"]').length===0&& !r.querySelector('.report-controls,.report-links,button,input,select,.report-annotation');})()","the region is the one editable element and holds no controls")
        try await check("(()=>{const e=document.getElementById('result-region-a');return e.dataset.resultId==='region-a'&&e.dataset.help==='Help/parametric_methods/paired_t.htm'&&e.dataset.r==='recipe'&&e.getAttribute('aria-label')==='Alpha'&& !document.getElementById('result-region-b').dataset.r;})()","result blocks carry their id, help and R availability")
        // A selection from one result into the next, formatted in one step: both results change, one undo restores both.
        _ = try await js("(()=>{const r=document.createRange(),a=document.getElementById('sr-a2').lastChild.firstChild,b=document.getElementById('sr-b1').firstChild;document.getElementById('report-results').focus();r.setStart(a,1);r.setEnd(b,3);const s=getSelection();s.removeAllRanges();s.addRange(r);StatsDirectReportEditor.command('underline');})()")
        try await settled(report)
        precondition(report.reportUndo.last!.edits.count==2,"a command across two results is one transaction of two edits")
        try await check("(()=>{const underlined=root=>!!root.querySelector('u,[style*=\"underline\"]');return underlined(document.getElementById('sr-a2'))&&underlined(document.getElementById('sr-b-h'))&&underlined(document.getElementById('sr-b1'));})()","the selection crossed the result boundary")
        _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        try await check("!document.querySelector('#sr-a2 u,#sr-a2 [style*=\"underline\"],#sr-b-h u,#sr-b-h [style*=\"underline\"]')&&document.getElementById('sr-b1').querySelectorAll('u').length===1","undo restored both results")
        // Clear formatting with a caret clears the paragraph at the caret: inline elements, inline styles and the block's own styles.
        _ = try await js("(()=>{const r=document.createRange(),n=document.getElementById('sr-a2').lastChild.firstChild;document.getElementById('report-results').focus();r.setStart(n,1);r.collapse(true);const s=getSelection();s.removeAllRanges();s.addRange(r);StatsDirectReportEditor.command('removeFormat');})()")
        try await settled(report)
        try await check("(()=>{const p=document.getElementById('sr-a2');return p.textContent==='Alpha two'&& !p.querySelector('b,span,font')&& !p.getAttribute('style')&& !!document.getElementById('sr-a1')&&document.getElementById('sr-b1').getAttribute('style')==='font-style:italic';})()","caret Clear formatting cleared only its paragraph")
        _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        try await check("document.getElementById('sr-a2').getAttribute('style')==='text-align:right;font-size:18pt'&& !!document.querySelector('#sr-a2 b')","undo restored the paragraph's formatting")
        // With a selection it clears every block the selection touches, across results, passing over the chart and keeping the heading.
        let svgBefore=try await js("document.getElementById('sr-svg').outerHTML") as! String
        _ = try await js("(()=>{const r=document.createRange(),a=document.getElementById('sr-a2').firstChild.firstChild,b=document.getElementById('sr-b2').firstChild;document.getElementById('report-results').focus();r.setStart(a,2);r.setEnd(b,4);const s=getSelection();s.removeAllRanges();s.addRange(r);StatsDirectReportEditor.command('removeFormat');})()")
        try await settled(report)
        // The partly selected paragraph loses its own styles and the formatting of the selected text; the unselected start keeps its bold.
        try await check("(()=>{const a=document.getElementById('sr-a2'),b1=document.getElementById('sr-b1');return !a.getAttribute('style')&&a.lastChild.nodeType===3&&a.lastChild.textContent==='pha two'&&a.textContent==='Alpha two'&&!b1.getAttribute('style')&&!b1.querySelector('u')&&document.getElementById('sr-b-h').tagName==='H1'&&document.getElementById('sr-svg').outerHTML===\(v.jsString(svgBefore));})()","selection Clear formatting cleared every touched block, kept the heading and passed over the chart")
        precondition(report.reportUndo.last!.edits.count==2)
        _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        // What a right-click is on reaches the host: the result, its help and R, and whether a chart is there.
        _ = try await js("document.getElementById('sr-b1').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}))");try await settled(report)
        let context=try await js("StatsDirectReportEditor.contextTarget()") as! [String:Any]
        precondition(context["resultId"] as? String==b && context["inReport"] as? Bool==true && context["picture"] as? Bool==false && (context["help"] is NSNull||context["help"]==nil) && report.reportContext["resultId"] as? String==b,"context target \(context) / host \(report.reportContext)")
        _ = try await js("document.getElementById('sr-svg').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}))");try await settled(report)
        precondition(report.reportContext["picture"] as? Bool==true && report.reportContext["resultId"] as? String==b)
        _ = try await js("document.getElementById('sr-a1').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}))");try await settled(report)
        precondition(report.reportContext["help"] as? String=="Help/parametric_methods/paired_t.htm" && report.reportContext["r"] as? String=="recipe")
        let menu=NSMenu();v.extendReportMenu(menu,for:report)
        let titles=menu.items.map(\.title)
        precondition(titles.starts(with:["Method Help","Continue in R","Select Result","Select All Results"]),"context menu items: \(titles)")
        // Typing on past the last result stays in that result; a result is revealed below the toolbar.
        _ = try await js("(()=>{const p=document.getElementById('sr-b2'),r=document.createRange();document.getElementById('report-results').focus();r.selectNodeContents(p);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r);document.execCommand('insertParagraph');document.execCommand('insertText',false,'Tail text');})()")
        try await settled(report)
        try await check("document.getElementById('result-region-b').textContent.includes('Tail text')&&[...document.getElementById('report-results').children].every(e=>e.matches('.report-entry[data-result-id]'))","text typed after the last result belongs to it")
        precondition((report.reportEntries!.last!.editedBody ?? "").contains("Tail text"))
        precondition(try await js("StatsDirectReportEditor.reveal('region-b')&&document.getElementById('report-results').style.getPropertyValue('--reveal-room')!==''") as? Bool==true)
        // A report that fits the window stays at the top when a result is revealed.
        _ = try await js("window.scrollTo(0,0)")
        try await check("(()=>{StatsDirectReportEditor.reveal('region-a');return window.scrollY===0&&document.getElementById('report-results').style.getPropertyValue('--reveal-room')==='0px';})()","revealing the first result of a short report scrolled the window")
        // A result after a tall one lands with its top just below the toolbar, and stays there when more of it arrives.
        _ = try await js("(()=>{const a=document.getElementById('result-region-a');const tall=document.createElement('p');tall.id='sr-tall';tall.style.height='2000px';tall.textContent='Tall';a.append(tall);})()")
        try await check("(()=>{const e=StatsDirectReportEditor,b=document.getElementById('result-region-b'),bar=document.getElementById('report-toolbar'),gap=bar.getBoundingClientRect().height+8;e.reveal('region-b');const top=b.getBoundingClientRect().top;if(!(window.scrollY>0&&top>=gap-1&&top<=gap+40))return false;e.extend('region-b','<p id=\"sr-b-more\">More output</p>');e.reveal('region-b');const again=b.getBoundingClientRect().top;return window.scrollY>0&&again>=gap-1&&again<=gap+40&&!!document.getElementById('sr-b-more');})()","a result after a tall one, or given more output, is not at the toolbar")
        _ = try await js("document.getElementById('sr-tall').remove();document.getElementById('sr-b-more').remove();window.scrollTo(0,0)")
        // Ctrl+Y / ⌘Y redoes, as Word does on either platform.
        let undoCount=report.reportUndo.count
        _ = try await js("(()=>{const p=document.getElementById('sr-a1'),r=document.createRange();document.getElementById('report-results').focus();r.selectNodeContents(p);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r);document.execCommand('insertText',false,' redo me');})()")
        try await settled(report)
        precondition(report.reportUndo.count==undoCount+1 && (report.reportEntries!.first!.editedBody ?? "").contains("redo me"))
        _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        precondition(!(report.reportEntries!.first!.editedBody ?? "").contains("redo me") && report.reportRedo.count==1)
        _ = try await js("document.getElementById('report-results').dispatchEvent(new KeyboardEvent('keydown',{key:'y',metaKey:true,bubbles:true,cancelable:true}))");try await settled(report)
        precondition((report.reportEntries!.first!.editedBody ?? "").contains("redo me") && report.reportRedo.isEmpty,"⌘Y did not redo")
        // A host that loads another report into the same page (the Windows window) replaces every block: the results the editor knew before are forgotten, so the first edit of the new report is not reported as their removal.
        let c="region-c"
        report.reportEntries=[ReportEntry(id:c,title:"Gamma",operation:"",body:"<h1 id='sr-c-h'>Gamma</h1><p id='sr-c1'>Gamma one</p>",rPlan:nil)];report.reportUndo=[];report.reportRedo=[]
        _ = try await js("(()=>{const root=document.getElementById('report-results');root.replaceChildren();StatsDirectReportEditor.replaceEntries([{id:'region-c',html:\"<article class='report-entry' id='result-region-c' data-result-id='region-c' aria-label='Gamma'><h1 id='sr-c-h'>Gamma</h1><p id='sr-c1'>Gamma one</p></article>\"}],['region-c']);const p=document.getElementById('sr-c1'),r=document.createRange();root.focus();r.selectNodeContents(p);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r);document.execCommand('insertText',false,' edited');})()")
        try await settled(report)
        precondition(report.reportUndo.count==1 && (report.reportEntries!.first!.editedBody ?? "").contains("Gamma one edited"),"the first edit after a load was lost: \(report.reportUndo.count) changes")
        report.reportEntries=[ReportEntry(id:a,title:"Alpha",operation:"TPaired",body:"<h1 id='sr-a-h'>Alpha</h1><p id='sr-a1'>Alpha one</p>",rPlan:nil,helpPath:"Help/parametric_methods/paired_t.htm")];report.reportUndo=[];report.reportRedo=[];v.renderReport(report);try await settled(report)
        let exported=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
        precondition(exported.contains("https://www.statsdirect.com/help/parametric_methods/paired_t.htm") && !exported.contains("data-help") && !exported.contains("contenteditable"),"the saved report carries the method link, not the editing attributes")
        v.remove(report)
        print("PASS: one editable region: no controls in the report, commands and Clear formatting across results, context target with help/R/chart, text after the last result, reveal, and the method link in the saved report");fflush(stdout)
    }

    @MainActor static func chartResizing(_ v: Viewer, report: Document, output: URL) async throws {
        v.tabs.selectTabViewItem(report.item)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true)")
        let original=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').innerHTML") as! String
        let originalViewBox=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').getAttribute('viewBox')") as! String
        let undoCount=report.reportUndo.count
        // The chart is selected by a click; the toolbar's width field and Fit then size it. Nothing sits in the report itself.
        try await report.web.evaluateJavaScript("(()=>{const s=document.querySelector('.report-body svg');s.dispatchEvent(new MouseEvent('click',{bubbles:true}));})()")
        let none=try await report.web.evaluateJavaScript("!document.querySelector('.report-body .report-chart-sizing,.report-body .report-chart-resize,.report-body .report-controls')") as! Bool
        precondition(none,"sizing controls must not be in the report")
        let enabled=try await report.web.evaluateJavaScript("(()=>{const i=document.querySelector('[data-format=pictureWidth]');return !i.disabled&&Number(i.value)>0;})()") as! Bool
        precondition(enabled,"the toolbar width field follows the selected chart")
        try await report.web.evaluateJavaScript("(()=>{const input=document.querySelector('[data-format=pictureWidth]');input.focus();input.value='324';input.dispatchEvent(new Event('change',{bubbles:true}));})()")
        try await settled(report)
        precondition(report.reportUndo.count==undoCount+1)
        let width=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').getBoundingClientRect().width") as! Double
        precondition(abs(width-324)<1)
        let fieldHandled=try await report.web.evaluateJavaScript("StatsDirectReportEditor.menuCommand('undo')") as! Bool
        precondition(!fieldHandled,"Width-field Undo must stay in the text input")
        try await report.web.evaluateJavaScript("document.querySelector('.report-body .report-media').focus()")
        let handled=try await report.web.evaluateJavaScript("StatsDirectReportEditor.menuCommand('undo')") as! Bool
        precondition(handled);try await settled(report)
        precondition(report.reportUndo.count==undoCount)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('redo')");try await settled(report)
        let redone=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').style.width") as! String
        precondition(redone=="324px")
        // The context menu's commands act on the selected chart too.
        try await report.web.evaluateJavaScript("(()=>{document.querySelector('.report-body svg').dispatchEvent(new MouseEvent('click',{bubbles:true}));StatsDirectReportEditor.command('pictureWidth','320');})()")
        try await settled(report)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('pictureFit')")
        try await settled(report)
        let fit=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').style.width") as! String
        precondition(fit=="100%")
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('undo')");try await settled(report)
        let retained=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').innerHTML") as! String
        precondition(retained==original,"Resizing changed chart contents")
        let narrow=try await report.web.evaluateJavaScript("(()=>{const s=document.querySelector('.report-body svg'),p=s.closest('.report-media'),before=s.getBoundingClientRect();p.style.width='240px';const b=s.getBoundingClientRect();p.style.removeProperty('width');return b.width<=240&&Math.abs(b.width/b.height-before.width/before.height)<0.01&&s.style.width==='320px';})()") as! Bool
        precondition(narrow)
        let png=try await report.web.evaluateJavaScript("(()=>{const c=document.createElement('canvas');c.width=100;c.height=50;const x=c.getContext('2d');x.fillStyle='#197c70';x.fillRect(0,0,100,50);return c.toDataURL('image/png');})()") as! String
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Raster picture resize",operation:"",body:"<p>Raster picture resize</p><img alt='Raster resize check' src='\(png)'>",rPlan:nil));try await settled(report)
        try await report.web.evaluateJavaScript("(()=>{const img=document.querySelector('.report-body img[alt=\"Raster resize check\"]');img.dispatchEvent(new MouseEvent('click',{bubbles:true}));const input=document.querySelector('[data-format=pictureWidth]');input.value='200';input.dispatchEvent(new Event('change'));})()")
        try await settled(report)
        let raster=try await report.web.evaluateJavaScript("(()=>{const b=document.querySelector('.report-body img[alt=\"Raster resize check\"]').getBoundingClientRect();return b.width===200&&b.height===100;})()") as! Bool
        precondition(raster)
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("resized-report."+format.rawValue))
        }
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.body)")
        let copied=try await v.reportScript(report,method:"clipboard")!
        let clipboard=try JSONSerialization.jsonObject(with:Data(copied.utf8)) as! [String:String]
        precondition(clipboard["html"]!.contains("width: 320px")&&clipboard["html"]!.contains("width: 200px"))
        let reopened=try await v.importReport(output.appendingPathComponent("resized-report.html"));try await settled(reopened)
        let restored=try await reopened.web.evaluateJavaScript("(()=>{const s=document.querySelector('.report-body svg'),i=document.querySelector('.report-body img[alt=\"Raster resize check\"]');return s.style.width==='320px'&&Math.abs(s.getBoundingClientRect().width-320)<1&&i.style.width==='200px'&&i.getBoundingClientRect().height===100;})()") as! Bool
        precondition(restored)
        let bounds=try await reopened.web.evaluateJavaScript("document.querySelector('.report-body svg').getAttribute('viewBox')") as! String
        precondition(bounds==originalViewBox,"HTML reopening changed the generated chart's bounds or text alignment")
        try (await v.reportExportData(reopened,format:.docx)).write(to:output.appendingPathComponent("resized-reopened-report.docx"))
        print("PASS: chart and picture sizing from the toolbar and the context menu's commands, single-step native undo/redo, responsive proportions, clipboard and HTML/PDF/DOCX persistence; no controls in the report");fflush(stdout)
    }

    @MainActor static func archived(_ v: Viewer, url: URL, output: URL) async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let original=try Data(contentsOf:url)
        let parsed=url.pathExtension.lowercased()=="rtf" ? try LegacyReport.read(original):nil
        let doc=try await v.importReport(url);try await settled(doc)
        let counts=try await doc.web.evaluateJavaScript("({svg:[...document.querySelectorAll('.report-body svg')].filter(s=>!s.parentElement.closest('svg')).length,images:document.querySelectorAll('.report-body img').length,tables:document.querySelectorAll('.report-body table').length,unreadable:document.querySelectorAll('.report-import-warning').length,text:document.querySelector('.report-body').innerText.length})") as! [String:Any]
        print("Archived report:",original.count,"bytes; source picture formats:",parsed?.pictures.map(\.format) ?? [],"; imported counts:",counts);fflush(stdout)
        precondition((counts["unreadable"] as! Int)==0,"Archived report contains a failed conversion")
        if let parsed {precondition((counts["svg"] as! Int)+(counts["images"] as! Int)==parsed.pictures.count,"Archived picture count differs")}
        let fonts=try await doc.web.evaluateJavaScript("[...new Set([...document.querySelectorAll('.report-body svg text')].map(t=>getComputedStyle(t).fontFamily))]")
        print("Archived chart fonts:", fonts as Any)
        let labelsInside=try await doc.web.evaluateJavaScript("[...document.querySelectorAll('.report-body svg')].every(s=>{const v=s.viewBox.baseVal,m=s.getCTM().inverse();return [...s.querySelectorAll('text')].every(t=>{const b=t.getBBox(),a=m.multiply(t.getCTM());return [[b.x,b.y],[b.x+b.width,b.y],[b.x,b.y+b.height],[b.x+b.width,b.y+b.height]].every(([x,y])=>{const p=new DOMPoint(x,y).matrixTransform(a);return p.x>=v.x-0.01&&p.y>=v.y-0.01&&p.x<=v.x+v.width+0.01&&p.y<=v.y+v.height+0.01})})})") as! Bool
        precondition(labelsInside,"A substituted chart font clips a label at the SVG boundary")
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(doc,format:format)
            try data.write(to:output.appendingPathComponent("archived-report."+format.rawValue))
            if format == .pdf {precondition(PDFDocument(data:data)?.pageCount ?? 0 > 0)}
            print("PASS: archived report",format.rawValue,"export",data.count,"bytes");fflush(stdout)
        }
        let unchanged=try Data(contentsOf:url);precondition(unchanged==original)
        print("PASS: archived RTF imports with all pictures, exports in every supported format, and remains byte-identical");fflush(stdout)
    }

    @MainActor static func legacy(_ v: Viewer, output: URL) async throws {
        let fixtures=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/Reports")
        let layoutSource=try LegacyReport.read(Data(contentsOf:fixtures.appendingPathComponent("layout.rtf")))
        precondition(layoutSource.tableRows==[[1200,6000],[1200,2400,4200,6000],[1200,2400,4200,6000]])
        var layout=try await v.importReport(fixtures.appendingPathComponent("layout.rtf"));try await settled(layout)
        for cycle in 0..<3 {
            let state=try await layout.web.evaluateJavaScript("(()=>{const r=document.querySelector('.legacy-report'),t=r.querySelector('table'),p=[...r.querySelectorAll('p')].find(p=>p.textContent.includes('Body at'));return {body:getComputedStyle(p).fontSize,cell:getComputedStyle(t.rows[1].cells[1].querySelector('p')).fontSize,span:t.rows[0].cells[1].colSpan,header:t.rows[0].cells[1].tagName,align:getComputedStyle(t.rows[1].cells[1].querySelector('p')).textAlign,columns:[...t.rows[1].cells].every((c,i)=>Math.abs(c.getBoundingClientRect().x-t.rows[2].cells[i].getBoundingClientRect().x)<1)}})()") as! [String:Any]
            precondition(state["body"] as! String=="16px" && state["cell"] as! String=="14px" && state["span"] as! Int==3 && state["header"] as! String=="TH" && state["align"] as! String=="right" && state["columns"] as! Bool)
            for format in cycle==0 ? ReportFormat.allCases:[.html] {
                let data=try await v.reportExportData(layout,format:format)
                try data.write(to:output.appendingPathComponent("legacy-layout."+format.rawValue))
            }
            if cycle<2 {layout=try await v.importReport(output.appendingPathComponent("legacy-layout.html"));try await settled(layout)}
        }
        try await layout.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true);const p=[...document.querySelectorAll('.legacy-report p')].find(p=>p.textContent.includes('Body at'));window.getSelection().selectAllChildren(p);StatsDirectReportEditor.command('fontSize','20');")
        try await settled(layout)
        let custom=output.appendingPathComponent("legacy-custom.html")
        try await v.reportExportData(layout,format:.html).write(to:custom)
        let customReport=try await v.importReport(custom);try await settled(customReport)
        let customSize=try await customReport.web.evaluateJavaScript("(()=>{const p=[...document.querySelectorAll('.legacy-report p')].find(p=>p.textContent.includes('Body at'));return getComputedStyle([...p.querySelectorAll('*')].at(-1)||p).fontSize})()") as! String
        precondition(abs(Double(customSize.replacingOccurrences(of:"px",with:""))!-26.6667)<0.02,"Reopening must retain user formatting on imported RTF")
        print("PASS: RTF point sizing, spanning headers, numerical alignment and stable layout through two HTML reopenings");fflush(stdout)
        let original=try Data(contentsOf:fixtures.appendingPathComponent("legacy-charts.rtf"))
        let parsed=try LegacyReport.read(original)
        precondition(parsed.pictures.count==2 && parsed.pictures.map(\.format)==["emf","wmf"])
        precondition(parsed.html.contains("<table") && parsed.html.contains("12.5") && parsed.html.contains("α") && parsed.html.contains("χ"))
        precondition(!parsed.html.contains("!!help!") && !parsed.html.contains("Hidden inline") && parsed.html.contains("Visible again"))
        let binary=try LegacyReport.read(Data(contentsOf:fixtures.appendingPathComponent("binary-picture.rtf")))
        precondition(binary.pictures.count==1 && binary.pictures[0].data==parsed.pictures[0].data)
        for invalid in ["not rtf", "{\\rtf1 unclosed", "{\\rtf1 {\\pict\\emfblip\\bin99 short}}", "{\\rtf1 text}junk"] {
            do { _=try LegacyReport.read(Data(invalid.utf8));precondition(false,"Malformed RTF accepted") } catch {}
        }
        let doc=try await v.importReport(fixtures.appendingPathComponent("legacy-charts.rtf"));try await settled(doc)
        let state=try await doc.web.evaluateJavaScript("({text:document.body.innerText,charts:document.querySelectorAll('.report-body svg').length,table:document.querySelectorAll('.report-body table').length})") as! [String:Any]
        precondition(state["charts"] as! Int==2 && state["table"] as! Int==1)
        precondition((state["text"] as! String).contains("WMF chart") && (state["text"] as! String).contains("EMF chart") && !(state["text"] as! String).contains("could not be converted"))
        let chartFont=try await doc.web.evaluateJavaScript("getComputedStyle(document.querySelector('.report-body svg text')).fontFamily") as! String
        precondition(chartFont.contains("Calibri") && chartFont.contains("Arial") && chartFont.contains("sans-serif"), "Calibri chart lost its portable font fallback")
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(doc,format:format)
            try data.write(to:output.appendingPathComponent("legacy-converted."+format.rawValue))
            if format == .pdf {let pdf=PDFDocument(data:data)!;precondition(pdf.string!.contains("12.5") && pdf.string!.contains("EMF chart") && pdf.string!.contains("WMF chart"))}
            if format == .html {precondition(String(decoding:data,as:UTF8.self).contains("Calibri, Carlito, Arial, Helvetica, sans-serif"))}
        }
        let reopened=try await v.importReport(output.appendingPathComponent("legacy-converted.html"));try await settled(reopened)
        let reopenedFont=try await reopened.web.evaluateJavaScript("getComputedStyle(document.querySelector('.report-body svg text')).fontFamily") as! String
        precondition(reopenedFont==chartFont,"Saved HTML lost the chart font fallback")
        let oldHTML=try await ReportImporter.convert(html:"<svg><text font-family='CALIBRI'>Previously imported chart</text></svg>",resources:v.root)["html"] as! String
        precondition(oldHTML.contains("Calibri, Carlito, Arial, Helvetica, sans-serif"))
        let edgeHTML=try await ReportImporter.convert(html:"<svg width='200' height='60' viewBox='0 0 200 60'><text x='195' y='25' font-family='CALIBRI' font-size='20'>Edge label</text></svg>",resources:v.root)["html"] as! String
        let viewPattern=try NSRegularExpression(pattern:"viewBox=\"([^\"]+)\"")
        let viewMatch=viewPattern.firstMatch(in:edgeHTML,range:NSRange(edgeHTML.startIndex...,in:edgeHTML))!
        let viewValues=edgeHTML[Range(viewMatch.range(at:1),in:edgeHTML)!].split(separator:" ").compactMap{Double($0)}
        precondition(viewValues.count==4 && viewValues[0]+viewValues[2]>250 && edgeHTML.contains("x=\"195\""),"Viewport must fit the full label without moving the recorded text")
        let unchanged=try Data(contentsOf:fixtures.appendingPathComponent("legacy-charts.rtf"))
        precondition(unchanged==original)
        let standard=try await v.importReport(fixtures.appendingPathComponent("standard-wmf.rtf"));try await settled(standard)
        let standardCharts=try await standard.web.evaluateJavaScript("document.querySelectorAll('.report-body svg').length") as! Int
        precondition(standardCharts==1)
        let raster=try await v.importReport(fixtures.appendingPathComponent("raster-picture.rtf"));try await settled(raster)
        let rasterLoaded=try await raster.web.evaluateJavaScript("[...document.querySelectorAll('.report-body img')].some(img=>img.complete&&img.naturalWidth===2)") as! Bool
        precondition(rasterLoaded)
        let damaged=try await v.importReport(fixtures.appendingPathComponent("damaged-picture.rtf"));try await settled(damaged)
        let damagedText=try await damaged.web.evaluateJavaScript("document.body.innerText") as! String
        precondition(damagedText.contains("Keep this text") && damagedText.contains("could not be converted") && damagedText.contains("Still readable"))
        let attack="<html><head><style>@import url(https://example.invalid/style);p{font-weight:bold;background-image:url(https://example.invalid/image)}</style></head><body><script>window.attack=true</script><p onclick='alert(1)'>Safe text</p><img src='https://example.invalid/image'><svg><foreignObject><iframe src='https://example.invalid'></iframe></foreignObject><text>Safe chart</text></svg><a href='javascript:alert(1)'>Unsafe link</a><a href='file:///etc/passwd'>Local link</a></body></html>"
        let cleaned=try await ReportImporter.convert(html:attack,resources:v.root)["html"] as! String
        precondition(cleaned.contains("Safe text") && cleaned.contains("Safe chart") && !cleaned.contains("onclick") && !cleaned.contains("<script") && !cleaned.contains("foreignObject") && !cleaned.contains("file://") && !cleaned.contains("example.invalid") && !cleaned.contains("javascript:"))
        v.tabs.selectTabViewItem(doc.item)
        print("PASS: RTF tables/Unicode/hidden fields, EMF and WMF SVG charts, binary pictures, malformed input, visible conversion failures, original preservation, export and offline HTML sanitization");fflush(stdout)
    }
}
