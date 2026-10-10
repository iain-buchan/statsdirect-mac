import Cocoa
import WebKit

extension ReportExportTests {
    @MainActor static func transfers(_ v: Viewer, output: URL) async throws {
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        let report=v.makeReport(),sourceID=UUID().uuidString,targetID=UUID().uuidString
        let source="""
        <p id="transfer-source">Alpha <strong style="font-family:'Times New Roman';font-size:18pt;color:#0066cc">formatted finding</strong> Omega</p>
        <table id="transfer-table"><tbody><tr><th colspan="2">Merged heading</th></tr><tr><td>Label A</td><td>12.5</td></tr><tr><td>Keep B</td><td>27</td></tr></tbody></table>
        <ol><li>First interpretation</li><li>Second interpretation</li></ol>
        <svg id="transfer-svg" viewBox="0 0 300 150" width="300" height="150" style="width:240px;height:auto"><defs><clipPath id="transfer-clip"><rect width="300" height="150"/></clipPath></defs><g clip-path="url(#transfer-clip)"><rect width="300" height="150" fill="white"/><path d="M10 120L140 20L270 110" fill="none" stroke="blue"/><text x="15" y="140" font-size="12">Vector chart</text></g></svg>
        <p id="transfer-tail">Unselected ending</p>
        """
        report.reportEntries=[ReportEntry(id:sourceID,title:"Source",operation:"",body:source,rPlan:nil),ReportEntry(id:targetID,title:"Destination",operation:"",body:"<p id='transfer-target'>Destination: </p>",rPlan:nil)]
        v.renderReport(report);try await settled(report)
        try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true)")
        func js(_ script:String) async throws -> Any {
            do {return try await report.web.evaluateJavaScript(script) ?? NSNull()}
            catch {print("Transfer JS error:",script,(error as NSError).userInfo);print("DOM:",try await report.web.evaluateJavaScript("[...document.querySelectorAll('.report-body')].map(b=>b.innerHTML)") ?? "");fflush(stdout);throw error}
        }
        func choose(_ selector:String,caret:Bool=false) async throws {
            _ = try await js("(()=>{const p=document.querySelector(\(v.jsString(selector)));p.closest('.report-body').focus();const r=document.createRange();r.selectNodeContents(p);\(caret ? "r.collapse(false);":"")const s=window.getSelection();s.removeAllRanges();s.addRange(r);})()")
        }
        func command(_ name:String) async throws {_ = try await v.transferReportClipboard(report,command:name,pasteboard:board);try await settled(report)}
        func undo() async throws {_ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)}
        func redo() async throws {_ = try await js("StatsDirectReportEditor.command('redo')");try await settled(report)}
        func check(_ expression:String,_ reason:String) async throws {
            let result=try await js(expression) as! Bool
            if !result {print("Transfer failure:",reason,try await js("[...document.querySelectorAll('.report-body')].map(b=>StatsDirectReportEditor.serialize(b))"));fflush(stdout)}
            precondition(result,reason)
        }
        try await choose("#transfer-source strong");try await command("cut")
        precondition(report.reportTextUndo.count==1)
        try await check("!document.getElementById('transfer-source').textContent.includes('formatted finding')","Cut did not remove selection")
        precondition(board.string(forType:Viewer.reportFragmentType)!.contains("Times New Roman"))
        try await choose("#transfer-target",caret:true);try await command("paste")
        precondition(report.reportTextUndo.count==2)
        try await check("(()=>{const p=document.getElementById('transfer-target'),s=[...p.querySelectorAll('span')].find(e=>e.textContent==='formatted finding'),c=getComputedStyle(s);return p.textContent==='Destination: formatted finding'&&c.fontSize==='24px'&&c.fontFamily.includes('Times New Roman')&&c.color==='rgb(0, 102, 204)'&&Number(c.fontWeight)>=700;})()","Formatted cut/paste changed text or styling")
        try await undo();try await check("document.getElementById('transfer-target').textContent==='Destination: '","Undo paste failed")
        try await undo();try await check("document.getElementById('transfer-source').textContent.includes('formatted finding')","Undo cut failed")
        try await redo();try await redo();try await undo();try await undo()

        // Whole mixed selection: table spans, lists, font, exact chart width and
        // SVG clip references must survive the private/native clipboard path.
        try await choose("#result-\(sourceID) .report-body");try await command("copy")
        precondition(board.string(forType:.html)!.contains("data:image/png;base64,") && board.string(forType:Viewer.reportFragmentType)!.contains("<svg"))
        try await choose("#transfer-target",caret:true);try await command("paste")
        try await check("(()=>{const b=document.querySelector('#result-\(targetID) .report-body'),s=b.querySelector('svg'),clip=s.querySelector('clipPath');return b.querySelector('th').colSpan===2&&b.querySelectorAll('ol li').length===2&&b.textContent.includes('12.5')&&s.style.width==='240px'&&clip.id!=='transfer-clip'&&s.querySelector('g').getAttribute('clip-path')==='url(#'+clip.id+')'&&b.querySelectorAll('.report-media').length===1;})()","Mixed paste lost table/list/vector content")
        try await undo()

        // A partial table cut clears selected cell content without deleting the
        // table shell, other cells, merged headings or values outside selection.
        _ = try await js("(()=>{const t=document.getElementById('transfer-table'),r=document.createRange();t.closest('.report-body').focus();r.setStart(t.rows[1].cells[0].firstChild,6);r.setEnd(t.rows[1].cells[1].firstChild,2);const s=window.getSelection();s.removeAllRanges();s.addRange(r);})()")
        try await command("cut")
        try await check("(()=>{const t=document.getElementById('transfer-table');return t.rows.length===3&&t.rows[0].cells[0].colSpan===2&&t.rows[1].cells[0].textContent==='Label '&&t.rows[1].cells[1].textContent==='.5'&&t.rows[2].textContent==='Keep B27';})()","Partial table cut removed unselected data")
        precondition(board.string(forType:Viewer.reportFragmentType)!.contains("<table"))
        try await undo()

        func dragSelection(copy:Bool=false,inside:Bool=false) async throws {
            _ = try await js("""
            (()=>{
              const start=document.getElementById('transfer-source'),svg=document.getElementById('transfer-svg').closest('.report-media'),r=document.createRange();
              start.closest('.report-body').focus();r.setStartBefore(start);r.setEndAfter(svg);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(r);
              const target=document.getElementById('\(inside ? "transfer-source":"transfer-target")');target.scrollIntoView({block:'center'});
              const at=document.createRange();at.selectNodeContents(target);at.collapse(\(inside));const box=at.getClientRects()[0]||target.getBoundingClientRect();
              const transfer=new DataTransfer();start.dispatchEvent(new DragEvent('dragstart',{dataTransfer:transfer,bubbles:true}));
              const position={dataTransfer:transfer,bubbles:true,cancelable:true,clientX:box.left+1,clientY:box.top+Math.min(8,box.height/2),altKey:\(copy)};
              target.dispatchEvent(new DragEvent('dragover',position));target.dispatchEvent(new DragEvent('drop',position));start.dispatchEvent(new DragEvent('dragend',{dataTransfer:transfer,bubbles:true}));
            })()
            """)
            try await settled(report)
        }
        let beforeDrag=report.reportTextUndo.count
        try await dragSelection(inside:true)
        precondition(report.reportTextUndo.count==beforeDrag,"Dropping onto the selection should do nothing")
        try await dragSelection()
        precondition(report.reportTextUndo.count==beforeDrag+1 && report.reportTextUndo.last!.edits.count==2,"Move must be one two-section undo transaction")
        try await check("(()=>{const a=document.querySelector('#result-\(sourceID) .report-body'),b=document.querySelector('#result-\(targetID) .report-body');return !a.querySelector('table,svg')&&a.textContent.includes('Unselected ending')&&b.querySelector('table')&&!!b.querySelector('svg');})()","Drag did not move the mixed selection")
        try await undo()
        try await check("document.querySelectorAll('.report-body svg').length===1&&!!document.getElementById('transfer-table')&&document.getElementById('transfer-target').textContent==='Destination: '","Undo move did not restore both sections")
        try await redo();try await undo()
        try await dragSelection(copy:true)
        try await check("document.querySelectorAll('.report-body svg').length===2&&!!document.getElementById('transfer-table')","Option-drag did not copy")
        try await undo()

        // Moving words later within the same paragraph must track the live
        // destination through deletion, preserve spaces and remain one undo.
        let beforeInline=report.reportTextUndo.count
        _ = try await js("""
        (()=>{
          const p=document.getElementById('transfer-source'),r=document.createRange();p.closest('.report-body').focus();r.selectNodeContents(p.querySelector('strong'));const s=window.getSelection();s.removeAllRanges();s.addRange(r);
          p.scrollIntoView({block:'center'});const at=document.createRange();at.setStart(p.lastChild,p.lastChild.textContent.length);at.collapse(true);const box=at.getClientRects()[0],transfer=new DataTransfer();
          p.dispatchEvent(new DragEvent('dragstart',{dataTransfer:transfer,bubbles:true}));p.dispatchEvent(new DragEvent('drop',{dataTransfer:transfer,bubbles:true,cancelable:true,clientX:box.left+1,clientY:box.top+5}));p.dispatchEvent(new DragEvent('dragend',{dataTransfer:transfer,bubbles:true}));
        })()
        """);try await settled(report)
        precondition(report.reportTextUndo.count==beforeInline+1)
        try await check("document.getElementById('transfer-source').textContent==='Alpha  Omegaformatted finding'","Same-paragraph drag lost text or used the old destination offset")
        try await undo()

        // Direct pointer gestures also work without WebKit's native text-drag
        // hold delay. Grabbing a chart inside a mixed selection moves it all.
        func pointerMove(_ kind:String,copy:Bool=false,cancel:Bool=false) async throws {
            _ = try await js("""
            (()=>{
              const p=document.getElementById('transfer-source'),svg=document.getElementById('transfer-svg'),strong=p.querySelector('strong'),r=document.createRange(),s=window.getSelection();p.closest('.report-body').focus();
              if('\(kind)'==='mixed'){r.setStartBefore(p);r.setEndAfter(svg.closest('.report-media'));}
              else {r.selectNodeContents(strong);if('\(kind)'==='chart')r.collapse(true);}
              s.removeAllRanges();s.addRange(r);
              const start='\(kind)'==='text'?strong:svg;start.scrollIntoView({block:'center'});const from=start.getBoundingClientRect();
              start.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true,button:0,pointerId:31,clientX:from.left+from.width/2,clientY:from.top+from.height/2}));
              const target=document.getElementById('transfer-target');target.scrollIntoView({block:'center'});const at=document.createRange();at.setStart(target.firstChild,target.firstChild.length);at.collapse(true);const box=at.getClientRects()[0],position={bubbles:true,cancelable:true,button:0,pointerId:31,clientX:box.left+1,clientY:box.top+5,altKey:\(copy)};
              target.dispatchEvent(new PointerEvent('pointermove',position));
              if(\(cancel))document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
              target.dispatchEvent(new PointerEvent('pointerup',position));
            })()
            """);try await settled(report)
        }
        let beforePointer=report.reportTextUndo.count
        try await pointerMove("text")
        precondition(report.reportTextUndo.count==beforePointer+1&&report.reportTextUndo.last!.edits.count==2)
        try await check("!document.getElementById('transfer-source').textContent.includes('formatted finding')&&document.getElementById('transfer-target').textContent.includes('formatted finding')&&document.getElementById('transfer-target').textContent.replace('formatted finding','')==='Destination: '","Direct text drag lost selected text or destination spacing")
        try await undo()
        try await pointerMove("chart")
        try await check("!document.querySelector('#result-\(sourceID) .report-body svg')&&document.querySelector('#result-\(targetID) .report-body svg').style.width==='240px'","Direct SVG drag failed")
        try await undo()
        try await pointerMove("mixed",copy:true)
        try await check("document.querySelectorAll('.report-body svg').length===2&&document.querySelectorAll('.report-body table').length===2","Dragging a selected chart discarded the rest of its mixed selection")
        try await undo()
        try await pointerMove("mixed",cancel:true)
        precondition(report.reportTextUndo.count==beforePointer,"Escape during a move changed the report")
        try await check("!!document.getElementById('transfer-table')&&document.querySelectorAll('.report-body svg').length===1&&!document.querySelector('.report-drop-caret')","Cancelled pointer move left changed content or an insertion marker")

        // Clipboard paste replacing a selection that crosses result sections
        // should restore every affected section together when undone.
        let beforeReplacement=report.reportTextUndo.count
        _ = try await js("(()=>{const a=document.getElementById('transfer-tail'),b=document.getElementById('transfer-target'),r=document.createRange();a.closest('.report-body').focus();r.setStart(a.firstChild,11);r.setEnd(b.firstChild,12);const s=window.getSelection();s.removeAllRanges();s.addRange(r);})()")
        board.clearContents();board.setString("replacement",forType:.string);try await command("paste")
        precondition(report.reportTextUndo.count==beforeReplacement+1&&report.reportTextUndo.last!.edits.count==2)
        try await check("document.getElementById('transfer-tail').textContent==='Unselected replacement'&&document.getElementById('transfer-target').textContent===' '","Multi-section paste removed the wrong content")
        try await undo()

        // A pasteboard write can take time (chart fallbacks). Typing meanwhile
        // must invalidate the cut, never delete a newer version of the content.
        try await choose("#transfer-source strong")
        let pending=try await js("StatsDirectReportEditor.prepareClipboard(true)") as! [String:Any]
        _ = try await js("document.getElementById('transfer-source').append(document.createTextNode(' New text'))")
        let removed=try await js("StatsDirectReportEditor.cutPrepared(\(v.jsString(pending["token"] as! String)))") as! Bool
        precondition(!removed)
        try await check("document.getElementById('transfer-source').textContent.includes('formatted finding')","Stale cut removed new work")
        _ = try await js("document.getElementById('transfer-source').lastChild.remove()")

        // External rich HTML is sanitized but its useful presentation remains.
        board.clearContents();board.setString("<style>.pasted{font-family:Georgia;font-size:20px;color:rgb(128,0,0)}</style><p class='pasted' onclick='window.reportPasteUnsafe=1'>External rich text</p><script>window.reportPasteUnsafe=1</script><img src='https://example.invalid/tracker.png'><a href='javascript:alert(1)'>Bad link</a>",forType:.html)
        try await choose("#transfer-target",caret:true);try await command("paste")
        try await check("(()=>{const b=document.querySelector('#result-\(targetID) .report-body'),p=[...b.querySelectorAll('p')].find(p=>p.textContent==='External rich text');return !window.reportPasteUnsafe&&!b.querySelector('script,style,img[src^=http],[onclick],a[href^=javascript]')&&p.style.fontFamily==='Georgia'&&p.style.fontSize==='20px';})()","External paste lost formatting or retained active content")
        try await undo()
        board.clearContents();board.setData(Data("{\\rtf1\\ansi Bold \\b RTF emphasis\\b0 .}".utf8),forType:.rtf)
        try await choose("#transfer-target",caret:true);try await command("paste")
        try await check("document.querySelector('#result-\(targetID) .report-body').textContent.includes('RTF emphasis')","RTF paste failed")
        try await undo()

        // Finish with a moved table/chart, then save and reopen it.
        try await dragSelection()
        for format in ReportFormat.allCases {try (await v.reportExportData(report,format:format)).write(to:output.appendingPathComponent("moved-report."+format.rawValue))}
        let reopened=try await v.importReport(output.appendingPathComponent("moved-report.html"));try await settled(reopened)
        let restored=try await reopened.web.evaluateJavaScript("document.querySelectorAll('.report-body svg').length===1&&document.querySelector('.report-body th').colSpan===2&&document.querySelector('.report-body svg').style.width==='240px'") as! Bool
        precondition(restored)
        print("PASS: native private/public clipboard, formatted cut/paste with undo/redo, table spans and partial cells, lists, sized SVG and clip references, drag/Option-drag between sections with atomic undo, self-drop, stale-cut protection, external HTML/RTF paste, and moved HTML/PDF/DOCX/reopen");fflush(stdout)
    }
}
