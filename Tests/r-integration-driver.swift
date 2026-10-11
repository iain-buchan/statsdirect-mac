import Cocoa
import WebKit

@main struct RIntegrationTests {
    @MainActor static func check(_ ok: Bool, _ message: String) throws {
        guard ok else { throw NSError(domain:"RIntegrationTests",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        print("PASS: " + message); fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let deadline=Date().addingTimeInterval(30)
        while Date()<deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw NSError(domain:"RIntegrationTests",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out waiting for UI or R"])
    }
    @MainActor static func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        let viewer=Viewer(); app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: R integration checks completed"); fflush(stdout) }
                catch { print("FAIL: \(error.localizedDescription)"); fflush(stdout); exit(1) }
                viewer.closeApproved=true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+120) { print("FAIL: R integration timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        try check(!NSApp.mainMenu!.items.contains { $0.submenu?.title=="R" },"no separate R menu in the native menu bar")
        try check(!buttons(v.window.contentView!).contains { $0.identifier?.rawValue=="R" },"no separate R menu inside the window")
        let file=NSApp.mainMenu!.items.first { $0.submenu?.title=="File" }!.submenu!
        let new=file.items.first { $0.title=="New R Script" }!
        try check(NSApp.sendAction(new.action!,to:new.target,from:new),"File → New R Script opens a script tab")
        let first=v.active!, pane=first.rPane!
        try check(first.title=="R Script 1" && pane.editor.string.isEmpty && !pane.hasUnsavedChanges,"blank script opens without unsaved changes")
        for title in ["Run","Stop / Reset","Save script…","Clear output","Output folder","Open in R"] {
            try check(buttons(pane.view).contains { $0.title==title && !$0.isHidden },"script window exposes \(title)")
        }
        pane.editor.string="x <- 41; cat('FIRST_SCRIPT', x, '\\n'); plot(1:5)"
        v.window.makeFirstResponder(pane.editor)
        let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command],timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        try check(v.window.performKeyEquivalent(with:key),"⌘Return reaches Run without an R menu")
        try await wait { !pane.isRunning && pane.console.string.contains("FIRST_SCRIPT 41") }
        try check(pane.console.textStorage!.containsAttachments,"R chart appears inline with output")
        buttons(pane.view).first { $0.title=="Clear output" }!.performClick(nil)
        try check(pane.console.string.isEmpty,"Clear output removes text and charts")
        pane.editor.string="stopifnot(x==41); cat('VARIABLE_RETAINED\\n')"; pane.runScript()
        try await wait { !pane.isRunning && pane.console.string.contains("VARIABLE_RETAINED") }
        try check(true,"clearing output retains session variables")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-R-open-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("Example.R"), marker=folder.appendingPathComponent("executed.txt")
        let source="writeLines('ran', \(RScriptGenerator.string(marker.path))); stopifnot(!exists('x')); cat('SECOND_SCRIPT\\n')"
        try source.write(to:url,atomically:true,encoding:.utf8)
        v.openRScriptURL(url)
        let second=v.active!, other=second.rPane!
        try check(second.title=="R Script 2: Example.R" && other.editor.string==source && !other.hasUnsavedChanges,"R file opens in a separate tab with its exact text")
        try check(!other.isRunning && !FileManager.default.fileExists(atPath:marker.path),"opening a script does not execute it")
        let save=file.items.first { $0.action == #selector(Viewer.saveDocument) }!
        try check(v.validateMenuItem(save) && save.title=="Save R Script…","File Save targets the active R script")
        let copy=try other.writeExternalScript(), firstCopy=try pane.writeExternalScript()
        let copyText=try String(contentsOf:copy,encoding:.utf8)
        try check(copyText==source && copy.lastPathComponent=="Example.R" && copy.deletingLastPathComponent() != firstCopy.deletingLastPathComponent(),"Open in R saves exact code in independent session folders")
        other.editor.insertText("# Edited\n",replacementRange:NSRange(location:0,length:0))
        try check(other.hasUnsavedChanges,"editing an opened script marks it unsaved")
        _=try other.writeExternalScript()
        let original=try String(contentsOf:url,encoding:.utf8)
        try check(original==source && other.hasUnsavedChanges,"external copy never overwrites the opened file or clears unsaved edits")
        other.runScript()
        try await wait { !other.isRunning && other.console.string.contains("SECOND_SCRIPT") }
        try check(FileManager.default.fileExists(atPath:marker.path) && !other.console.string.contains("Error:"),"explicit Run works in an independent R session")
        other.stopSession()
        let resetCopy=try other.writeExternalScript()
        try check(resetCopy==copy,"Reset preserves access to this tab's output folder")
        other.editor.string="stopifnot(!exists('x')); cat('RESET_READY\\n')"; other.runScript()
        try await wait { !other.isRunning && other.console.string.contains("RESET_READY") }
        let restartedCopy=try other.writeExternalScript()
        try check(restartedCopy.deletingLastPathComponent() != resetCopy.deletingLastPathComponent(),"a restarted process uses a fresh folder, isolated from a stopping run")
        let controls=buttons(other.view).filter { !$0.isHidden }
        v.window.setContentSize(NSSize(width:850,height:520)); v.window.contentView!.layoutSubtreeIfNeeded()
        try check(controls.allSatisfy { other.view.bounds.contains(other.view.convert($0.bounds,from:$0)) },"R controls fit the minimum main window")
        v.helpLibrary(); v.window.contentView!.layoutSubtreeIfNeeded()
        v.workspaceSplit.setPosition(350,ofDividerAt:0); v.window.contentView!.layoutSubtreeIfNeeded()
        let external=buttons(other.view).first { $0.title=="Open in R" }!
        external.scrollToVisible(external.bounds)
        try check(!external.visibleRect.isEmpty && other.view.toolbar!.frame.width < 400,"script toolbar scrolls to its last control with Help docked in a narrow window")
        v.helpPane.hide()
        v.window.setContentSize(NSSize(width:1180,height:850))

        // Run an actual paired analysis, render the real operation report, then
        // activate the report's toolbar action through WebKit's message bridge.
        let columns:[[String:Any]]=[["title":"Before","values":[10,20,30,40]],["title":"After","values":[8,17,25,32]]]
        let output=try await TutorTools.run(operation:"TPaired",dataset:["columns":columns,"rowCount":4,"complete":true],agreement:true,studyType:nil,preferences:[:]) { body in
            try await withCheckedThrowingContinuation { c in v.analysisRequest(body,entry:"statsdirect_operation") { c.resume(with:$0) } }
        }
        let analysis=v.newDocument(kind:"operation",title:"Paired t test"); analysis.operationName="TPaired"
        v.finishOperationReport(analysis,output,frames:[],note:nil)
        let report=v.active!, entry=report.reportEntries![0]
        try check(!entry.body.contains("<details>") && !entry.body.contains("Inputs used for this report") && entry.body.contains("<svg"),"paired report retains its result and SVG without the input-code expander")
        try check(entry.rPlan!.script.contains("input_history <-") && entry.rPlan!.script.contains("data_frames <-"),"input history and worksheet values remain in the R handoff")
        try await wait {
            guard !report.web.isLoading else { return false }
            return (try? await report.web.evaluateJavaScript("!!document.querySelector('[data-command=continueInR]:not(:disabled)')")) as? Bool==true
        }
        _=try await report.web.evaluateJavaScript("document.querySelector('[data-command=continueInR]').click()")
        try await wait { v.active?.rPane != nil }
        let continued=v.active!, r=continued.rPane!
        try await wait { !r.isRunning && r.console.string.contains("Paired t-test") }
        try check(r.editor.string==entry.rPlan!.script && r.console.textStorage!.containsAttachments,"Continue in R opens and runs the exact report script, including its agreement chart")
        try check(continued.operationName=="TPaired" && v.methodHelpPath(continued)==v.analysisCatalog["TPaired"]?["help"] as? String,"continued script retains context help for its analysis")
        try check(!r.hasUnsavedChanges,"an unchanged generated script closes without a save prompt, like Windows")
        r.editor.insertText("# Note\n",replacementRange:NSRange(location:0,length:0))
        try check(r.hasUnsavedChanges,"edits to a generated script are protected")
        let html=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
        try check(!html.contains("Inputs used for this report") && !html.contains("<details") && html.contains("<svg"),"HTML export includes results and chart without hidden input code")

        // The dedicated screen-data report has its own rendering path.
        let input:[String:Any] = ["counts":[[10,9],[12,11],[8,15]],"doExact":false,"cco":0.95]
        let contingency:[String:Any] = try await withCheckedThrowingContinuation { c in v.analysisRequest(["action":"run","id":UUID().uuidString,"input":input]) { c.resume(with:$0) } }
        let table=v.newDocument(kind:"analysis",title:"Contingency table")
        v.showChiSquareReport(contingency,in:table)
        try check(table.pendingResult != nil && !table.pendingResult!.body.contains("<details>") && table.pendingResult!.rPlan != nil,"screen-data results also omit the input expander and retain their R handoff")
        let starter=try RScriptGenerator.generate(operation:"UnmappedMethod",title:"Unmapped",output:output,resources:v.root)
        try check(!starter.hasRecipe && starter.script.contains("data_frames <-"),"methods without an R recipe still provide the input data and settings")
        let missing=RPane(script:"cat('keep me')",saved:true,resources:v.root,executable:{nil})
        defer { missing.shutdown() }
        try check(buttons(missing.view).contains { $0.title=="Install R…" && !$0.isHidden } && missing.editor.string=="cat('keep me')","missing R keeps the script and offers setup inside its window")
        v.remove(first); v.remove(second); v.remove(continued)
        v.newRTab()
        try check(v.active!.title=="R Script 1","script numbering reuses closed numbers")
        for doc in v.documents { doc.rPane?.shutdown() }
    }
}
