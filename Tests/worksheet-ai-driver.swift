import Cocoa
import WebKit

@main struct WorksheetAIChecks {
    @MainActor static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ChatGPTTutor.Failure(message: message) }
        print("PASS: " + message)
        fflush(stdout)
    }

    @MainActor static func wait(_ message: String, until condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChatGPTTutor.Failure(message: message)
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
        let viewer = Viewer()
        app.delegate = viewer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                do { try await run(viewer) }
                catch { print("FAIL: " + error.localizedDescription); exit(1) }
                viewer.closeApproved = true
                app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 150) {
            print("FAIL: Worksheet AI test timed out"); exit(1)
        }
        app.run()
    }

    @MainActor static func run(_ viewer: Viewer) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("worksheet-ai-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("chatgpt-mock")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        viewer.chatGPTTutor.shutdown()
        viewer.chatGPTTutor = ChatGPTTutor(executable: root.appendingPathComponent("Tests/mock-worksheet-ai-server.py"),
                                         storage: storage, resources: viewer.root.appendingPathComponent("Tutor"))
        viewer.chatGPTTutor.changed = { [weak viewer] in viewer?.worksheetAI?.updateControls() }
        defer { viewer.chatGPTTutor.shutdown() }
        viewer.window.setContentSize(NSSize(width: 1350, height: 850))

        func openWorkbook(_ name: String, value: String) async throws -> Document {
            let file = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: viewer.root.appendingPathComponent("Examples/test.xlsx"), to: file)
            viewer.openExcelURL(file)
            try await wait("Workbook did not open: " + name) {
                guard let doc = viewer.active, doc.workbookName == name,
                      doc.pendingWorkbook == nil, !doc.web.isLoading else { return false }
                return (try? await doc.web.evaluateJavaScript("!!window.statsDirectGrid")) as? Bool == true
            }
            let doc = viewer.active!
            _ = try await doc.web.callAsyncJavaScript("""
                statsDirectGrid.setCellText({col:0,row:0,text:'Score'});
                statsDirectGrid.setCellText({col:0,row:1,text:value});
                return true;
                """, arguments: ["value": value], in: nil, contentWorld: .page)
            try await wait("Workbook edits did not settle") { doc.gridVersion >= 2 }
            return doc
        }
        func toolbar(_ doc: Document, _ id: String) async throws {
            _ = try await doc.web.evaluateJavaScript("document.querySelector('[data-command=\(id)]').click()")
        }
        func text(_ pane: WorksheetAIPane) async -> String {
            (try? await pane.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
        }

        let first = try await openWorkbook("Fictional A.xlsx", value: "142741")
        try await toolbar(first, "worksheetAI")
        try await wait("Worksheet toolbar did not open AI Assist") { viewer.worksheetAI?.workbookID == first.id }
        let pane = viewer.worksheetAI!
        try check(pane.share.state == .off && pane.confirm.state == .off, "worksheet sharing starts off")
        let second = try await openWorkbook("Fictional B.xlsx", value: "281593")
        try check(pane.workbookID == second.id && pane.share.state == .off, "opening a workbook follows it without authorising it")
        try JSONSerialization.data(withJSONObject: ["A": first.id, "B": second.id])
            .write(to: storage.appendingPathComponent("workbooks.json"))
        _ = try await viewer.chatGPTTutor.signIn()
        try await viewer.chatGPTTutor.refreshAccount()

        for (doc, name) in [(first, "A"), (second, "B")] {
            viewer.tabs.selectTabViewItem(doc.item)
            try check(pane.share.state == .off && pane.confirm.state == .off, "each workbook needs its own approval")
            pane.share.performClick(nil)
            try check(!pane.sendButton.isEnabled, "worksheet sharing requires confirmation")
            pane.confirm.performClick(nil)
            pane.input.string = "READ_" + name
            pane.send()
            try await wait("The mock could not read its approved workbook " + name) {
                guard !pane.isBusy else { return false }
                return (await text(pane)).contains("Synthetic workbook \(name) data checked.")
            }
        }
        try check(true, "the mock verified bidirectional workbook-data isolation and exact approved cells")
        let folded = try await pane.transcript.web.evaluateJavaScript("!!document.querySelector('details:not([open])')") as? Bool
        try check(folded == true, "suggested R code is collapsed in the worksheet reply")
        _ = try await pane.transcript.web.evaluateJavaScript("""
            document.querySelector('details').open = true;
            document.querySelector('[data-code=r]').click();
            """)
        try await wait("Open in R did not create a review tab") { viewer.active?.rConsolePane != nil }
        let review = viewer.active!
        try check(review.rConsolePane?.sourceText.contains("mean(2:4)") == true && review.rConsolePane?.hasWorkspace == false
                  && pane.workbookID == second.id,
                  "Open in R creates an unexecuted review tab without retargeting the worksheet dock")
        viewer.remove(review)
        viewer.tabs.selectTabViewItem(second.item)
        let count = viewer.documents.count
        _ = try await second.web.evaluateJavaScript("window.statsDirectGrid.editCommand('selectAll', '')")
        pane.chooseMethod.performClick(nil)
        try await wait("Choose a method did not open the native Analyse catalogue") {
            (try? await second.web.evaluateJavaScript("!!document.getElementById('worksheet-analysis-search')")) as? Bool == true
        }
        _ = try await second.web.evaluateJavaScript("""
            const field = document.getElementById('worksheet-analysis-search');
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, 'paired t');
            field.dispatchEvent(new Event('input', {bubbles:true}));
            """)
        try await wait("Paired t did not appear in the method picker") {
            (try? await second.web.evaluateJavaScript("!!document.querySelector('[data-worksheet-command=TPaired]')")) as? Bool == true
        }
        _ = try await second.web.evaluateJavaScript("document.querySelector('[data-worksheet-command=TPaired]').click()")
        try await wait("The method picker did not create a local confirmation") { pane.offer != nil }
        try check(viewer.documents.count == count, "choosing a method waits for Continue before opening an analysis")
        pane.cancelAnalysis()
        viewer.tabs.selectTabViewItem(second.item)
        pane.input.string = "Keep this draft for B"
        viewer.tabs.selectTabViewItem(first.item)
        try check(pane.share.state == .on && pane.confirm.state == .on, "returning restores the workbook's approval")
        pane.input.string = "FINISH_A"
        pane.send()
        try await wait("The fixture did not start a read in A") {
            (await text(pane)).contains("Reading A after the switch.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        try Data().write(to: storage.appendingPathComponent("finish-stream"))
        try await wait("A's reply did not finish before following B") { !pane.isBusy && pane.workbookID == second.id }
        try check(pane.input.string == "Keep this draft for B", "natural reply completion follows the most recent workbook")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("A did not keep its completed response") {
            (await text(pane)).contains("Synthetic workbook A data checked after switching.")
        }
        try check(true, "a streamed data read after switching stays scoped to the original approved workbook")
        pane.input.string = "STOP_A"
        pane.send()
        try await wait("The fixture did not stream in A") {
            guard pane.isBusy else { return false }
            return (await text(pane)).contains("Streaming for A.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        let report = viewer.makeReport()
        try check(pane.workbookID == first.id && pane.isBusy, "a report and a new workbook do not retarget a streaming reply")
        pane.stop()
        try await wait("Stop did not switch to the pending workbook") { !pane.isBusy && pane.workbookID == second.id }
        try check(pane.input.string == "Keep this draft for B", "following the last workbook restores its own draft")
        let restored = await text(pane)
        try check(!restored.contains("Streaming for A."), "the stopped partial reply stays in its original transcript")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("The stopped reply was lost") { (await text(pane)).contains("Reply stopped before completion") }

        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        pane.input.string = "QUESTION_ONLY"
        pane.send()
        try await wait("Question-only mode did not send a clean payload") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("General guidance without workbook data.")
        }
        try check(true, "question-only payload omits workbook, data tools and earlier chat")
        viewer.remove(report)
        viewer.tabs.selectTabViewItem(first.item)
        try await toolbar(first, "worksheetLearn")
        try await wait("Learn did not open from the toolbar") { viewer.active?.kind == "learn" }
        try check(pane.workbookID == first.id, "Learning opens from the toolbar without retargeting worksheet AI")
        UserDefaults.standard.set(true, forKey: "DisableOnlineTutor")
        pane.updateControls()
        try check(!pane.sendButton.isEnabled && !pane.share.isEnabled, "managed online AI disable blocks worksheet sending and sharing")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
    }
}
