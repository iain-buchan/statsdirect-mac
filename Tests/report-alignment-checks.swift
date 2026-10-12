import Cocoa
import PDFKit

extension ReportExportTests {
    @MainActor static func chartAlignment(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let report = v.makeReport()
        func svg(_ name: String, _ color: String) -> String {
            "<svg aria-label='\(name)' width='240' height='120' viewBox='0 0 240 120' xmlns='http://www.w3.org/2000/svg'><rect width='240' height='120' fill='\(color)'/><text x='8' y='22'>\(name)</text></svg>"
        }
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4v4XhPwgDABj/BWWqqcXlAAAAAElFTkSuQmCC"
        report.reportEntries = [ReportEntry(id:"alignment", title:"Chart alignment", operation:"", body:
            "<p id='alignment-note'>Text alignment stays independent.</p>" + svg("Left chart", "#dd2211") + svg("Centre chart", "#11bb33") + svg("Right chart", "#2244dd") + "<img alt='Right picture' src='\(png)' style='width:160px;height:80px'>", record:nil)]
        v.renderReport(report);try await settled(report)
        v.window.setContentSize(NSSize(width:1180,height:850));v.window.contentView!.layoutSubtreeIfNeeded()
        func js(_ script: String) async throws -> Any? { try await report.web.evaluateJavaScript(script) }
        func select(_ index: Int) async throws {
            _ = try await js("document.querySelectorAll('.report-body .report-media')[\(index)].querySelector('svg,img').dispatchEvent(new MouseEvent('click',{bubbles:true}))")
            try await Task.sleep(nanoseconds:150_000_000)
        }
        func align(_ command: String) async throws {
            _ = try await js("(()=>{const b=document.querySelector('[data-command=\(command)]');b.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));b.click();})()")
            try await settled(report)
        }
        let geometry = """
        (()=>[...document.querySelectorAll('.report-body .report-media')].map(w=>{
          const p=w.querySelector('svg,img'),b=p.getBoundingClientRect(),r=w.getBoundingClientRect();
          return {left:b.left-r.left,right:r.right-b.right,width:b.width,style:p.getAttribute('style')||''};}))()
        """
        func aligned(_ doc: Document, _ expected: [String]) async throws {
            let values = try await doc.web.evaluateJavaScript(geometry) as! [[String:Any]]
            precondition(values.count == expected.count, "picture count")
            for (value, alignment) in zip(values, expected) {
                let left=value["left"] as! Double, right=value["right"] as! Double
                let ok = alignment == "left" ? abs(left)<1 : alignment == "right" ? abs(right)<1 : abs(left-right)<1
                precondition(ok,"\(alignment) chart geometry: \(value)")
            }
        }
        // Let WebKit establish its initial editable focus before a synthetic click;
        // otherwise that deferred focus can overwrite the test's first selection.
        v.window.makeFirstResponder(report.web)
        _ = try await js("document.querySelector('.report-body').focus()")
        try await Task.sleep(nanoseconds:150_000_000)
        try await aligned(report,["left","left","left","left"])
        try await select(1)
        let state = try await js("(()=>{const p=StatsDirectReportEditor.selectedPicture(),r=getSelection().rangeCount?getSelection().getRangeAt(0):null;return {selected:!!p,left:document.querySelector('[data-command=justifyLeft]').getAttribute('aria-pressed'),full:document.querySelector('[data-command=justifyFull]').disabled,range:r?[r.startContainer.nodeName,r.startOffset,r.endContainer.nodeName,r.endOffset,r.collapsed,r.startContainer.parentElement.outerHTML.slice(0,240),r.endContainer.parentElement.outerHTML.slice(0,240),r.toString()]:[],margin:p?[p.style.marginLeft,getComputedStyle(p).marginLeft,p.style.marginRight,getComputedStyle(p).marginRight]:[]};})()") as! [String:Any]
        precondition(state["left"] as? String == "true" && state["full"] as? Bool == true,"chart alignment state and unavailable Justify: \(state)")
        try await align("justifyCenter")
        try await aligned(report,["left","center","left","left"])
        precondition(report.reportUndo.count==1,"aligning a chart is one undo step")
        precondition(try await js("document.querySelector('[data-command=justifyCenter]').getAttribute('aria-pressed')==='true'&&getComputedStyle(document.getElementById('alignment-note')).textAlign==='start'") as? Bool == true,"chart button state without changing adjacent text")
        try await align("justifyCenter")
        precondition(report.reportUndo.count==1,"repeating alignment is a no-op")
        _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        try await aligned(report,["left","left","left","left"])
        _ = try await js("StatsDirectReportEditor.command('redo')");try await settled(report)
        try await aligned(report,["left","center","left","left"])
        try await select(2)
        precondition(try await js("StatsDirectReportEditor.menuCommand('justifyRight')") as? Bool == true,"native Format menu handles a selected chart")
        try await settled(report)
        try await select(3);try await align("justifyRight")
        try await aligned(report,["left","center","right","right"])
        print("PASS: charts default left; toolbar and Format menu align only the selected chart with single-step undo/redo");fflush(stdout)

        precondition(try await js("""
        (()=>[...document.querySelectorAll('.report-body svg')].every(p=>{
          const source=p.cloneNode(true);source.style.fontFamily='Arial';source.style.fill='#345678';
          source.style.marginTop='16px';source.style.marginBottom='16px';
          const before=source.getAttribute('style'),out=StatsDirectReportEditor.exportableSvg(source);
          return ![...out.style].some(n=>n.startsWith('margin'))&&out.style.fontFamily==='Arial'&&out.style.fill===source.style.fill&&source.getAttribute('style')===before;
        }))()
        """) as? Bool == true,"standalone SVG drops report margins but retains drawing styles and leaves the source unchanged")
        print("PASS: standalone SVG removes page margins without changing chart drawing styles or report alignment");fflush(stdout)

        // Select actual text after a chart; the same controls must return to text editing.
        _ = try await js("(()=>{const p=document.getElementById('alignment-note');document.querySelector('.report-body').focus();getSelection().selectAllChildren(p);})()")
        try await Task.sleep(nanoseconds:50_000_000)
        precondition(try await js("StatsDirectReportEditor.selectedPicture()===null&&!document.querySelector('[data-command=justifyFull]').disabled") as? Bool == true,"text selection restores text controls")
        try await align("justifyCenter")
        precondition(try await js("getComputedStyle(document.getElementById('alignment-note')).textAlign==='center'") as? Bool == true,"text alignment remains functional")
        try await aligned(report,["left","center","right","right"])
        _ = try await js("(()=>{const p=document.querySelectorAll('.report-body .report-media'),r=document.createRange();r.setStartBefore(p[0]);r.setEndAfter(p[1]);getSelection().removeAllRanges();getSelection().addRange(r);})()")
        precondition(try await js("StatsDirectReportEditor.selectedPicture()===null") as? Bool == true,"a multiple-chart selection is not treated as one chart")
        print("PASS: text alignment is retained and mixed selections do not accidentally target one chart");fflush(stdout)

        // Geometry rather than implementation flags: the anchored edge/centre stays
        // fixed while the free corner follows the pointer. Escape leaves no history.
        for (index, delta, growth) in [(0,30,30),(1,30,60),(2,-30,30)] {
            try await select(index)
            let count=report.reportUndo.count
            let result=try await js("""
            (()=>{const w=document.querySelectorAll('.report-body .report-media')[\(index)],p=w.querySelector('svg'),h=w.querySelector('button'),b=p.getBoundingClientRect(),r=h.getBoundingClientRect();
              const x=r.left+r.width/2,y=r.top+r.height/2,ev=(type,target,dx)=>target.dispatchEvent(new PointerEvent(type,{bubbles:true,cancelable:true,pointerId:19,button:0,clientX:x+dx,clientY:y}));
              ev('pointerdown',h,0);ev('pointermove',document,\(delta));ev('pointerup',document,\(delta));
              const a=p.getBoundingClientRect();ev('pointerdown',h,0);ev('pointermove',document,20);document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
              return {growth:a.width-b.width,anchor:\(index)==0?a.left-b.left:\(index)==1?(a.left+a.right-b.left-b.right)/2:a.right-b.right,cancelled:p.getBoundingClientRect().width-a.width};})()
            """) as! [String:Double]
            try await settled(report)
            precondition(abs(result["growth"]!-Double(growth))<1&&abs(result["anchor"]!)<1&&abs(result["cancelled"]!)<1,"alignment-aware resizing: \(result)")
            precondition(report.reportUndo.count==count+1,"one resize undo and no cancelled edit")
            _ = try await js("StatsDirectReportEditor.command('undo')");try await settled(report)
        }
        try await aligned(report,["left","center","right","right"])
        print("PASS: left/centre/right corner resizing keeps the correct anchor, with undo and Escape cancellation");fflush(stdout)

        _ = try await js("document.querySelectorAll('.report-body .report-media')[2].focus();getSelection().removeAllRanges()")
        precondition(try await js("StatsDirectReportEditor.menuCommand('justifyCenter')") as? Bool == true,"keyboard-focused chart aligns without a text selection")
        try await settled(report)
        try await aligned(report,["left","center","center","right"])
        try await select(2)
        _ = try await js("document.querySelector('[data-command=justifyRight]').focus();document.querySelector('[data-command=justifyRight]').click()")
        try await settled(report)
        precondition(try await js("document.querySelector('[data-command=justifyRight]').getAttribute('aria-pressed')==='true'") as? Bool == true,"keyboard toolbar focus retains chart selection and updates its state")
        try await aligned(report,["left","center","right","right"])

        // A fresh full-width right-aligned picture retains its choice when narrowed.
        try await select(2)
        _ = try await js("StatsDirectReportEditor.command('pictureFit');StatsDirectReportEditor.command('pictureWidth',240)")
        try await settled(report);try await aligned(report,["left","center","right","right"])
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        _ = try await v.transferReportClipboard(report,command:"copy",pasteboard:board)
        let clipboard=board.string(forType:.html)!
        try clipboard.write(to:output.appendingPathComponent("chart-alignment-clipboard.html"),atomically:true,encoding:.utf8)
        // Public HTML exercises Office-compatible raster fallback and sanitization.
        board.clearContents();board.setString(clipboard,forType:.html)
        let pasted=v.makeReport();try await settled(pasted)
        try await pasted.web.evaluateJavaScript("document.querySelector('.report-body').focus();getSelection().selectAllChildren(document.querySelector('.report-body'))")
        _ = try await v.transferReportClipboard(pasted,command:"paste",pasteboard:board);try await settled(pasted)
        try await aligned(pasted,["right"])
        precondition(pasted.reportUndo.count==1,"aligned picture paste is one undo step")
        print("PASS: Fit then resize and public HTML clipboard/paste retain chart alignment");fflush(stdout)

        v.tabs.selectTabViewItem(report.item)
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("chart-alignment."+format.rawValue))
            if format == .pdf {
                let pdf=PDFDocument(data:data)!
                precondition(pdf.pageCount==1,"alignment fixture fits one PDF page")
                let image=pdf.page(at:0)!.thumbnail(of:NSSize(width:595,height:842),for:.mediaBox)
                let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
                var positions=[Int.max,Int.max,Int.max,Int.max],ends=[0,0,0,0]
                for y in 0..<bitmap.pixelsHigh {for x in 0..<bitmap.pixelsWide {
                    guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{continue}
                    let r=c.redComponent,g=c.greenComponent,b=c.blueComponent
                    // Dominant channels tolerate PDFKit's display-profile conversion.
                    let index = r>g+0.25&&r>b+0.25 ? 0 : g>r+0.25&&g>b+0.25 ? 1 : b>r+0.25&&b>g+0.25 ? 2 : r>g+0.1&&g>b+0.25 ? 3 : -1
                    if index>=0 {positions[index]=min(positions[index],x);ends[index]=max(ends[index],x)}
                }}
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("chart-alignment-pdf.png"))
                precondition(positions.allSatisfy{$0 != Int.max}&&positions[0]+40<positions[1]&&positions[1]+40<positions[2]&&abs(ends[2]-ends[3])<2,"PDF preserves three distinct chart alignments and right-aligned raster: \(positions), \(ends)")
            }
        }
        let reopened=try await v.importReport(output.appendingPathComponent("chart-alignment.html"));try await settled(reopened)
        try await aligned(reopened,["left","center","right","right"])
        v.window.setContentSize(NSSize(width:1000,height:850));v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:100_000_000);try await aligned(reopened,["left","center","right","right"])
        try await v.reportExportData(reopened,format:.docx).write(to:output.appendingPathComponent("chart-alignment-reopened.docx"))
        let image=try await reopened.web.takeSnapshot(configuration:nil)
        try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("chart-alignment-reopened.png"))
        print("PASS: HTML reopening/responsive layout and rendered PDF retain chart alignment; Word packages checked separately");fflush(stdout)
        for doc in [reopened,pasted,report]{v.remove(doc)}
    }
}
