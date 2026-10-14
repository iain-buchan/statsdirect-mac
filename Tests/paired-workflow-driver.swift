import Cocoa
import WebKit

@main struct PairedWorkflowTests {
    @MainActor static func check(_ ok: Bool, _ text: String) throws {
        guard ok else { throw NSError(domain:"PairedWorkflow",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
        print("PASS: " + text); fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end=Date().addingTimeInterval(30)
        while Date()<end {
            if try await condition() { return }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw NSError(domain:"PairedWorkflow",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out waiting for paired form or report"])
    }
    @MainActor static func js(_ doc: Document, _ script: String) async throws -> Any? {
        try await doc.web.evaluateJavaScript(script)
    }
    @MainActor static func isTrue(_ doc: Document, _ script: String) async throws -> Bool {
        try await js(doc,script) as? Bool == true
    }
    @MainActor static func menuItem(_ menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? String == "TPaired" { return item }
            if let sub=item.submenu,let found=menuItem(sub) { return found }
        }
        return nil
    }
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        UserDefaults.standard.set(["use-default-ci":true,"default-ci":"95","selectGroupsByIdentifier":false],forKey:"analysisDefaults")
        let viewer=Viewer();app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: paired workflow checks completed");fflush(stdout) }
                catch { print("FAIL: \(error)");fflush(stdout);exit(1) }
                viewer.closeApproved=true;app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+180) { print("FAIL: paired workflow timed out");fflush(stdout);exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.window.setContentSize(NSSize(width:1180,height:850))
        // Settle AppKit's split/tab layout before synthetic canvas gestures.
        v.window.contentView?.layoutSubtreeIfNeeded()
        v.workspaceSplit.adjustSubviews(); v.documentSplit.adjustSubviews()
        let grid=v.newDocument(kind:"grid",title:"PEFR selection fixture",url:v.root.appendingPathComponent("Grid/index.html"))
        v.window.contentView?.layoutSubtreeIfNeeded()
        try check(grid.web.bounds.width > 0 && grid.web.bounds.height > 0, "worksheet has a visible native frame before canvas gestures")
        try await wait { !grid.web.isLoading && grid.web.url != nil }
        try await wait { try await isTrue(grid,"!!window.statsDirectGrid && !!document.querySelector('canvas')") }
        _=try await grid.web.callAsyncJavaScript("""
        const before=[312,242,340,388,296,254,391,402,290],after=[300,201,232,312,220,256,328,330,231];
        await statsDirectGrid.loadWorkbook({name:'PEFR',sheets:[{name:'Measurements',rows:100,columns:8,headerRow:true,cells:[
          {col:3,row:0,text:'PEFR Before',kind:'text'},{col:4,row:0,text:'PEFR After',kind:'text'},
          ...before.map((n,i)=>({col:3,row:i+1,text:String(n),kind:'number'})),
          ...after.map((n,i)=>({col:4,row:i+1,text:String(n),kind:'number'})),
          {col:6,row:99,text:'999',kind:'number'}]}]});
        return true;
        """,arguments:[:],in:nil,contentWorld:.page)
        // One heading drag: use actual grid event handlers, not an analysis fixture.
        func select(_ first:Int,_ last:Int,row:Int = -1) async throws {
            v.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
            v.tabs.selectTabViewItem(grid.item)
            v.window.contentView?.layoutSubtreeIfNeeded()
            _=try await grid.web.callAsyncJavaScript("""
            // Allow React's layout and pointer effects to commit. WKWebView may
            // suspend animation-frame callbacks in an automated app even with a
            // visible native frame; these synthetic gestures need DOM layout,
            // not an indefinitely awaited display-refresh callback.
            await new Promise(r=>setTimeout(r,100));
            const b=document.querySelector('canvas').getBoundingClientRect();
            if(b.width<=0 || b.height<=0)throw new Error('Canvas has no laid-out area');
            const y=b.y+(row<0?18:36+row*29+14),x=c=>b.x+48+c*178+89;
            const send=(type,c,buttons)=>document.elementFromPoint(x(c),y).dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:x(c),clientY:y,button:0,buttons}));
            send('mousemove',first,0);send('mousedown',first,1);
            await new Promise(r=>setTimeout(r,65));
            for(let i=1;i<=8;i++){send('mousemove',first+(last-first)*i/8,1);await new Promise(r=>setTimeout(r,30));}
            send('mouseup',last,0);return true;
            """,arguments:["first":first,"last":last,"row":row],in:nil,contentWorld:.page)
            if row < 0 {
                let expected=Array(min(first,last)...max(first,last))
                try await wait {
                    try await js(grid,"statsDirectGrid.analysisSource().selection") as? [Int] == expected
                }
            }
        }
        func open() async throws -> Document {
            v.analysisSourceID=grid.id
            let item=menuItem(NSApp.mainMenu!)!
            try check(item.menu?.title == "Parametric","paired t test is selected through the Parametric menu")
            try check(NSApp.sendAction(item.action!,to:item.target,from:item),"menu selection starts the paired-test form")
            let doc=v.active!
            try await wait { try await isTrue(doc,"!!document.querySelector('.paired-inputs button[type=submit]')") }
            _=try await js(doc,"const original=statsDirectOperation.update;statsDirectOperation.update=s=>{window.pairedState=s;original(s);};true")
            return doc
        }
        func run(_ doc:Document,agreement:Bool) async throws -> Document {
            if agreement { _=try await js(doc,"document.querySelector('input[name=paired-agreement]').click();true") }
            try check(try await isTrue(doc,"document.querySelector('.paired-inputs button[type=submit]').textContent==='Run' && !document.body.innerText.includes('Continue →')"),"one Run button; no data-confirmation step")
            _=try await js(doc,"document.querySelector('.paired-inputs button[type=submit]').click();true")
            try await wait { doc.completedJobID != nil && v.active?.reportEntries?.isEmpty == false }
            try check(try await isTrue(doc,"pairedState.state==='complete'"),"one Run completes the original engine operation without another prompt")
            return v.active!
        }
        try await select(3,4)
        try check(try await isTrue(grid,"JSON.stringify(statsDirectGrid.analysisSource().selection)==='[3,4]'"),"one drag selects both original measurement columns")
        let paired=try await open()
        try check(try await isTrue(paired,"document.querySelector('.paired-inputs').innerText.includes('PEFR Before → PEFR After') && document.querySelector('.paired-inputs').innerText.includes('rows 2–10')"),"selected labels and only the nine used pairs are ready on opening")
        let report=try await run(paired,agreement:true)
        let body=report.reportEntries!.last!.body
        try check(body.contains("56.111111") && body.contains("29.842662") && body.contains("82.37956"),"PEFR mean difference and 95% confidence limits match the Windows example")
        let points=try NSRegularExpression(pattern:"<ellipse\\b").numberOfMatches(in:body,range:NSRange(body.startIndex...,in:body))
        try check(body.contains("<svg") && points==9 && body.contains("123.090887"),"agreement chart is SVG with all nine pairs and the original limits")
        try check(try await isTrue(paired,"pairedState.history.find(h=>h.name==='gamma').value===95 && pairedState.history.find(h=>h.name==='doAgreement').value===true && pairedState.history.find(h=>h.name==='data').value.columns.every(c=>c.values.length===9)"),"default 95%, checked agreement and exact selected data reach the engine history")

        let plain=try await open(),same=try await run(plain,agreement:false)
        try check(same===report && report.reportEntries!.count==2 && !report.reportEntries!.last!.body.contains("<svg"),"unchecked agreement uses the same single Run and appends to the active report without a chart")

        try await select(3,3)
        let one=try await open()
        try check(try await isTrue(one,"document.querySelector('input[name=paired-agreement]').disabled"),"one selected differences column disables the unavailable agreement option")
        _=try await run(one,agreement:false)
        try check(report.reportEntries!.count==3,"one-column differences retain their one-Run analysis")

        try await select(2,4)
        let wide=try await open()
        try check(try await isTrue(wide,"document.querySelectorAll('.column-chooser input:checked').length===0 && !!document.querySelector('.column-chooser')"),"a wider selection is not silently cropped to two columns")
        v.remove(wide)

        try await select(3,4)
        let change=try await open()
        _=try await js(change,"Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Change data…').click();true")
        try await wait { try await isTrue(change,"!!document.querySelector('.column-chooser')") }
        try check(try await isTrue(change,"document.querySelectorAll('.column-chooser input:checked').length===2 && !!document.querySelector('input[name=paired-agreement]')"),"optional Change data retains both columns and agreement on the same form")
        _=try await js(change,"document.querySelector('.cancel button').click();true")
        try await wait { try await isTrue(change,"window.pairedState?.state==='cancelled'") }
        try check(report.reportEntries!.count==3,"cancelling the combined form produces no report")

        UserDefaults.standard.set(["use-default-ci":true,"default-ci":"99","selectGroupsByIdentifier":false],forKey:"analysisDefaults")
        let custom=try await open()
        _=try await run(custom,agreement:true)
        try check(try await isTrue(custom,"pairedState.history.find(h=>h.name==='gamma').value===99"),"the saved confidence level is honored without another click")

        UserDefaults.standard.set(["use-default-ci":false,"default-ci":"95","selectGroupsByIdentifier":false],forKey:"analysisDefaults")
        let explicit=try await open()
        _=try await js(explicit,"document.querySelector('input[name=paired-agreement]').click();document.querySelector('.paired-inputs button[type=submit]').click();true")
        try await wait { try await isTrue(explicit,"window.pairedState?.prompt?.kind==='confidence' && !!document.querySelector('form input[type=number]')") }
        _=try await js(explicit,"document.querySelector('form').requestSubmit();true")
        try await wait { explicit.completedJobID != nil }
        try check(try await isTrue(explicit,"pairedState.history.find(h=>h.name==='doAgreement').value===true"),"deliberately requesting confidence each time keeps the agreement choice across that prompt")
    }
}
