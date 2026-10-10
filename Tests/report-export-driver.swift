import Cocoa
import PDFKit

@main struct ReportExportTests {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let viewer=Viewer();app.delegate=viewer
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do {
                    if let index=CommandLine.arguments.firstIndex(where:{$0=="--legacy-file" || $0=="--report-file"}),index+1<CommandLine.arguments.count {
                        try await archived(viewer, url:URL(fileURLWithPath:CommandLine.arguments[index+1]), output:URL(fileURLWithPath:CommandLine.arguments[1]))
                    } else if CommandLine.arguments.contains("--transfer-only") {try await transfers(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1]))}
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
            try check(html.contains("<img class=\"r-chart\"") && html.contains("data:image/png;base64,") && html.contains("<pre class=\"r-script\">") && html.contains("Residual Standard Error"),"LOESS report lacks R's chart or script")
            v.appendReport(ReportEntry(id:UUID().uuidString,title:"LOESS",operation:"LOESS",body:"<section class='engine-report'>"+html+"</section>",rPlan:nil))
            print("PASS: LOESS through R: the report carries R's PNG chart and the script");fflush(stdout)
        }
        let rows=(1...65).map{"<tr><td>Observation \($0)</td><td>\($0).25</td><td>-2.5</td><td>1.2e-7</td></tr>"}.joined()
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Export table checks",operation:"",body:"<h1>Export table checks</h1><table><thead><tr><th rowspan='2'>Measurement</th><th colspan='3'>Results</th></tr><tr><th>Estimate</th><th>Difference</th><th>P value</th></tr></thead><tbody>\(rows)</tbody></table><p><strong>All report entries included</strong> — α = 0.05, 95% CI, χ<sup>2</sup> and CO<sub>2</sub>.</p>",rPlan:nil))
        let report=v.active!
        for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("combined-report."+format.rawValue))
            if format == .html {
                let html=String(decoding:data,as:UTF8.self)
                precondition(html.contains("56.111111")&&html.contains("8.64")&&html.contains("Observation 65"))
                precondition(html.contains("<svg")&&html.contains("https://www.statsdirect.com/help/"))
                precondition(html.contains("class=\"r-chart\"")&&html.contains("data:image/png;base64,")&&html.contains("Residual Standard Error"))
                precondition(!html.contains("onclick=") && !html.contains("statsDirectReport.postMessage") && !html.contains("file:///"))
                print("PASS: HTML contains every result, inline vector chart, R's PNG chart and portable help links; no app handlers or file paths")
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
        try await chartResizing(v, report: report, output: output)
        try await transfers(v, output: output)
        try await legacy(v, output: output)
    }

    @MainActor static func settled(_ doc: Document) async throws {
        for _ in 0..<150 where doc.web.isLoading { try await Task.sleep(nanoseconds: 100_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    @MainActor static func editing(_ v: Viewer, report: Document, output: URL) async throws {
        let id=UUID().uuidString
        v.appendReport(ReportEntry(id:id,title:"Editing checks",operation:"",body:"<p id='edit-note'>Original interpretation</p><p id='edit-align'>Aligned note</p><p id='edit-heading'>Editable heading</p><p id='edit-bullet'>Interpretation bullet</p><p id='edit-number'>Interpretation step</p><p id='edit-font'>Formatting sample</p><p id='edit-super'>Superscript sample</p><p id='edit-sub'>Subscript sample</p><p id='edit-clear'>Clear sample</p><p id='edit-typing'>Typing: </p><p id='edit-indent'>Indented interpretation</p><p id='edit-nested'>Nested bullet</p><table><tr><th>Measure</th><th>Value</th></tr><tr><td>Estimate</td><td>12.5</td></tr></table>",rPlan:nil))
        try await settled(report)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true);let p=document.getElementById('edit-note');p.parentElement.focus();window.getSelection().selectAllChildren(p);document.execCommand('insertText',false,'Edited interpretation');")
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
        // Native Format dispatch uses the same selection as the toolbar.
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.getElementById('edit-align'))")
        let menu=NSMenuItem(title:"Right",action:#selector(Viewer.reportFormatCommand(_:)),keyEquivalent:"");menu.representedObject=["command":"justifyRight","value":""]
        precondition(v.validateMenuItem(menu));v.reportFormatCommand(menu);try await settled(report)
        let right=try await report.web.evaluateJavaScript("document.getElementById('edit-align').style.textAlign") as! String
        precondition(right=="right")
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('justifyCenter');")
        try await settled(report)
        let chartHTML=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').outerHTML") as! String
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.querySelector('.report-body'));StatsDirectReportEditor.command('fontSize','48');")
        let chartAfter=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').outerHTML") as! String
        precondition(chartHTML==chartAfter)
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Later result",operation:"",body:"<p>Later result retained</p>",rPlan:nil))
        try await settled(report)
        precondition(report.reportEntries!.first(where:{$0.id==id})!.editedBody!.contains("Edited interpretation"))
        let visible=try await report.web.evaluateJavaScript("document.body.innerText") as! String
        precondition(visible.contains("Edited interpretation") && visible.contains("Later result retained"))
        // Removing a plot, editing text, then restoring it must preserve the edits.
        let first=report.reportEntries!.first!
        v.editReport(report,["action":"hideChart","resultID":first.id,"index":0]);try await settled(report)
        let hiddenHTML=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
        precondition(!hiddenHTML.contains("<svg"))
        v.editReport(report,["action":"undoReport"]);try await settled(report)
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

    @MainActor static func chartResizing(_ v: Viewer, report: Document, output: URL) async throws {
        v.tabs.selectTabViewItem(report.item)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true)")
        let original=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').innerHTML") as! String
        let originalViewBox=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').getAttribute('viewBox')") as! String
        let undoCount=report.reportTextUndo.count
        try await report.web.evaluateJavaScript("(()=>{const input=document.querySelector('.report-chart-sizing input');input.focus();input.value='324';input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));})()")
        try await settled(report)
        precondition(report.reportTextUndo.count==undoCount+1)
        let width=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').getBoundingClientRect().width") as! Double
        precondition(abs(width-324)<1)
        let handled=try await report.web.evaluateJavaScript("StatsDirectReportEditor.menuCommand('undo')") as! Bool
        precondition(handled);try await settled(report)
        precondition(report.reportTextUndo.count==undoCount)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.command('redo')");try await settled(report)
        // Real pointer handlers: many moves form one native undo step. Escape
        // cancels a drag, and keyboard resizing follows the same history path.
        try await report.web.evaluateJavaScript("""
        (()=>{const h=document.querySelector('.report-chart-resize');h.dispatchEvent(new PointerEvent('pointerdown',{pointerId:7,button:0,clientX:400,clientY:300,bubbles:true}));document.dispatchEvent(new PointerEvent('pointermove',{pointerId:7,clientX:380,clientY:290,bubbles:true}));document.dispatchEvent(new PointerEvent('pointermove',{pointerId:7,clientX:375,clientY:285,bubbles:true}));})()
        """)
        try await settled(report);precondition(report.reportTextUndo.count==undoCount+1)
        try await report.web.evaluateJavaScript("document.dispatchEvent(new PointerEvent('pointerup',{pointerId:7,bubbles:true}))")
        try await settled(report);precondition(report.reportTextUndo.count==undoCount+2)
        let dragged=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').style.width") as! String
        precondition(dragged=="274px")
        try await report.web.evaluateJavaScript("""
        (()=>{const h=document.querySelector('.report-chart-resize');h.dispatchEvent(new PointerEvent('pointerdown',{pointerId:8,button:0,clientX:400,clientY:300,bubbles:true}));document.dispatchEvent(new PointerEvent('pointermove',{pointerId:8,clientX:350,clientY:270,bubbles:true}));h.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));})()
        """)
        try await settled(report);precondition(report.reportTextUndo.count==undoCount+2)
        let cancelled=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').style.width") as! String
        precondition(cancelled==dragged)
        try await report.web.evaluateJavaScript("document.querySelector('.report-chart-resize').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',shiftKey:true,bubbles:true}))")
        try await settled(report)
        let keyboard=try await report.web.evaluateJavaScript("document.querySelector('.report-body svg').style.width") as! String
        precondition(keyboard=="299px")
        try await report.web.evaluateJavaScript("(()=>{const input=document.querySelector('.report-chart-sizing input');input.value='320';input.dispatchEvent(new Event('change'));})()")
        try await settled(report)
        try await report.web.evaluateJavaScript("document.querySelector('.report-chart-sizing button').click()")
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
        try await report.web.evaluateJavaScript("(()=>{const img=document.querySelector('.report-body img[alt=\"Raster resize check\"]'),input=img.closest('.report-media').querySelector('input');input.value='200';input.dispatchEvent(new Event('change'));})()")
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
        print("PASS: SVG/raster resize, pointer drag/cancel, keyboard, fit, single-step native undo/redo, responsive proportions, clipboard and HTML/PDF/DOCX persistence");fflush(stdout)
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
            do { _=try LegacyReport.read(Data(invalid.utf8));preconditionFailure("Malformed RTF accepted") } catch {}
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
