import Cocoa
import WebKit

@main struct AnalysisWorkflowTests {
    @MainActor static func check(_ ok: Bool, _ text: String) throws {
        guard ok else { throw NSError(domain: "AnalysisWorkflow", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        print("PASS: " + text); fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(30)
        while Date() < end { if try await condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }
        throw NSError(domain: "AnalysisWorkflow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for analysis form"])
    }
    @MainActor static func js(_ doc: Document, _ script: String) async throws -> Any? { try await doc.web.evaluateJavaScript(script) }
    @MainActor static func yes(_ doc: Document, _ script: String) async throws -> Bool { try await js(doc, script) as? Bool == true }
    @MainActor static func item(_ menu: NSMenu, _ operation: String) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? String == operation { return item }
            if let sub = item.submenu, let found = self.item(sub, operation) { return found }
        }
        return nil
    }
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        UserDefaults.standard.set(["use-default-ci":true, "default-ci":"95", "selectGroupsByIdentifier":false], forKey: "analysisDefaults")
        let viewer = Viewer(); app.delegate = viewer
        DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: selection and combined analysis workflows"); fflush(stdout) }
                catch { if let doc=viewer.active { print("STATE:", (try? await doc.web.evaluateJavaScript("JSON.stringify({state:window.formState,html:document.body.innerText})")) as Any) }; print("FAIL: \(error)"); fflush(stdout); exit(1) }
                viewer.closeApproved = true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now()+180) { print("FAIL: analysis workflows timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.window.setContentSize(NSSize(width: 1180, height: 850))
        let grid = v.newDocument(kind: "grid", title: "Selection fixture", url: v.root.appendingPathComponent("Grid/index.html"))
        try await wait { try await yes(grid, "!!window.statsDirectGrid && !!document.querySelector('canvas')") }
        _ = try await grid.web.callAsyncJavaScript("""
        await statsDirectGrid.loadWorkbook({name:'Selected measurements',sheets:[{name:'Data',rows:100,columns:6,headerRow:true,cells:[
          {col:0,row:0,text:'Before',kind:'text'},{col:1,row:0,text:'After',kind:'text'},
          ...[12,3,4,7,8].map((n,i)=>({col:0,row:i+1,text:String(n),kind:'number'})),
          ...[8,17,9,11,13].map((n,i)=>({col:1,row:i+1,text:String(n),kind:'number'})),
          {col:5,row:99,text:'999',kind:'number'}]}]});return true;
        """, arguments: [:], in: nil, contentWorld: .page)
        func select(_ last: Int, rectangle: Bool = false) async throws {
            v.tabs.selectTabViewItem(grid.item)
            v.window.contentView!.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds:150_000_000)
            _ = try await grid.web.callAsyncJavaScript("""
            const b=document.querySelector('canvas').getBoundingClientRect(),x=c=>b.x+48+c*178+89;
            const y=r=>b.y+(r<0?18:36+r*29+14),startRow=rectangle?1:-1,endRow=rectangle?2:-1;
            const send=(type,c,r,buttons,shiftKey=false)=>document.elementFromPoint(x(c),y(r)).dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:x(c),clientY:y(r),button:0,buttons,shiftKey}));
            send('mousemove',0,startRow,0);send('mousedown',0,startRow,1);await new Promise(r=>setTimeout(r,60));
            if(rectangle){send('mouseup',0,startRow,0);send('mousedown',last,endRow,1,true);send('mouseup',last,endRow,0,true);}else{send('mousemove',last,endRow,1);await new Promise(r=>setTimeout(r,80));send('mouseup',last,endRow,0);}await new Promise(r=>setTimeout(r,80));return true;
            """, arguments: ["last":last, "rectangle":rectangle], in:nil, contentWorld:.page)
        }
        func open(_ name: String) throws -> Document {
            v.analysisSourceID = grid.id; let menu = item(NSApp.mainMenu!, name)!
            try check(NSApp.sendAction(menu.action!, to:menu.target, from:menu), "\(name) starts from its analysis menu")
            return v.active!
        }
        try await select(1)
        let unpaired = try open("TUnpaired")
        try await wait { unpaired.completedJobID != nil }
        let report = v.documents.last { $0.kind == "report" }!
        try check(report.reportEntries?.count == 1, "unpaired t uses two highlighted columns without a confirmation step")
        let history: [String:Any] = try await withCheckedThrowingContinuation { c in
            v.analysisRequest(["action":"poll", "id":unpaired.completedJobID!], entry:"statsdirect_operation") { c.resume(with:$0) }
        }
        let inputs = history["history"] as! [[String:Any]]
        let data = inputs.first { $0["name"] as? String == "data" }!["value"] as! [String:Any]
        let columns = data["columns"] as! [[String:Any]]
        try check(columns.count == 2 && (columns[0]["values"] as! [Any]).count == 5, "analysis uses exactly the selected columns and their used rows")
        try check(inputs.first { $0["name"] as? String == "gamma" }?["value"] as? Double == 95, "saved 95% confidence needs no separate click")

        try await select(1, rectangle:true)
        let selection = try await js(grid,"statsDirectGrid.analysisSource()") as! [String:Any]
        try check((selection["selection"] as? [Int]) == [0,1] && (selection["range"] as? [String:Int]) == ["first":2,"last":3], "fixture selects exactly four worksheet cells")
        let table = try open("Chi2by2")
        try await wait { try await yes(table, "!!document.querySelector('.analysis-form .grid')") }
        try await wait { try await yes(table, "!document.querySelector('.analysis-form fieldset[aria-busy=true]')") }
        try check(try await yes(table, "document.querySelector('.analysis-form').innerText.includes('2 rows × 2 columns')&&!document.body.innerText.includes('Continue →')&&!document.body.innerText.includes('has not been copied')"), "chi-square table and study options share one Run form")
        _ = try await js(table, "const original=statsDirectOperation.update;statsDirectOperation.update=s=>{window.formState=s;original(s);};document.querySelector('input[name=\"choice-study_type\"]:last-of-type');true")
        _ = try await js(table, "[...document.querySelectorAll('label')].find(l=>l.textContent==='Neither').querySelector('input').click();true")
        try await wait { try await yes(table, "[...document.querySelectorAll('label')].some(l=>l.textContent.includes('Calculate Fisher')&&l.querySelector('input[type=checkbox]'))") }
        try await wait { try await yes(table, "!document.querySelector('.analysis-form button[type=submit]').disabled") }
        try check(table.pendingResult == nil, "changing study type only updates the form; it does not run the calculation")
        _ = try await js(table, "[...document.querySelectorAll('label')].find(l=>l.textContent.includes('Calculate Fisher')).querySelector('input').click();true")
        try await Task.sleep(nanoseconds:600_000_000)
        try await wait { try await yes(table, "!document.querySelector('.analysis-form button[type=submit]').disabled") }
        _ = try await js(table, "document.querySelector('.analysis-form button[type=submit]').click();true")
        try await wait { table.pendingResult != nil }
        try check(report.reportEntries?.count == 1, "instant results stay in the input window until Add to report")
        let completed = try await js(table, "window.formState") as! [String:Any]
        let values = completed["values"] as! [String:Any]
        try check(abs((values["chi"] as! Double)-8.64)<1e-10, "highlighted four cells reach chi-square in their original row/column orientation")
        let answers = completed["history"] as! [[String:Any]]
        try check(answers.first { $0["name"] as? String == "doFisher" }?["value"] as? Bool == true, "Fisher checkbox is honoured by the calculation")
        v.keepResult(table, id:table.pendingResult!.id); try await wait { report.reportEntries?.count == 2 }
        try check(report.reportEntries?.count == 2, "results append to the same active report")

        try await select(0)
        let weighted = try open("WeightedUnivariateSummary")
        try await wait { try await yes(weighted, "!!document.querySelector('.column-chooser')&&document.body.innerText.includes('Select weights')") }
        try check(try await yes(weighted, "document.querySelectorAll('.column-chooser input:checked').length===0"), "the weights prompt asks for its own column instead of reusing the measurement selection")
        v.remove(weighted)
        try await select(2)
        let wide = try open("TUnpaired")
        try await wait { try await yes(wide, "!!document.querySelector('.column-chooser')") }
        try check(try await yes(wide, "document.querySelectorAll('.column-chooser input:checked').length===0"), "a wider selection is not silently cropped for other analyses")
        v.remove(wide)
    }
}
