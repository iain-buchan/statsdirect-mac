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
        let new=file.items.first { $0.title=="New Script" }!
        try check(NSApp.sendAction(new.action!,to:new.target,from:new),"File → New Script opens a script tab")
        let first=v.active!, pane=first.rPane!
        try check(first.title=="R Script 1" && pane.editor.string.isEmpty && !pane.hasUnsavedChanges,"blank script opens without unsaved changes")
        for title in ["Run","Stop / Reset","Save script…","Clear output","Output folder","Open in R"] {
            try check(buttons(pane.view).contains { $0.title==title && !$0.isHidden },"script window exposes \(title)")
        }
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType:Data]()) { result, type in result[type] = item.data(forType:type) }
        } ?? []
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(originalClipboard.map { data in
                let item=NSPasteboardItem(); for (type,value) in data { item.setData(value,forType:type) }; return item
            })
        }
        func edit(_ command: String) throws {
            guard let button=buttons(pane.view).first(where:{$0.identifier?.rawValue==command}) else { throw CocoaError(.validationMissingMandatoryProperty) }
            pane.view.toolbar?.refresh()
            button.performClick(nil)
        }
        pane.editor.string="before <- c(1, 2)\nafter <- c(3, 4)"
        pane.editor.setSelectedRange(NSRange(location:0,length:6)); v.window.makeFirstResponder(pane.editor)
        try edit("copy"); try check(pasteboard.string(forType:.string)=="before","Script Copy keeps the editor selection")
        try edit("cut"); try check(pane.editor.string.hasPrefix(" <-"),"Script Cut removes selected code")
        try edit("undo"); try check(pane.editor.string.hasPrefix("before"),"Script toolbar Undo restores cut code")
        try edit("redo"); try check(pane.editor.string.hasPrefix(" <-"),"Script toolbar Redo repeats the cut")
        try edit("paste"); try check(pane.editor.string.hasPrefix("before <-"),"Script Paste inserts at the retained selection")
        pane.console.string="RESULT 42"; pane.console.setSelectedRange(NSRange(location:0,length:9)); v.window.makeFirstResponder(pane.console)
        try edit("copy"); try check(pasteboard.string(forType:.string)=="RESULT 42","Script Copy also copies selected output")
        let beforeOutputEdit=pane.editor.string
        try edit("cut"); try edit("paste")
        try check(pane.editor.string==beforeOutputEdit && pane.console.string=="RESULT 42","Cut and Paste on read-only output cannot change an unrelated script selection")
        let moreButton=buttons(pane.view).first { $0.title=="More commands" }!
        v.window.makeFirstResponder(moreButton)
        try edit("copy")
        try check(pasteboard.string(forType:.string)=="RESULT 42","Copy retains the output target when keyboard focus moves to More")
        v.window.makeFirstResponder(moreButton)
        try edit("cut"); try edit("paste")
        try check(pane.editor.string==beforeOutputEdit,"More cannot cut a stale script selection while output is selected")
        pane.editor.undoManager?.removeAllActions()
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
        let source="writeLines('ran', \(String(decoding:try JSONSerialization.data(withJSONObject:marker.path,options:[.fragmentsAllowed,.withoutEscapingSlashes]),as:UTF8.self))); stopifnot(!exists('x')); cat('SECOND_SCRIPT\\n')"
        try source.write(to:url,atomically:true,encoding:.utf8)
        v.openRScriptURL(url)
        let second=v.active!, other=second.rPane!
        try check(second.title=="R Script 2: Example.R" && other.editor.string==source && !other.hasUnsavedChanges,"R file opens in a separate tab with its exact text")
        try check(!other.isRunning && !FileManager.default.fileExists(atPath:marker.path) && other.outputFolder == nil && other.console.string.isEmpty,"opening a script does not execute it or start R")
        let save=file.items.first { $0.action == #selector(Viewer.saveDocument) }!
        try check(v.validateMenuItem(save) && save.title=="Save R Script…","File Save targets the active R script")
        let copy=try other.writeExternalScript(), firstCopy=try pane.writeExternalScript()
        let copyText=try String(contentsOf:copy,encoding:.utf8)
        try check(copyText==source && copy.lastPathComponent=="Example.R" && copy.deletingLastPathComponent() != firstCopy.deletingLastPathComponent(),"session copies preserve exact code in independent output folders")
        other.editor.insertText("# Edited\n",replacementRange:NSRange(location:0,length:0))
        try check(other.hasUnsavedChanges,"editing an opened script marks it unsaved")
        _=try other.writeExternalScript()
        let original=try String(contentsOf:url,encoding:.utf8)
        try check(original==source && other.hasUnsavedChanges,"external copy never overwrites the opened file or clears unsaved edits")
        other.runScript()
        try await wait { !other.isRunning && other.console.string.contains("SECOND_SCRIPT") }
        try check(FileManager.default.fileExists(atPath:marker.path) && !other.console.string.contains("Error:"),"explicit Run works in an independent R session")
        // Passive opening can make an external copy before the first R process.
        // Reset must retain the running session's folder, then a restart isolates it.
        let runningCopy=try other.writeExternalScript()
        other.stopSession()
        let resetCopy=try other.writeExternalScript()
        try check(resetCopy==runningCopy && FileManager.default.fileExists(atPath:copy.path),"Reset preserves the current output folder and the earlier external copy")
        other.editor.string="stopifnot(!exists('x')); cat('RESET_READY\\n')"; other.runScript()
        try await wait { !other.isRunning && other.console.string.contains("RESET_READY") }
        let restartedCopy=try other.writeExternalScript()
        try check(restartedCopy.deletingLastPathComponent() != resetCopy.deletingLastPathComponent(),"a restarted process uses a fresh folder, isolated from a stopping run")
        let controls=buttons(other.view).filter { !$0.isHiddenOrHasHiddenAncestor }
        v.window.setContentSize(NSSize(width:850,height:520)); v.window.contentView!.layoutSubtreeIfNeeded()
        try check(controls.allSatisfy { other.view.bounds.contains(other.view.convert($0.bounds,from:$0)) },"R controls fit the minimum main window")
        v.helpLibrary(); v.window.contentView!.layoutSubtreeIfNeeded()
        v.workspaceSplit.setPosition(350,ofDividerAt:0); v.window.contentView!.layoutSubtreeIfNeeded()
        let toolbar=other.view.toolbar!, overflow=toolbar.overflowMenu()
        try check(buttons(toolbar).first { $0.title=="More commands" }?.imagePosition == .imageOnly,"More uses its outline icon without clipped label text")
        try check(toolbar.frame.width < 400 && overflow.items.contains { $0.title == "Open in R" && $0.isEnabled },"Open in R is reachable in More with Help docked in a narrow window")
        try check(buttons(toolbar).filter { !$0.isHiddenOrHasHiddenAncestor }.allSatisfy { toolbar.bounds.contains(toolbar.convert($0.bounds,from:$0)) },"narrow script toolbar has one unclipped row")
        let commandOrder=toolbar.items.map { $0.button.identifier?.rawValue ?? $0.button.title }
        try check(Array(commandOrder.prefix(7)) == ["Save script…","undo","redo","cut","copy","paste","Find"],"script command order matches reports and worksheets")
        other.showFind()
        try await wait { other.editor.enclosingScrollView?.isFindBarVisible == true }
        try check(true,"Script Find opens the native Find bar")
        if let bitmap=other.view.bitmapImageRepForCachingDisplay(in:other.view.bounds) {
            other.view.cacheDisplay(in:other.view.bounds,to:bitmap)
            let pictures=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/unified-toolbar-output")
            try FileManager.default.createDirectory(at:pictures,withIntermediateDirectories:true)   // the toolbar suite makes this folder when it runs first; this suite must not depend on that
            try bitmap.representation(using:.png,properties:[:])?.write(to:pictures.appendingPathComponent("script-narrow.png"))
        }
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
        func scriptForRecord(_ record: String) async throws -> [String:Any] {
            let frames=try await v.recordFrames(record)
            return try await withCheckedThrowingContinuation { c in
                v.analysisRequest(["record":record,"frames":frames,"title":NSNull()],entry:"statsdirect_r_script") { c.resume(with:$0) }
            }
        }
        let expected=try await scriptForRecord(entry.record!)
        let expectedScript=expected["text"] as! String
        try check(entry.recipe && expectedScript.contains("before <-") && expectedScript.contains("confidence <- 0.95"),"record-backed R handoff retains the actual data and confidence level")
        try await wait {
            guard !report.web.isLoading else { return false }
            return (try? await report.web.evaluateJavaScript("!!document.querySelector('[data-command=continueInR]:not(:disabled)')")) as? Bool==true
        }
        _=try await report.web.evaluateJavaScript("document.querySelector('[data-command=continueInR]').click()")
        try await wait { v.active?.rPane != nil }
        let continued=v.active!, r=continued.rPane!
        try await wait { !r.isRunning && r.console.string.contains("Paired t-test") }
        try check(r.editor.string==expectedScript && r.console.textStorage!.containsAttachments,"Continue in R opens and runs the exact report script, including its agreement chart")
        // Exercise the real R startup lifecycle, not just the exported file.
        // Quotes, spaces and Unicode paths must survive the startup profile.
        let launchFolder=folder.appendingPathComponent("External R ' café")
        let launch=try RExternalSession(script:try r.writeExternalScript(),directory:launchFolder)
        let config=launch.configuration()
        try check(config.createsNewApplicationInstance && config.environment["R_PROFILE_USER"]==launch.profile.path,"Open in R isolates existing R sessions and sets its own startup profile")
        let started=Process(), outputFile=folder.appendingPathComponent("external-output.txt")
        FileManager.default.createFile(atPath:outputFile.path,contents:nil)
        let handle=try FileHandle(forWritingTo:outputFile); defer {try? handle.close()}
        started.executableURL=URL(fileURLWithPath:RRuntime.executable()!)
        started.arguments=["--no-save","--no-restore","-e","stopifnot(exists('before'), identical(Sys.getenv('R_PROFILE_USER'), '')); .First(); cat('EXTERNAL_READY\\n')"]
        started.environment=ProcessInfo.processInfo.environment.merging(["R_PROFILE_USER":launch.profile.path]) {_, new in new}
        started.currentDirectoryURL=folder; started.standardOutput=handle; started.standardError=handle
        try started.run(); try await wait {!started.isRunning}
        let externalOutput=try String(contentsOf:outputFile,encoding:.utf8)
        if started.terminationStatus != 0 || !externalOutput.contains("EXTERNAL_READY") {print(externalOutput);fflush(stdout)}
        try check(started.terminationStatus==0 && externalOutput.contains("EXTERNAL_READY") && externalOutput.components(separatedBy:"StatsDirect: running ").count==2 && externalOutput.contains("Paired t-test"),"external R startup runs the analysis once and retains its variables")
        try check(FileManager.default.fileExists(atPath:launchFolder.appendingPathComponent("Rplots.pdf").path),"external R startup produces the agreement chart")
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
        try check(table.pendingResult != nil && !table.pendingResult!.body.contains("<details>") && table.pendingResult!.record != nil,"screen-data results also omit the input expander and retain their R handoff")
        var unlisted=try JSONSerialization.jsonObject(with:Data(entry.record!.utf8)) as! [String:Any]
        unlisted["operation"]="UnmappedMethod"
        let starter=try await scriptForRecord(String(decoding:try JSONSerialization.data(withJSONObject:unlisted),as:UTF8.self))
        try check(starter["hasRecipe"] as? Bool==false && (starter["text"] as? String ?? "").contains("# Add your analysis here."),"methods without an R recipe still provide an editable data/settings script")
        let missing=RPane(script:"cat('keep me')",saved:true,resources:v.root,executable:{nil})
        defer { missing.shutdown() }
        try check(buttons(missing.view).contains { $0.title=="Install R…" && !$0.isHidden } && missing.editor.string=="cat('keep me')","missing R keeps the script and offers setup inside its window")
        v.remove(first); v.remove(second); v.remove(continued)
        v.newRTab()
        try check(v.active!.title=="R Script 1","script numbering reuses closed numbers")
        for doc in v.documents { doc.rPane?.shutdown() }
    }
}
