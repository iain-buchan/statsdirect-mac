import Cocoa
import WebKit
import PDFKit

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
                catch {
                    for grid in viewer.documents where grid.kind == "grid" {
                        print("GRID:", (try? await js(grid,"JSON.stringify({source:window.statsDirectGrid?.analysisSource(),gesture:window.analysisGesture,focus:document.hasFocus(),visibility:document.visibilityState})")) as Any)
                    }
                    if let doc=viewer.active {
                        print("SOURCE SNAPSHOT:",doc.operationSourceSnapshot as Any)
                        print("STATE:", (try? await js(doc,"JSON.stringify({state:window.formState,html:document.body.innerText})")) as Any)
                    }
                    print("FAIL: \(error)"); fflush(stdout); exit(1)
                }
                viewer.closeApproved = true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now()+180) { print("FAIL: analysis workflows timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.window.setContentSize(NSSize(width: 1180, height: 850))
        v.window.contentView?.layoutSubtreeIfNeeded()
        v.workspaceSplit.adjustSubviews(); v.documentSplit.adjustSubviews()
        let grid = v.newDocument(kind: "grid", title: "Selection fixture", url: v.root.appendingPathComponent("Grid/index.html"))
        try await wait { try await yes(grid, "!!window.statsDirectGrid && !!document.querySelector('canvas')") }
        _ = try await grid.web.callAsyncJavaScript("""
        await statsDirectGrid.loadWorkbook({name:'Selected measurements',sheets:[{name:'Data',rows:100,columns:6,headerRow:true,cells:[
          {col:0,row:0,text:'Before',kind:'text'},{col:1,row:0,text:'After',kind:'text'},
          ...[12,3,4,7,8].map((n,i)=>({col:0,row:i+1,text:String(n),kind:'number'})),
          ...[8,17,9,11,13].map((n,i)=>({col:1,row:i+1,text:String(n),kind:'number'})),
          {col:5,row:99,text:'999',kind:'number'}]}]});return true;
        """, arguments: [:], in: nil, contentWorld: .page)
        // loadWorkbook schedules React updates; wait for the fixture's metadata,
        // then exercise one actual gesture, never a direct selection API or retry.
        try await wait { try await yes(grid,"statsDirectGrid.analysisSource().name==='Selected measurements / Data'&&statsDirectGrid.analysisSource().columns.length===6") }
        var expectedColumns=[Int](),expectedRange:[String:Int]?
        func matches(_ source:[String:Any]) -> Bool {
            source["selection"] as? [Int] == expectedColumns && source["range"] as? [String:Int] == expectedRange
        }
        func select(_ last: Int, rectangle: Bool = false) async throws {
            expectedColumns=Array(0...last); expectedRange=rectangle ? ["first":2,"last":3] : nil
            v.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
            v.tabs.selectTabViewItem(grid.item)
            v.window.contentView!.layoutSubtreeIfNeeded()
            v.window.makeFirstResponder(grid.web)
            try await wait {
                guard v.window.isKeyWindow && NSApp.isActive else { return false }
                return try await yes(grid,"document.hasFocus()&&document.querySelector('canvas').getBoundingClientRect().width>0")
            }
            _ = try await grid.web.callAsyncJavaScript("""
            if(!window.analysisGestureInstalled){
              for(const type of ['focus','blur'])window.addEventListener(type,e=>window.analysisGesture?.events.push({type,time:performance.now(),trusted:e.isTrusted}));
              window.analysisGestureInstalled=true;
            }
            window.analysisGesture={expected:Array.from({length:last+1},(_,i)=>i),rectangle,events:[]};
            // Match the grid gesture suite: timers alone do not establish a
            // rendered frame. Bound the frame wait so a suspended view fails.
            const settle=async()=>{
              await new Promise(r=>setTimeout(r,65));let timer;
              try{await Promise.race([new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Worksheet did not render before the gesture')),3000);})]);}
              finally{clearTimeout(timer);}
            };
            await settle();
            const b=document.querySelector('canvas').getBoundingClientRect(),x=c=>b.x+48+c*178+89;
            const y=r=>b.y+(r<0?18:36+r*29+14),startRow=rectangle?1:-1,endRow=rectangle?2:-1;
            window.analysisGesture.bounds=b.toJSON();
            const send=(type,c,r,buttons,shiftKey=false)=>{
              const target=document.elementFromPoint(x(c),y(r));if(!target)throw new Error('Worksheet gesture has no hit target');
              window.analysisGesture.events.push({type,column:c,row:r,buttons,target:target.tagName,selection:statsDirectGrid.analysisSource().selection});
              target.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,clientX:x(c),clientY:y(r),button:0,buttons,shiftKey}));
            };
            send('mousemove',0,startRow,0);send('mousedown',0,startRow,1);await new Promise(r=>setTimeout(r,65));
            if(rectangle){send('mouseup',0,startRow,0);send('mousedown',last,endRow,1,true);await new Promise(r=>setTimeout(r,65));send('mouseup',last,endRow,0,true);}
            else{for(let i=1;i<=8;i++){send('mousemove',last*i/8,endRow,1);await new Promise(r=>setTimeout(r,30));}send('mouseup',last,endRow,0);}
            // Frame readiness is required before the gesture. Afterwards the
            // native caller waits for actual selection state; WebKit can pause
            // frame callbacks when the user returns to another app after mouse-up.
            window.analysisGesture.after=statsDirectGrid.analysisSource();return true;
            """, arguments: ["last":last, "rectangle":rectangle], in:nil, contentWorld:.page)
            try await wait { matches(try await js(grid,"statsDirectGrid.analysisSource()") as? [String:Any] ?? [:]) }
            try check(matches(try await js(grid,"statsDirectGrid.analysisSource()") as? [String:Any] ?? [:]),"one worksheet gesture selects \(expectedColumns), range \(expectedRange as Any), before analysis")
        }
        func open(_ name: String) async throws -> Document {
            let source=try await js(grid,"statsDirectGrid.analysisSource()") as? [String:Any] ?? [:]
            print("SELECTION before \(name):",source["selection"] as Any,"range:",source["range"] as Any);fflush(stdout)
            try check(matches(source),"\(name) dispatch retains the exact worksheet selection")
            v.analysisSourceID = grid.id; let menu = item(NSApp.mainMenu!, name)!
            try check(NSApp.sendAction(menu.action!, to:menu.target, from:menu), "\(name) starts from its analysis menu")
            let doc=v.active!
            try await wait { doc.operationSourceSnapshot != nil }
            try check(matches(doc.operationSourceSnapshot!),"\(name) receives the exact selected worksheet snapshot")
            return doc
        }
        try await select(1)
        let unpaired = try await open("TUnpaired")
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
        let table = try await open("Chi2by2")
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
        let weighted = try await open("WeightedUnivariateSummary")
        try await wait { try await yes(weighted, "!!document.querySelector('.column-chooser')&&document.body.innerText.includes('Select weights')") }
        try check(try await yes(weighted, "document.querySelectorAll('.column-chooser input:checked').length===0"), "the weights prompt asks for its own column instead of reusing the measurement selection")
        v.remove(weighted)
        try await select(2)
        let wide = try await open("TUnpaired")
        try await wait { try await yes(wide, "!!document.querySelector('.column-chooser')") }
        try check(try await yes(wide, "document.querySelectorAll('.column-chooser input:checked').length===0"), "a wider selection is not silently cropped for other analyses")
        v.remove(wide)

        try await select(1)
        let box = try await open("BoxWhiskerPlot")
        try await wait { try await yes(box, "!!document.querySelector('select[name=method]')") }
        try check(try await yes(box, "document.querySelector('select[name=method]').options.length===6&&document.querySelector('input[name=confidence]').value==='95'&&document.querySelector('input[name=confidence]').disabled&&!document.querySelector('.column-chooser')"), "box plot uses the selection automatically and offers six methods with the saved 95% default")
        if let path = ProcessInfo.processInfo.environment["STATSDIRECT_TEST_SCREENSHOT"] {
            let image = try await box.web.takeSnapshot(configuration:nil)
            if let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff), let png=bitmap.representation(using:.png,properties:[:]) { try png.write(to:URL(fileURLWithPath:path)) }
        }
        _ = try await js(box, """
        window.chooseBox=(name,value)=>{const e=document.querySelector(`[name=${name}]`);Object.getOwnPropertyDescriptor(e.tagName==='SELECT'?HTMLSelectElement.prototype:HTMLInputElement.prototype,'value').set.call(e,value);e.dispatchEvent(new Event(e.tagName==='SELECT'?'change':'input',{bubbles:true}));};
        chooseBox('method','4');true
        """)
        try await wait { try await yes(box, "document.querySelector('[name=innerFence]').disabled&&document.querySelector('[name=outerFence]').disabled") }
        _ = try await js(box, "chooseBox('method','3');true")
        try await wait { try await yes(box, "!document.querySelector('[name=confidence]').disabled&&!document.querySelector('[name=innerFence]').disabled") }
        _ = try await js(box, "chooseBox('confidence','99');chooseBox('title','Selected measurements');document.querySelector('[name=automaticAxisTitle]').click();true")
        try await wait { try await yes(box, "!document.querySelector('[name=x]').disabled") }
        _ = try await js(box, "chooseBox('x','Value (units)');chooseBox('orientation','Vertical');document.querySelector('[name=markMeanAndMedian]').click();document.querySelectorAll('form details').forEach(e=>e.open=true);chooseBox('series0','First measurement');chooseBox('minimum','20');chooseBox('maximum','0');document.querySelector('form button[type=submit]').click();true")
        try await wait { try await yes(box, "document.querySelector('[role=alert]')?.textContent.includes('minimum smaller')===true") }
        try check(try await yes(box, "document.querySelector('[name=title]').value==='Selected measurements'&&document.querySelector('[name=method]').value==='3'&&document.querySelector('[name=confidence]').value==='99'&&document.querySelector('[name=markMeanAndMedian]').checked"), "invalid box plot axis limits retain the chosen method, confidence and labels")
        _ = try await js(box, "document.querySelectorAll('form details').forEach(e=>e.open=true);chooseBox('minimum','0');chooseBox('maximum','20');document.querySelector('form button[type=submit]').click();true")
        try await wait { box.completedJobID != nil }
        let boxReport = report.reportEntries!.last!
        try check(boxReport.body.contains("<svg") && boxReport.body.contains("Selected measurements") && boxReport.body.contains("Value (units)") && boxReport.body.contains("First measurement"), "box plot options draw one SVG in the active report with the chosen chart, axis and series labels")
        v.continueResultInR(report, id:boxReport.id)
        try await wait { v.active?.rPane != nil }
        let script = v.active!, r = script.rPane!
        try await wait { !r.isRunning && r.console.textStorage!.containsAttachments }
        let plots = try FileManager.default.contentsOfDirectory(at: r.outputFolder!, includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("plots-") }
        try check(plots.count == 1 && plots[0].pathExtension == "pdf" && PDFDocument(url:plots[0])?.pageCount == 1, "Continue in R displays exactly one PDF page for the chosen box plot")
        try check(r.editor.string.contains("box_settings <- list(") && r.editor.string.contains("Selected measurements") && r.editor.string.contains("First measurement"), "box plot script retains the recorded choices and edited labels")
        v.remove(script)

        try await select(1)
        let histogram = try await open("HistogramPlot")
        try await wait { try await yes(histogram, "!!document.querySelector('[name=title0]')&&!!document.querySelector('[name=title1]')") }
        try check(try await yes(histogram, "document.querySelector('[name=title0]').value!==document.querySelector('[name=title1]').value&&!document.querySelector('.column-chooser')"), "histogram uses the two selected columns and presents their independent chart labels")
        _ = try await js(histogram, """
        document.querySelectorAll('form details').forEach(e=>e.open=true);
        window.setHistogram=(name,value)=>{const e=document.querySelector(`[name=${name}]`);Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,value);e.dispatchEvent(new Event('input',{bubbles:true}));};
        setHistogram('title0','First selected histogram');setHistogram('title1','Second selected histogram');setHistogram('x0','First measurement');setHistogram('x1','Second measurement');setHistogram('bins','1');document.querySelector('form button[type=submit]').click();true
        """)
        try await wait { try await yes(histogram, "document.querySelector('[role=alert]')?.textContent.includes('automatic bins')===true") }
        try check(try await yes(histogram, "document.querySelector('[name=title0]').value==='First selected histogram'&&document.querySelector('[name=title1]').value==='Second selected histogram'"), "histogram validation retains the labels for both series")
        _ = try await js(histogram, "setHistogram('bins','4');document.querySelector('form button[type=submit]').click();true")
        try await wait { histogram.completedJobID != nil }
        let histogramReport = report.reportEntries!.last!
        try check(["First selected histogram", "Second selected histogram", "First measurement", "Second measurement"].allSatisfy { histogramReport.body.contains($0) }, "the report draws both histograms with their edited chart and axis labels")
        v.continueResultInR(report, id:histogramReport.id)
        try await wait { v.active?.rPane != nil }
        let histogramScript = v.active!, hr = histogramScript.rPane!
        try await wait { !hr.isRunning && hr.console.textStorage!.containsAttachments }
        let histogramPDFs = try FileManager.default.contentsOfDirectory(at: hr.outputFolder!, includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("plots-") && $0.pathExtension == "pdf" }
        try check(histogramPDFs.count == 1 && PDFDocument(url:histogramPDFs[0])?.pageCount == 1, "Continue in R shows the two requested histogram panels on one PDF page")
        try check(hr.editor.string.contains("First selected histogram") && hr.editor.string.contains("Second selected histogram"), "histogram replay retains both selected titles")
        v.remove(histogramScript)
    }
}
