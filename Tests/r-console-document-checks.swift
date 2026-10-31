import Cocoa
import WebKit

extension RConsoleIntegrationTests {
    /// Native document routing and commands for the default production console.
    /// Source files stay passive; only the explicit console command below runs.
    @MainActor static func consoleDocumentChecks(_ viewer: Viewer) async throws -> [URL] {
        let originalIDs = Set(viewer.documents.map(\.id))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-console-documents-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var directories: [URL] = []
        var completed = false
        defer {
            if !completed { sessionFolders += directories }
            for doc in viewer.documents.filter({ !originalIDs.contains($0.id) }) {
                doc.rConsolePane?.shutdown(); doc.rPane?.shutdown(); viewer.remove(doc)
            }
            try? FileManager.default.removeItem(at: folder)
        }
        viewer.newRTab()
        guard let doc = viewer.active, let pane = doc.rConsolePane else { throw LegacyReportError("File New Script did not create an interactive console") }
        try await makeConsoleVisible(viewer, doc); try await ready(doc)
        if let directory = pane.session.workingDirectory { directories.append(directory) }
        let initial = try await snapshot(doc)
        try check(initial["mode"] as? String == "script" && (initial["history"] as? [String] ?? []).isEmpty && pane.sourceText.isEmpty,
                  "File New Script opens Script view without executing source or adding history")
        let source = (0..<100).map { "# retained line \($0)" }.joined(separator: "\n")
            + "\nneverExecuted <- stop('DO_NOT_RUN_SOURCE')\n# literal Needle[1] <tag> & value\n# second Needle[1]\n"
        _ = try await doc.web.callAsyncJavaScript("""
        const field=document.getElementById('script-source');field.value=source;
        field.setSelectionRange(0,0);field.dispatchEvent(new Event('input',{bubbles:true}));return true;
        """, arguments: ["source": source], in: nil, contentWorld: .page)
        try await wait("edited source snapshot") { pane.sourceText == source }
        viewer.showReportFind()
        guard let bar = doc.findBar else { throw LegacyReportError("The console find bar was not installed") }
        bar.term.stringValue = "Needle[1]"; bar.findNext()
        func selected() async throws -> (String, Int) {
            let value = try await evaluate(doc, "(()=>{const f=document.getElementById('script-source');return [f.value.slice(f.selectionStart,f.selectionEnd),f.selectionStart];})()") as? [Any] ?? []
            return (value.first as? String ?? "", value.dropFirst().first as? Int ?? -1)
        }
        try await wait("literal script match") { try await selected().0 == "Needle[1]" }
        let first = try await selected().1
        let next = NSMenuItem(title: "Find Next", action: #selector(Viewer.findReportNext), keyEquivalent: "g")
        let previous = NSMenuItem(title: "Find Previous", action: #selector(Viewer.findReportPrevious), keyEquivalent: "g")
        try check(!bar.isHidden && viewer.validateMenuItem(next) && viewer.validateMenuItem(previous), "the native console Find bar and Find Next/Previous menu commands are available")
        viewer.findReportNext()
        try await wait("next script match") { try await selected().1 > first }
        viewer.findReportPrevious()
        try await wait("previous script match") { try await selected().1 == first }
        let unchanged = try await snapshot(doc)
        try check(pane.sourceText == source && (unchanged["history"] as? [String] ?? []).isEmpty
                  && bar.replacement.isHidden == false && bar.replacement.ancestorsContainHiddenView,
                  "literal Find, Cmd-G and Shift-Cmd-G select source without editing or executing it; Replace controls are absent")
        let scriptHTML = try await viewer.documentPrintHTML(doc)
        let scriptPrint = try await DocumentPrintView.load(html: scriptHTML, title: doc.title)
        let printedSource = try await scriptPrint.web.evaluateJavaScript("document.querySelector('pre')?.textContent") as? String
        try check(printedSource == source && scriptHTML.contains("&lt;tag&gt; &amp; value") && printedSource?.contains("retained line 99") == true,
                  "Script print snapshot includes the complete escaped unexecuted source beyond its visible viewport")
        bar.close()
        _ = try await evaluate(doc, "StatsDirectRConsole.setMode('console');true")
        guard pane.session.submit(source: "cat(paste0('DOC_FIND_', 'OUTPUT'), '\\n'); plot(1:3)") else { throw LegacyReportError("The explicit console fixture command was rejected") }
        try await wait("console output and chart") {
            let value = try await snapshot(doc)
            return pane.session.state == "ready" && (value["transcript"] as? [[String:Any]] ?? []).contains { $0["kind"] as? String == "plot" }
                && (value["outputText"] as? String ?? "").contains("DOC_FIND_OUTPUT")
        }
        // Model events precede the scheduled DOM render. Selecting text first
        // intentionally holds that pending render to preserve the selection.
        try await wait("rendered console output and decoded chart before Find") {
            try await evaluate(doc, """
            (()=>{const transcript=document.getElementById('transcript'),image=transcript?.querySelector('figure.plot img');
            return !!image&&image.complete&&image.naturalWidth>0&&Array.from(transcript.querySelectorAll('.output-entry')).some(node=>node.textContent.includes('DOC_FIND_OUTPUT'));})()
            """) as? Bool == true
        }
        viewer.showReportFind(); bar.term.stringValue = "DOC_FIND_OUTPUT"; bar.findNext()
        try await wait("visible console match") { try await evaluate(doc, "getSelection().toString()") as? String == "DOC_FIND_OUTPUT" }
        let consoleHTML = try await viewer.documentPrintHTML(doc)
        let consolePrint = try await DocumentPrintView.load(html: consoleHTML, title: doc.title)
        let printable = try await consolePrint.web.callAsyncJavaScript("""
        const image=document.querySelector('img');if(image)await image.decode();
        return {text:document.body.innerText,images:document.querySelectorAll('img').length,
                width:image?.naturalWidth??0,buttons:document.querySelectorAll('button,.plot-actions').length};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String:Any] ?? [:]
        let printOK = (printable["text"] as? String ?? "").contains("DOC_FIND_OUTPUT") && printable["images"] as? Int == 1
            && (printable["width"] as? Int ?? 0) > 0 && printable["buttons"] as? Int == 0
        if !printOK {
            let state = try await snapshot(doc)
            let visible = try await evaluate(doc, "(()=>{const t=document.getElementById('transcript');return {text:t?.innerText,images:t?.querySelectorAll('img').length,selection:getSelection().toString()};})()")
            print("INFO: Console print snapshot=\(printable), live DOM=\(visible), mode=\(state["mode"] ?? "nil"), html bytes=\(consoleHTML.utf8.count)")
            fflush(stdout)
        }
        try check(printOK, "Console Find selects output and its offline print snapshot includes the full vector chart without command buttons")
        let path = folder.appendingPathComponent("passive.R")
        let imported = "importedMustNotRun <- stop('IMPORTED_SOURCE_ONLY')\n"
        try imported.write(to: path, atomically: true, encoding: .utf8)
        viewer.openRScriptURL(path)
        guard let opened = viewer.active, let openedPane = opened.rConsolePane else { throw LegacyReportError("An R file did not open in the production console") }
        try await makeConsoleVisible(viewer, opened); try await ready(opened)
        if let directory = openedPane.session.workingDirectory { directories.append(directory) }
        let loaded = try await snapshot(opened)
        try check(loaded["mode"] as? String == "script" && openedPane.sourceText == imported && !openedPane.hasUnsavedChanges
                  && (loaded["history"] as? [String] ?? []).isEmpty && !openedPane.hasWorkspace,
                  "an R file opens saved in Script view without executing imported source")
        for language in ["CSharp", "VB"] {
            let managed = viewer.makeRScript(script: "// passive managed source", language: language)
            try check(managed.rConsolePane == nil && managed.rPane?.language == language && managed.rPane?.isRunning == false,
                      "explicit \(language) source retains the managed script host instead of entering R")
        }
        let shared = folder.appendingPathComponent("same-title.R")
        try "later <- 2".write(to: shared, atomically: true, encoding: .utf8)
        let firstLaunch = try RExternalScript.snapshot(shared, source: "original <- 1", workingDirectory: folder)
        let secondLaunch = try RExternalScript.snapshot(shared, source: "later <- 2", workingDirectory: folder)
        try "third <- 3".write(to: shared, atomically: true, encoding: .utf8)
        try check(firstLaunch != secondLaunch && (try String(contentsOf: firstLaunch, encoding: .utf8)) == "original <- 1"
                  && (try String(contentsOf: secondLaunch, encoding: .utf8)) == "later <- 2",
                  "overlapping external R handoffs retain the exact requested source despite a same-title save or deferred installation")
        completed = true
        return directories
    }
}

private extension NSView {
    var ancestorsContainHiddenView: Bool {
        var ancestor = superview
        while let view = ancestor { if view.isHidden { return true }; ancestor = view.superview }
        return false
    }
}
