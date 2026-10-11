import Cocoa
import WebKit

// A tour of the app for a look at it without a screen recording: the real window, the example workbook opened, a paired t test run
// through its form, the report with the result and its chart, Continue in R, the help pane and the calculator, each saved as a PNG of
// the window captured from inside the app (an app may always picture its own windows). Scripts/app-tour.sh builds and runs it.
@main struct AppTour {
    @MainActor static func main() {
        guard CommandLine.arguments.count>1 else { print("Run this with Scripts/app-tour.sh and an output directory."); exit(2) }
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        let viewer=Viewer(); app.delegate=viewer
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await tour(viewer, output:URL(fileURLWithPath:CommandLine.arguments[1])); print("PASS: app tour");fflush(stdout) }
                catch { print("FAIL:",error.localizedDescription);fflush(stdout);exit(1) }
                viewer.closeApproved=true; app.terminate(nil)
            }
        }
        app.run()
    }
    @MainActor static func tour(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func fail(_ message:String) -> NSError { NSError(domain:"AppTour",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        func wait(_ what:String, timeout:TimeInterval=60, _ condition:() async throws -> Bool) async throws {
            let deadline=Date().addingTimeInterval(timeout)
            while Date()<deadline { if try await condition() { return }; try await Task.sleep(nanoseconds:50_000_000) }
            throw fail("timed out waiting for \(what) · status: \(v.status.stringValue)")
        }
        func js(_ doc:Document,_ script:String) async throws -> [String:Any] { try await v.learningJavaScript(doc,script) }
        func settle(_ seconds:Double) async throws { try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)) }
        // The window as it is on screen, pictured by the app itself (its own windows need no screen recording permission), at the
        // display's scale; the menu popped up for the R menu picture is a window of the app's too.
        func capture(_ name:String, allWindows:Bool=false) throws {
            v.window.displayIfNeeded()
            let id=CGWindowID(v.window.windowNumber)
            let image: CGImage?
            if allWindows {
                let bounds=CGRect(x:v.window.frame.minX, y:NSScreen.screens[0].frame.height-v.window.frame.maxY, width:v.window.frame.width, height:v.window.frame.height)
                image=CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
            } else {
                image=CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
            }
            guard let image, image.width>10 else { throw fail("the window could not be pictured for \(name)") }
            let rep=NSBitmapImageRep(cgImage:image)
            guard let png=rep.representation(using:.png,properties:[:]) else { throw fail("no PNG for \(name)") }
            try png.write(to:output.appendingPathComponent(name+".png"))
            print("captured \(name): \(image.width) by \(image.height)");fflush(stdout)
        }
        v.window.setFrame(NSRect(x:40,y:60,width:1380,height:900),display:true)
        NSApp.activate(ignoringOtherApps:true)
        // 1. The example workbook
        let example=v.root.appendingPathComponent("Examples/test.xlsx")
        v.openExcelURL(example)
        try await wait("the example workbook") { v.documents.contains{$0.kind=="grid" && $0.workbookName=="test.xlsx" && $0.pendingWorkbook==nil && $0.workbookSourceURL != nil} }
        let grid=v.documents.last{$0.kind=="grid" && $0.workbookName=="test.xlsx"}!
        try await wait("the grid") { (try? await js(grid,"({ok:!!window.statsDirectGrid&&statsDirectGrid.tutorInfo().sheets[0].name==='Parametric'})"))?["ok"] as? Bool == true }
        v.tabs.selectTabViewItem(grid.item); try await settle(1.5)
        try capture("1-worksheet")
        // 2. The paired t test form, its column chooser showing, then answered: both PEFR columns, the agreement analysis asked for
        let form=v.newDocument(kind:"operation",title:"Paired t test",url:v.root.appendingPathComponent("Grid/operation.html"))
        form.operationSourceID=grid.id
        try await wait("the form") { form.operationReady && form.operationSourceSnapshot != nil }
        _=try await js(form,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.tourState=s;update(s);};return {ok:true};})()")
        form.operationName="TPaired"; v.startOperation(form)
        try await wait("the column chooser") { (try? await js(form,"({ok:document.querySelectorAll('.column-chooser input').length>0})"))?["ok"] as? Bool == true }
        _=try await js(form,"(()=>{const inputs=document.querySelectorAll('.column-chooser input');for(const i of [0,1]){if(!inputs[i].checked)inputs[i].click();}return {ok:true};})()")
        v.tabs.selectTabViewItem(form.item); try await settle(1.0)
        try capture("2-analysis-form")
        var answered=Set<Int>(); let deadline=Date().addingTimeInterval(90)
        while form.completedJobID==nil && Date()<deadline {
            let state=(try? await js(form,"({state:window.tourState?.state??'',kind:window.tourState?.prompt?.kind??'',token:window.tourState?.token??-1,error:window.tourState?.prompt?.error??'',failure:window.tourState?.error??''})")) ?? [:]
            if !(state["failure"] as? String ?? "").isEmpty || state["state"] as? String=="failed" { throw fail("the paired t test failed: \(state["failure"] ?? "")") }
            if state["state"] as? String=="input", let token=state["token"] as? Int, token>=0, !answered.contains(token) {
                let kind=state["kind"] as? String ?? ""
                if kind=="boolean" { _=try await js(form,"({ok:(document.querySelectorAll('.yesno input')[0].click(),true)})") }   // Yes to the agreement analysis
                _=try await js(form,"({ok:(document.querySelector('form').requestSubmit(),true)})")
                answered.insert(token)
            }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        guard form.completedJobID != nil else { throw fail("the paired t test did not complete · \(v.status.stringValue)") }
        if let pending=form.pendingResult { v.keepResult(form,id:pending.id) }
        // 3. The report with the result and its agreement plot
        guard let report=v.documents.first(where:{$0.kind=="report"}) else { throw fail("no report document") }
        try await wait("the result in the report") { (report.reportEntries?.count ?? 0)>=1 }
        let entry=report.reportEntries!.last!
        v.tabs.selectTabViewItem(report.item)
        for _ in 0..<100 where report.web.isLoading { try await Task.sleep(nanoseconds:100_000_000) }
        try await wait("the rendered result") { (try? await js(report,"({ok:!!document.querySelector('.report-entry[data-result-id=\"\(entry.id)\"] svg')})"))?["ok"] as? Bool == true }
        try await settle(1.5)
        try capture("3-report")
        // 4. Continue in R: the R pane with the script, run
        let before=v.documents.filter{$0.kind=="r"}.count
        v.continueResultInR(report,id:entry.id)
        try await wait("the R script") { v.documents.filter{$0.kind=="r"}.count>before && v.status.stringValue.hasPrefix("R script") }
        let pane=v.documents.last{$0.kind=="r"}!
        v.tabs.selectTabViewItem(pane.item)
        try await wait("R's output", timeout:90) { (pane.rPane?.console.string.contains("t = ") ?? false) || (pane.rPane?.console.string.contains("Paired t-test") ?? false) }
        try await settle(1.5)
        try capture("4-continue-in-r")
        // 5. The R menu, popped up over the window
        if let rMenu=NSApp.mainMenu?.items.first(where:{$0.submenu?.title=="R"})?.submenu {
            let timer=Timer(timeInterval:0.6,repeats:false) { _ in
                try? capture("5-r-menu", allWindows:true)
                rMenu.cancelTracking()
            }
            RunLoop.main.add(timer,forMode:.eventTracking); RunLoop.main.add(timer,forMode:.common)
            rMenu.popUp(positioning:nil,at:NSPoint(x:40,y:v.window.contentView!.bounds.height-10),in:v.window.contentView)
        }
        // 6. The help pane docked beside the report, on the method's topic, and the calculator
        v.tabs.selectTabViewItem(report.item)
        v.currentMethodHelp()
        try await settle(2.5)
        try capture("6-help-pane")
        v.showCalculator()
        try await settle(1.5)
        try capture("7-calculator")
        // 8. The learning window (the tutor's lessons), if it opens without a sign-in
        v.openLearning()
        try await settle(3.0)
        if let learn=v.documents.last(where:{$0.kind=="learn"}) { v.tabs.selectTabViewItem(learn.item); try await settle(1.5); try capture("8-learning") }
    }
}
