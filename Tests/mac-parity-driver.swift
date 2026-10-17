import Cocoa
import WebKit
import PDFKit

@main struct MacParityTests {
    static func trace(_ text: String) {
        print("TRACE [\(ISO8601DateFormatter().string(from: Date()))]: \(text)"); fflush(stdout)
    }
    @MainActor static func scriptState(_ v: Viewer, _ doc: Document, _ phase: String) {
        let pane = doc.rPane!
        let operations = v.documents.filter { $0.scriptOwner === doc }.map {
            ["id": $0.id, "ready": String($0.operationReady), "job": $0.analysisJobID ?? "nil", "completed": $0.completedJobID ?? "nil"]
        }
        trace("\(phase): language=\(pane.language), running=\(pane.isRunning), state=\(pane.state.stringValue), file=\(pane.scriptFileName), active=\(v.active?.kind ?? "nil"), modal=\(NSApp.modalWindow?.title ?? "nil"), sheet=\(v.window.attachedSheet?.title ?? "nil"), operations=\(operations), source=\(pane.editor.string.debugDescription), console=\(pane.console.string.debugDescription)")
    }
    @MainActor static func check(_ value: Bool, _ text: String) throws {
        guard value else { throw NSError(domain:"MacParity",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
        print("PASS: " + text); fflush(stdout)
    }
    @MainActor static func wait(_ name: String = "native condition", _ condition: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(45)
        while Date() < end { if try await condition() { return }; try await Task.sleep(nanoseconds:80_000_000) }
        throw NSError(domain:"MacParity",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out: " + name])
    }
    @MainActor static func js(_ doc: Document, _ code: String) async throws -> Any? { try await doc.web.evaluateJavaScript(code) }
    @MainActor static func yes(_ doc: Document, _ code: String) async throws -> Bool { try await js(doc,code) as? Bool == true }
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        UserDefaults.standard.set(["use-default-ci":true,"default-ci":"95"],forKey:"analysisDefaults")
        let viewer=Viewer();app.delegate=viewer
        // Sample off the main thread so a blocked AppKit/WebKit call is visible.
        // The independent fatal watchdog below must still fire if sample stalls.
        let diagnostic = DispatchWorkItem {
            let folder = ProcessInfo.processInfo.environment["STATSDIRECT_PARITY_DIAGNOSTICS"] ?? FileManager.default.temporaryDirectory.path
            let path = URL(fileURLWithPath: folder).appendingPathComponent("sample-timeout.txt")
            trace("parity still running after 210 seconds; sampling PID \(ProcessInfo.processInfo.processIdentifier)")
            let sample = Process()
            sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            sample.arguments = [String(ProcessInfo.processInfo.processIdentifier), "2", "-file", path.path]
            do { try sample.run(); sample.waitUntilExit() }
            catch { trace("process sample failed: \(error)") }
            if let output = try? String(contentsOf: path, encoding: .utf8) { print(output); fflush(stdout) }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+210, execute:diagnostic)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { Task { @MainActor in
            do { try await run(viewer); print("PASS: Mac parity native suite"); fflush(stdout) }
            catch {
                print("FAIL: \(error)"); fflush(stdout)
                for doc in viewer.documents where doc.rPane != nil { scriptState(viewer, doc, "failure snapshot") }
                exit(1)
            }
            diagnostic.cancel()
            viewer.closeApproved=true;app.terminate(nil)
        } }
        DispatchQueue.global().asyncAfter(deadline:.now()+240) { print("FAIL: Mac parity timeout"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.window.setContentSize(NSSize(width:1180,height:850))
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("sd-parity-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let text=folder.appendingPathComponent("Notes.txt")
        try "Text\u{FEFF} report\n<svg onload='bad'> & café\nFirst\tSecond\n12\t34".write(to:text,atomically:true,encoding:.utf16)
        let report=try await v.importReport(text)
        try await wait { try await yes(report,"!!window.StatsDirectReportEditor") }
        let visible=try await js(report,"document.body.innerText") as? String ?? ""
        try check(visible.contains("<svg onload='bad'> & café") && visible.contains("12") && visible.contains("Text\u{FEFF} report"),"UTF-16 plain text report opens as literal editable content")
        try check(try await yes(report,"!document.querySelector('[onload]')"),"text report markup is never interpreted as active HTML")

        let tsv=folder.appendingPathComponent("Sample.tsv")
        try "before\tafter\n312\t300\n242\t201\n340\t232\n388\t312\n296\t220\n254\t256\n391\t328\n402\t330\n290\t231\n".write(to:tsv,atomically:true,encoding:.utf8)
        v.openDocumentURLs([tsv])
        try await wait { v.documents.contains { $0.openedFileURL == tsv && $0.pendingCSV == nil } }
        let grid=v.documents.first { $0.openedFileURL == tsv }!
        try check(try await yes(grid,"statsDirectGrid.csvSnapshot('\\t').text.includes('before\\tafter')"),"File/Open TSV decodes two actual columns and exports tabs")
        _=try await js(grid,"statsDirectGrid.editCommand('selectAll','')")
        try await wait { try await yes(grid,"statsDirectGrid.analysisSource().selection.length===2") }
        let printable=try await v.documentPrintHTML(grid)
        let page=try await DocumentPrintView.load(html:printable,title:grid.title)
        let pdf=try await page.web.pdf(configuration:WKPDFConfiguration())
        let output=PDFDocument(data:pdf)
        try check((output?.pageCount ?? 0)>0 && output?.string?.contains("312") == true && output?.string?.contains("231") == true,"worksheet PDF print snapshot includes first and last selected data, beyond canvas rendering")
        try check(v.validateMenuItem(NSMenuItem(title:"Print",action:#selector(Viewer.printPage),keyEquivalent:"")),"Print is enabled for worksheet documents")

        v.analysisSourceID=grid.id
        let item=NSMenuItem(title:"Paired t",action:nil,keyEquivalent:"");item.representedObject="TPaired"
        v.openAnalysisOperation(item);let paired=v.active!
        try await wait { try await yes(paired,"!!document.querySelector('input[name=paired-agreement]')") }
        _=try await js(paired,"document.querySelector('label.source input[type=checkbox]').click();document.querySelector('input[name=paired-agreement]').click();document.querySelector('.paired-inputs button[type=submit]').click()")
        try await wait { report.reportEntries!.count == 2 && paired.analysisJobID != nil && paired.completedJobID == nil }
        try check(paired.repeatAnalysis && report.reportEntries!.last!.body.contains("<svg"),"repeat mode keeps the agreement result in the active report and starts another acquisition")
        try check(try await yes(grid,"statsDirectGrid.analysisSource().selection.length===0"),"repeat mode clears the previous worksheet selection")
        try await Task.sleep(nanoseconds:700_000_000)
        try check(report.reportEntries!.count==2,"repeat waits for new input without creating duplicate results")
        try await wait("repeat form ready for a new selection") { try await yes(paired,"!!document.querySelector('.paired-inputs button[type=submit]:not(:disabled)')") }
        v.tabs.selectTabViewItem(grid.item)
        v.window.contentView?.layoutSubtreeIfNeeded()
        _=try await js(grid,"statsDirectGrid.setCellText({col:0,row:1,text:'322'})")
        // A real heading drag selects worksheet columns even if a cell editor
        // held focus. Select All intentionally targets that editor's text.
        _=try await grid.web.callAsyncJavaScript("""
        await new Promise(r=>setTimeout(r,100));
        const b=document.querySelector('canvas').getBoundingClientRect();
        if(b.width<=0||b.height<=0)throw new Error('Worksheet canvas has no laid-out area');
        const y=b.y+18,x=c=>b.x+48+c*178+89;
        const send=(type,c,buttons)=>document.elementFromPoint(x(c),y).dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:x(c),clientY:y,button:0,buttons}));
        send('mousedown',0,1);send('mousemove',1,1);send('mouseup',1,0);return true;
        """,arguments:[:],in:nil,contentWorld:.page)
        try await wait("new worksheet column selection") { try await yes(grid,"statsDirectGrid.analysisSource().selection.length===2") }
        v.tabs.selectTabViewItem(paired.item)
        // The empty chooser already contains a .selection element. Wait for
        // the asynchronous worksheet refresh to render the new column names
        // before clicking Run; existence alone can submit the old empty input.
        try await wait("repeat form reflects the new selection") {
            try await yes(paired,"document.querySelector('.paired-inputs .selection')?.textContent.includes('before → after') && !!document.querySelector('.paired-inputs button[type=submit]:not(:disabled)')")
        }
        _=try await js(paired,"document.querySelector('.paired-inputs button[type=submit]').click()")
        try await wait("second repeat result") { report.reportEntries!.count==3 && paired.analysisJobID != nil && paired.completedJobID == nil }
        try check(report.reportEntries![1].body.contains("56.111111") && report.reportEntries!.last!.body.contains("57.222222"),"second batch run reads the newly selected edited data")
        _=try await js(paired,"document.querySelector('.cancel button').click()")
        try await wait { paired.analysisJobID == nil }
        try check(paired.analysisCancelled && report.reportEntries!.count==3,"cancelling the repeat ends the loop and retains the first report")

        let script=v.makeRScript(script:"Console.WriteLine(Math.Sqrt(81));",title:"C# check")
        scriptState(v,script,"C#: created")
        script.rPane!.setLanguage("CSharp");script.rPane!.runScript()
        scriptState(v,script,"C#: Run returned")
        try await wait("C# completion") { !script.rPane!.isRunning }
        scriptState(v,script,"C#: completed")
        try check(script.rPane!.console.string.contains("9") && script.rPane!.state.stringValue=="Script complete","native C# script Run produces visible console output")
        scriptState(v,script,"VB: before setLanguage")
        script.rPane!.setLanguage("VB")
        scriptState(v,script,"VB: after setLanguage")
        try check(script.rPane!.language=="VB","idle script changes to VB before execution")
        script.rPane!.editor.string="Console.WriteLine(6 * 7)"
        scriptState(v,script,"VB: after replacing source, before Run")
        script.rPane!.runScript()
        scriptState(v,script,"VB: Run returned")
        try await wait("VB completion") { !script.rPane!.isRunning }
        scriptState(v,script,"VB: completed")
        try check(script.rPane!.console.string.contains("42") && script.rPane!.scriptFileName.hasSuffix(".vb"),"native language switch executes VB and changes the save extension")
        try check(script.rPane!.openInR()==nil,"Open in R cannot accidentally execute a C# or VB script")
        let scriptHTML=try await v.documentPrintHTML(script)
        try check(scriptHTML.contains("Console.WriteLine(6 * 7)"),"script printing uses current edited source")
        let file=folder.appendingPathComponent("saved.cs");try "Console.WriteLine(123);".write(to:file,atomically:true,encoding:.utf8)
        v.openDocumentURLs([file]);let opened=v.active!
        try check(opened.rPane?.language=="CSharp" && opened.rPane?.isRunning==false && opened.rPane?.console.string.isEmpty==true,"opening a C# file chooses its language and does not execute it")

        for (doc,language) in [(opened,"CSharp"),(script,"VB")] {
            let context=ScriptAIContext(viewer:v,script:doc,workbook:nil,active:{true})
            let overview=try await context.overview()
            let metadata=(overview["documents"] as! [[String:Any]])[0]
            let snapshot=try await context.call("statsdirect_read_document",["documentId":doc.id])
            try check(metadata["language"] as? String==language && snapshot["language"] as? String==language && context.rSource.isEmpty,"AI context names \(language) correctly and excludes it from R replay")
        }

        let xls=folder.appendingPathComponent("export.xls")
        v.exportLegacyExcel(grid,to:xls)
        try await wait { !grid.fileBusy }
        try check(FileManager.default.fileExists(atPath:xls.path) && grid.openedFileURL==tsv,"native legacy Excel export writes a separate data copy and preserves source identity")
    }
}
