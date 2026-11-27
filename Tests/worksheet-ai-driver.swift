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
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
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

        func openWorkbook(in folder: String, value: String) async throws -> Document {
            let location = directory.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            let file = location.appendingPathComponent("Fictional.xlsx")
            let path = file.resolvingSymlinksInPath()
            try FileManager.default.copyItem(at: viewer.root.appendingPathComponent("Examples/test.xlsx"), to: file)
            viewer.openExcelURL(file)
            try await wait("Workbook did not open from " + folder) {
                guard let doc = viewer.active, doc.openedFileURL?.resolvingSymlinksInPath() == path,
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
        func control<T: NSView>(_ id: String, in view: NSView) -> T? {
            if view.identifier?.rawValue == id, let match = view as? T { return match }
            for child in view.subviews {
                if let match: T = control(id, in: child) { return match }
            }
            return nil
        }

        let first = try await openWorkbook(in: "Workbook A", value: "142741")
        try await toolbar(first, "worksheetAI")
        try await wait("Worksheet toolbar did not open AI Assist") { viewer.worksheetAI?.workbookID == first.id }
        let pane = viewer.worksheetAI!
        try check(pane.share.state == .off && pane.confirm.state == .off, "worksheet sharing starts off")
        let second = try await openWorkbook(in: "Workbook B", value: "281593")
        try check(pane.workbookID == second.id && pane.share.state == .off, "opening a workbook follows it without authorising it")
        let workbookLabel: NSTextField? = control("worksheet-ai-workbook", in: pane.view)
        let labelB = workbookLabel?.stringValue ?? ""
        try check(labelB.contains("Fictional.xlsx") && labelB.contains("Workbook B") && !labelB.contains("Workbook A"),
                  "the sharing label distinguishes same-named Excel files by folder")
        try JSONSerialization.data(withJSONObject: ["A": first.id, "B": second.id])
            .write(to: storage.appendingPathComponent("workbooks.json"))
        _ = try await viewer.chatGPTTutor.signIn()
        try await viewer.chatGPTTutor.refreshAccount()

        for (doc, name) in [(first, "A"), (second, "B")] {
            viewer.tabs.selectTabViewItem(doc.item)
            try check(workbookLabel?.stringValue.contains("Workbook " + name) == true,
                      "switching to workbook \(name) displays its folder")
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
        let folded = try await pane.transcript.web.evaluateJavaScript("!!document.querySelector('details[data-r-block]:not([open])')") as? Bool
        try check(folded == true, "suggested R code is collapsed in the worksheet reply")
        _ = try await pane.transcript.web.evaluateJavaScript("""
            document.querySelector('details[data-r-block]').open = true;
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
        let confirmation: NSTextField? = control("worksheet-ai-confirmation", in: pane.view)
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        try check(confirmation?.stringValue.contains("Menu: Analysis › Parametric") == true,
                  "the inline confirmation gives the method's menu path")
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        if let proceed {
            let action = pane.view.convert(proceed.bounds, from: proceed)
            let history = pane.view.convert(pane.transcript.view.bounds, from: pane.transcript.view)
            let above = pane.view.isFlipped ? action.maxY <= history.minY : action.minY >= history.maxY
            try check(above && !proceed.isHiddenOrHasHiddenAncestor,
                      "Continue appears above the transcript beside the worksheet controls")
        } else { throw ChatGPTTutor.Failure(message: "The visible Continue button was not found") }
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

        pane.input.string = "CLOSE_A"
        pane.send()
        try await wait("The fixture did not start the reply to close") {
            (await text(pane)).contains("Close-test stream for A.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        pane.hide()
        try await wait("Closing the pane did not interrupt the reply and reject a late read") {
            !pane.isBusy && FileManager.default.fileExists(atPath: storage.appendingPathComponent("close-read-rejected").path)
        }
        try check(!pane.visible && pane.workbookID == first.id, "closing the dock stops sharing without switching the hidden conversation")
        try await toolbar(second, "worksheetAI")
        try await wait("The reopened dock did not follow the active workbook") { pane.visible && pane.workbookID == second.id }
        try check(!(await text(pane)).contains("Close-test stream for A."), "the reopened dock does not show the other workbook's partial reply")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("Closing the dock lost the original stopped reply") {
            let transcript = await text(pane)
            return transcript.contains("Close-test stream for A.") && transcript.contains("Reply stopped before completion")
        }
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        let questionHint: NSTextField? = control("worksheet-ai-question-only-hint", in: pane.view)
        try check(questionHint?.isHiddenOrHasHiddenAncestor == false
                  && questionHint?.stringValue.localizedCaseInsensitiveContains("full question each time") == true,
                  "question-only mode explains that each send needs the full question")
        pane.input.string = "QUESTION_ONLY"
        pane.send()
        try await wait("Question-only mode did not send a clean payload") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("General guidance without workbook data.")
        }
        try check(true, "question-only payload omits workbook, data tools and earlier chat")
        try check((await text(pane)).contains("General guidance · No worksheet cells read for this reply"),
                  "a reply that read no cells says so under it")

        // Markers wherever a real reply puts them: after a sentence, in a list item, in backticks; never inside code.
        let cases: [(String, String, [String])] = [
            ("Use this.\n[[method:TPaired]]\nThen check.", "Use this.\n\nThen check.", ["TPaired"]),
            ("I haven't run the test. [[method:TPaired]]", "I haven't run the test.", ["TPaired"]),
            ("Try [[method:TPaired]] or `[[method:Wilcoxon]]` here.", "Try or here.", ["TPaired", "Wilcoxon"]),
            ("- [[method:TPaired]]\n  1. `[[method:Wilcoxon]]`\n> [[method:TPaired]]", "\n\n", ["TPaired", "Wilcoxon", "TPaired"]),
            ("[[method:TPaired]] is the paired test", " is the paired test", ["TPaired"]),
            ("```r\n# [[method:TPaired]]\n```\n[[method:Wilcoxon]]", "```r\n# [[method:TPaired]]\n```\n", ["Wilcoxon"]),
            ("~~~~\n[[method:TPaired]]\n~~~\n[[method:TPaired]]\n~~~~\nafter [[method:Wilcoxon]]", "~~~~\n[[method:TPaired]]\n~~~\n[[method:TPaired]]\n~~~~\nafter", ["Wilcoxon"]),
            ("1. ```r\n   x <- '[[method:TPaired]]'\n   ```\n[[method:TPaired]]", "1. ```r\n   x <- '[[method:TPaired]]'\n   ```\n", ["TPaired"]),
            ("Inline ```code``` then [[method:TPaired]]", "Inline ```code``` then", ["TPaired"]),
            ("No marker: [[method:]] [[method:T Paired]] [method:TPaired]", "No marker: [[method:]] [[method:T Paired]] [method:TPaired]", [])
        ]
        for (reply, shown, ids) in cases {
            let read = WorksheetAIMarkers.read(reply)
            guard read.text == shown, read.ids == ids else {
                throw ChatGPTTutor.Failure(message: "Method markers misread in \(reply.debugDescription): \(read.text.debugDescription) \(read.ids)")
            }
        }
        try check(true, "method markers are read after a sentence, in a list item and in backticks, and never inside code (\(cases.count) cases)")
        pane.input.string = "INLINE_MARKER"
        pane.send()
        try await wait("The reply with markers inside its text did not arrive") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Marker reply for the paired design.")
        }
        let markerReply = await text(pane)
        let paired: NSButton? = control("TPaired", in: pane.view), plot: NSButton? = control("BoxWhiskerPlot", in: pane.view)
        let code = try await pane.transcript.web.evaluateJavaScript(
            "document.querySelector('article.assistant:last-of-type code').textContent") as? String
        try check(!markerReply.contains("[[method:") && markerReply.contains("Marker reply for the paired design.")
                  && markerReply.contains("shows the pairs")
                  && paired?.isHiddenOrHasHiddenAncestor == false && plot?.isHiddenOrHasHiddenAncestor == false
                  && code?.contains("# [[method:TPaired]] stays in code") == true,
                  "a marker inside a sentence or in backticks is not shown, still offers its method, and code keeps its text")

        // Windows pull request 40, engine-independent part: the live selection, the Data used receipt (headings, Stop
        // and failure), Reply in progress, the clarifying card, the structure-only overview and the empty-workbook choices.
        func grid(_ doc: Document, _ script: String) async throws {
            _ = try await doc.web.callAsyncJavaScript(script + "; return true;", arguments: [:], in: nil, contentWorld: .page)
        }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: storage.appendingPathComponent(name).path) }
        func receiptLines() async -> [String] {
            (try? await pane.transcript.web.evaluateJavaScript("""
                (() => { const all = [...document.querySelectorAll('details[data-receipt]')], last = all[all.length - 1];
                  return last ? [...last.querySelectorAll('li')].map(item => item.textContent) : []; })()
                """)) as? [String] ?? []
        }
        // A stack view detaches a hidden control only at its next layout pass, so "not shown" is hidden or absent.
        func shown(_ id: String) -> Bool {
            let found: NSView? = control(id, in: pane.view)
            return found?.isHiddenOrHasHiddenAncestor == false
        }
        func assistantRows() async -> Int {
            (try? await pane.transcript.web.evaluateJavaScript("document.querySelectorAll('article.assistant').length")) as? Int ?? -1
        }
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A") { pane.workbookID == first.id && !pane.isBusy }
        let beforeHeading = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:1,row:0,text:'Qzheading'})")
        try await wait("The heading edit did not settle") { first.gridVersion > beforeHeading }

        try await grid(first, "statsDirectGrid.selectCells({x:1,y:2,width:1,height:1})")
        try await wait("The selection label did not show the current cell") {
            pane.selectionLabel.stringValue == "Current cell: Parametric!B3" && !pane.selectionLabel.isHidden
        }
        try check(true, "the pane's label follows the current cell")
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:1,width:2,height:4})")
        try await wait("The selection label did not show the selected range") { pane.selectionLabel.stringValue == "Selection: Parametric!A2:B5" }
        try check(true, "the pane's label shows a selected range in A1 notation")
        try await grid(first, "statsDirectGrid.clearSelection()")
        try await wait("Clearing the selection did not hide the label") { pane.selectionLabel.isHidden }
        try check(true, "with nothing selected the label is hidden")

        // Share A again: the earlier question-only check turned its sharing off.
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        try check(pane.replyActivity.isHidden, "no reply indicator while AI Assist is idle")
        pane.input.string = "OVERVIEW_A"
        pane.send()
        try check(pane.isBusy && !pane.replyActivity.isHidden && pane.replyActivity.stringValue == "Reply in progress…" && pane.stopButton.isEnabled,
                  "Reply in progress… appears beside Stop as soon as a question is sent")
        try await wait("The overview reply did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Overview checked for A.")
        }
        try check(pane.replyActivity.isHidden, "Reply in progress… goes when the reply completes")
        try check(exists("overview-checked"), "the shared overview gives sheets, extents, column letters and the selection, but no headings or cell values")
        let overviewRead = try JSONSerialization.jsonObject(with: Data(contentsOf: storage.appendingPathComponent("overview-read.json"))) as? [String: Any]
        let headings = overviewRead?["headerRow"] as? Bool == true
        if headings {
            try check((overviewRead?["titles"] as? [String]) == ["Score", "Qzheading"], "the row-1 headings travel only as the titles of a bounded read")
        }
        let overviewLines = await receiptLines()
        try check(overviewLines == ["Fictional.xlsx · Parametric · " + (headings ? "A1:B1 (headings), " : "") + "A2:B3 (part of the worksheet’s used range)"],
                  "Data used lists the range read and the headings sent as titles: \(overviewLines)")
        let summary = try await pane.transcript.web.evaluateJavaScript("document.querySelector('details[data-receipt] summary').textContent") as? String
        try check(summary == "Data used", "the receipt is a Data used disclosure under the reply")

        pane.input.string = "CLARIFY_A"
        pane.send()
        try await wait("The clarifying question did not appear") { !pane.isBusy && pane.clarification != nil }
        let question: NSTextField? = control("worksheet-ai-clarification-question", in: pane.view)
        let means: NSButton? = control("worksheet-ai-choice-means", in: pane.view), unsure: NSButton? = control("worksheet-ai-choice-unsure", in: pane.view)
        let general: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
        try check(question?.stringValue == "What would you like to find out?" && means?.title == "Compare means" && unsure?.title == "I’m not sure"
                  && means?.isHiddenOrHasHiddenAncestor == false && general?.isHiddenOrHasHiddenAncestor != false,
                  "the assistant's clarifying question shows its fixed answers below the reply, in place of the general choices"
                  + " (\(question?.stringValue ?? "no question"); \(means?.title ?? "no means"); \(unsure?.title ?? "no unsure"); general shown: \(general?.isHiddenOrHasHiddenAncestor == false))")
        let staleToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:1,width:1,height:3})")
        try await wait("A selection change did not retire the card's token") { pane.guidanceToken != staleToken }
        try check(!pane.answerClarification("means", token: staleToken) && pane.clarification != nil && !pane.isBusy,
                  "a late click on the card drawn before the selection changed is refused")
        let editToken = pane.guidanceToken, beforeEdit = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:2,row:4,text:'5'})")
        try await wait("An edit did not retire the card's token") { first.gridVersion > beforeEdit && pane.guidanceToken != editToken }
        try check(!pane.answerClarification("means", token: editToken) && pane.clarification != nil,
                  "a late click on the card drawn before an edit is refused")
        let current: NSButton? = control("worksheet-ai-choice-means", in: pane.view)
        current?.performClick(nil)
        try await wait("The chosen answer was not sent") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Means noted.")
        }
        try check((await text(pane)).contains("I want to compare means.") && pane.clarification == nil,
                  "choosing an answer sends its sentence with the conversation and retires the card")

        pane.input.string = "READ_STOP_A"
        pane.send()
        try await wait("The fixture did not read before stopping") { exists("read-served") }
        pane.stop()
        try check(!pane.isBusy || pane.replyActivity.stringValue == "Stopping…", "Stop shows that the reply is stopping")
        try await wait("Stop did not end the reply") { !pane.isBusy }
        try check(pane.replyActivity.isHidden, "Reply in progress… goes when the reply is stopped")
        let readLine = "Fictional.xlsx · Parametric · " + (headings ? "A1 (headings), " : "") + "A2 (part of the worksheet’s used range)"
        let stoppedLines = await receiptLines()
        try check((await text(pane)).contains("[Reply stopped before any text.]") && stoppedLines == [readLine],
                  "a reply stopped after a read but before any text keeps its Data used receipt: \(stoppedLines)")

        pane.input.string = "READ_FAIL_A"
        pane.send()
        try await wait("The failed reply did not end") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("[No reply was received.]")
        }
        let failedLines = await receiptLines()
        try check(failedLines == [readLine] && pane.input.string == "READ_FAIL_A",
                  "a reply that fails after a read keeps its receipt and returns the question to the composer: \(failedLines)")
        pane.input.string = ""

        let rowsBefore = await assistantRows()
        pane.input.string = "HOLD_A"
        pane.send()
        try await wait("The held question did not reach the fixture") {
            (try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8))?.contains("HOLD_A") == true
        }
        pane.stop()
        try await wait("Stop did not end the held reply") { !pane.isBusy }
        try check(await assistantRows() == rowsBefore && pane.replyActivity.isHidden, "Stop before any read or text adds no reply and no receipt")
        let log = (try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? ""
        try check(!log.isEmpty && !log.contains("Data used") && !log.contains("(headings)") && !log.contains("part of the worksheet"),
                  "no receipt reaches the provider in any request, including the shared follow-ups after it")

        viewer.newWorksheet()
        guard let blank = viewer.documents.last(where: { $0.kind == "grid" && $0.openedFileURL == nil }) else {
            throw ChatGPTTutor.Failure(message: "The new worksheet was not created")
        }
        try await wait("The empty workbook's choices did not appear") {
            let example: NSButton? = control("worksheet-ai-open-example", in: pane.view)
            return pane.workbookID == blank.id && blank.pendingWorkbook == nil && example?.isHiddenOrHasHiddenAncestor == false
        }
        let workbookHelp: NSButton? = control("worksheet-ai-workbook-help", in: pane.view)
        let browse: NSButton? = control("worksheet-ai-browse-methods", in: pane.view)
        try check((await text(pane)).contains("This workbook is empty.") && workbookHelp?.isHiddenOrHasHiddenAncestor == false
                  && browse?.isHiddenOrHasHiddenAncestor != false && !shown("worksheet-ai-help-choose"),
                  "an empty workbook offers the example workbook and the workbook Help instead of method guidance")
        try await grid(blank, "statsDirectGrid.setCellText({col:0,row:0,text:'7'})")
        try await wait("Data did not bring back the general choices") {
            let guide: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
            return guide?.isHiddenOrHasHiddenAncestor == false
        }
        try check(!(await text(pane)).contains("This workbook is empty."), "a workbook with data offers Help me choose a method and Browse methods")
        let guide: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
        guide?.performClick(nil)
        try await wait("Help me choose a method did not send its question") {
            guard !pane.isBusy else { return false }
            let shown = await text(pane)
            return shown.contains("Help me choose a statistical method.") && shown.contains("General guidance without workbook data.")
        }
        try check((await text(pane)).contains("General guidance · No worksheet cells read for this reply"),
                  "Help me choose a method asks in question-only mode, which sends nothing about the workbook and reads no cells")

        viewer.newWorksheet()
        guard let blank2 = viewer.documents.last(where: { $0.kind == "grid" && $0.openedFileURL == nil && $0 !== blank }) else {
            throw ChatGPTTutor.Failure(message: "The second new worksheet was not created")
        }
        try await wait("The second empty workbook's choices did not appear") {
            let example: NSButton? = control("worksheet-ai-open-example", in: pane.view)
            return pane.workbookID == blank2.id && blank2.pendingWorkbook == nil && example?.isHiddenOrHasHiddenAncestor == false
        }
        (control("worksheet-ai-open-example", in: pane.view) as NSButton?)?.performClick(nil)
        try await wait("Open example workbook did not open test.xlsx in AI Assist") {
            guard let example = viewer.documents.last(where: { $0.kind == "grid" && $0.workbookName == "test.xlsx" }),
                  example.pendingWorkbook == nil, pane.workbookID == example.id else { return false }
            let choices: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
            return choices?.isHiddenOrHasHiddenAncestor == false
        }
        try check(true, "Open example workbook opens test.xlsx, which AI Assist follows with its general choices")
        viewer.tabs.selectTabViewItem(blank2.item)
        try await wait("AI Assist did not follow the empty workbook again") {
            let help: NSButton? = control("worksheet-ai-workbook-help", in: pane.view)
            return pane.workbookID == blank2.id && help?.isHiddenOrHasHiddenAncestor == false
        }
        (control("worksheet-ai-workbook-help", in: pane.view) as NSButton?)?.performClick(nil)
        try await wait("Workbook help did not open the workbook topic") {
            viewer.helpPane.visible && viewer.helpPane.web.url?.path.hasSuffix("basics/worksheet.htm") == true
        }
        try check(!pane.visible, "Workbook help opens the workbook topic in the dock in place of AI Assist")
        viewer.tabs.selectTabViewItem(first.item)
        try await toolbar(first, "worksheetAI")
        try await wait("AI Assist did not reopen on workbook A") { pane.visible && pane.workbookID == first.id }
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
