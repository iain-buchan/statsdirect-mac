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
        // Generous for a loaded build Mac: the distribution cards' cases more than doubled the run.
        DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
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
        // Windows pull request 40, engine-independent part: the live selection, the Data used receipt (headings, Stop
        // and failure), Reply in progress, the clarifying card, the structure-only overview and the empty-workbook choices.
        func grid(_ doc: Document, _ script: String) async throws {
            _ = try await doc.web.callAsyncJavaScript(script + "; return true;", arguments: [:], in: nil, contentWorld: .page)
        }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: storage.appendingPathComponent(name).path) }
        // A stack view detaches a hidden control only at its next layout pass, so "not shown" is hidden or absent.
        func shown(_ id: String) -> Bool {
            let found: NSView? = control(id, in: pane.view)
            return found?.isHiddenOrHasHiddenAncestor == false
        }
        // The receipt under the latest reply only: its Data used lines, and whether it says no cells were read.
        func lastReceipt() async -> (lines: [String], none: Bool) {
            let value = (try? await pane.transcript.web.evaluateJavaScript("""
                (() => { const rows = document.querySelectorAll('article.assistant'), last = rows[rows.length - 1];
                  return last ? {lines: [...last.querySelectorAll(':scope > details[data-receipt] li')].map(item => item.textContent),
                                 none: !!last.querySelector(':scope > .data-used-none')} : {lines: [], none: false}; })()
                """)) as? [String: Any]
            return ((value?["lines"] as? [String]) ?? [], value?["none"] as? Bool == true)
        }
        func assistantRows() async -> Int {
            (try? await pane.transcript.web.evaluateJavaScript("document.querySelectorAll('article.assistant').length")) as? Int ?? -1
        }
        // The distribution cards' checks. What reached the provider: every request, and the questions and tool results
        // among them (Windows WorksheetAnalysisDataTraffic).
        func requestLines() -> [String] {
            ((try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
        }
        func dataTraffic() -> [String] {
            requestLines().filter { line in
                guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return false }
                return request["method"] as? String == "turn/start" || request["result"] != nil
            }
        }
        func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
        }
        func label(_ id: String) -> String {
            viewer.window.contentView?.layoutSubtreeIfNeeded()
            return (control(id, in: pane.view) as NSTextField?)?.stringValue ?? ""
        }
        // The shown card as Windows' WorksheetActionSnapshot gives it: its kind, its buttons' token, its paragraphs and its
        // choices with their titles.
        struct Card {
            let kind: String, token: String, lines: [String], choices: [String], titles: [String]
            var text: String { (lines + titles).joined(separator: "\n") }
        }
        func card() -> Card? {
            viewer.window.contentView?.layoutSubtreeIfNeeded()
            guard let box: NSView = control("worksheet-ai-distribution", in: pane.view), !box.isHiddenOrHasHiddenAncestor,
                  let kind = pane.distribution?.card.kind.rawValue else { return nil }
            let buttons = views(WorksheetAIChoiceButton.self, in: box)
            return Card(kind: kind, token: buttons.first?.token ?? "", lines: views(NSTextField.self, in: box).map(\.stringValue),
                        choices: buttons.map(\.choice), titles: buttons.map(\.title))
        }
        // Windows WaitForWorksheetEvidence: the card of this kind, drawn with the live token and its selection read, holding
        // every piece of evidence and none of `absent`. A failure shows the card as it stood.
        @discardableResult func waitCard(_ kind: String, _ evidence: [String], _ message: String, absent: [String] = []) async throws -> Card {
            for _ in 0..<300 {
                if let shown = card(), shown.kind == kind, shown.token == pane.guidanceToken, pane.guidanceFingerprint != nil,
                   evidence.allSatisfy(shown.text.contains), !absent.contains(where: shown.text.contains) { return shown }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ChatGPTTutor.Failure(message: message + ": " + (card()?.text.debugDescription ?? "no card"))
        }
        // Windows ClickWorksheetAction: the live card's button, clicked as the user would.
        func click(_ choice: String) throws {
            guard let button: WorksheetAIChoiceButton = control("worksheet-ai-card-" + choice, in: pane.view),
                  !button.isHiddenOrHasHiddenAncestor, button.token == pane.guidanceToken else {
                throw ChatGPTTutor.Failure(message: "The card shows no live \(choice) button")
            }
            button.performClick(nil)
        }
        func feedback(_ text: String, _ message: String) async throws {
            try await wait(message + ": " + label("worksheet-ai-distribution-feedback").debugDescription) {
                label("worksheet-ai-distribution-feedback") == text
            }
        }
        // The offer of a method chosen on a card: its confirmation and the card's check and advice beneath it.
        func offered(_ title: String) async throws -> String {
            var shown = ""
            for _ in 0..<300 {
                if pane.offer?.methodTitle == title {
                    shown = label("worksheet-ai-confirmation") + "\n" + label("worksheet-ai-offer-details")
                    if shown.hasPrefix(title) { return shown }
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ChatGPTTutor.Failure(message: "The \(title) offer did not appear: offer \(pane.offer?.methodTitle ?? "none"), notice "
                                       + label("worksheet-ai-notice").debugDescription + ", card " + (card()?.text.debugDescription ?? "none"))
        }
        func button(_ title: String) -> NSButton? {
            views(NSButton.self, in: pane.view).first { $0.title == title && !$0.isHiddenOrHasHiddenAncestor }
        }
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
        let questionOnlyReceipt = await lastReceipt()
        try check(questionOnlyReceipt.none && questionOnlyReceipt.lines.isEmpty, "a reply that read no cells says so under it")

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
        try check(headings && (overviewRead?["titles"] as? [String]) == ["Score", "Qzheading"],
                  "the row-1 headings travel only as the titles of a bounded read")
        let overviewLines = await lastReceipt().lines
        try check(overviewLines == ["Fictional.xlsx · Parametric · A1:B1 (headings), A2:B3 (part of the worksheet’s used range)"],
                  "Data used lists the range read and the headings sent as titles: \(overviewLines)")
        let summary = try await pane.transcript.web.evaluateJavaScript("document.querySelector('article > details[data-receipt] > summary').textContent") as? String
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
        try await wait("The card's selection was not read") { pane.guidanceFingerprint != nil }
        // A click that arrives before the page reports a new selection, which it does once the selection settles.
        let earlyToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:1,y:1,width:1,height:2})")
        let early = await pane.answerClarification("means", token: earlyToken)
        let earlyTranscript = await text(pane)
        try check(!early && pane.clarification != nil && !pane.isBusy && !earlyTranscript.contains("I want to compare means."),
                  "a click delivered before the page reports a new selection is refused against the live grid")
        // Five areas read "A1,B1,C1,D1,…", so a change to the fifth leaves the caption, and the page, quiet.
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,4].map(x => ({x, y:0, width:1, height:1}))})")
        try await wait("The five-area selection was not shown") { pane.selectionLabel.stringValue == "Selection: Parametric!A1,B1,C1,D1,…" }
        try await wait("The card's selection was not read again") { pane.guidanceFingerprint != nil }
        let captionToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,5].map(x => ({x, y:0, width:1, height:1}))})")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == captionToken, "the page reports nothing for a change its short caption does not show")
        let hidden = await pane.answerClarification("means", token: captionToken)
        try check(!hidden && pane.clarification != nil && !pane.isBusy, "a click after a change the caption does not show is refused against the live grid")
        // Sparse whole rows: 2, 3, 6 and 2, 4, 6 share the caption "2:6 (some rows)" but not the fingerprint.
        try await grid(first, "statsDirectGrid.selectRows([[1,3],[5,6]])")
        try await wait("The sparse rows were not shown") { pane.selectionLabel.stringValue == "Selection: Parametric!2:6 (some rows)" }
        try await wait("The card's selection was not read for the sparse rows") { pane.guidanceFingerprint != nil }
        let rowsToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectRows([[1,2],[3,4],[5,6]])")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == rowsToken, "the page reports nothing when sparse rows change under the same caption")
        let sparse = await pane.answerClarification("means", token: rowsToken)
        try check(!sparse && pane.clarification != nil, "a click after sparse rows changed under the same caption is refused against the live grid")
        // The header-row setting changes what a read sends without advancing any revision. The page reports it, as a
        // distribution card must be read again, and the live grid would refuse the click anyway.
        try await wait("The card's selection was not read after the sparse-row refusal") { pane.guidanceFingerprint != nil }
        let headerToken = pane.guidanceToken
        try await grid(first, "document.querySelector('.worksheet-options input[type=checkbox]').click()")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken != headerToken, "the page reports a change of the header-row setting, which draws the card again")
        let afterToggle = await pane.answerClarification("means", token: headerToken)
        try check(!afterToggle && pane.clarification != nil, "a click after the header-row setting changed is refused against the live grid")
        try await grid(first, "document.querySelector('.worksheet-options input[type=checkbox]').click()")
        let headerRestored = try await first.web.evaluateJavaScript("document.querySelector('.worksheet-options input[type=checkbox]').checked") as? Bool
        try check(headerRestored == true, "the header-row setting is back on for the reads that follow")
        let staleToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:1,width:1,height:3})")
        try await wait("A selection change did not retire the card's token") { pane.guidanceToken != staleToken }
        let afterSelection = await pane.answerClarification("means", token: staleToken)
        try check(!afterSelection && pane.clarification != nil && !pane.isBusy,
                  "a late click on the card drawn before the selection changed is refused")
        let editToken = pane.guidanceToken, beforeEdit = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:2,row:4,text:'5'})")
        try await wait("An edit did not retire the card's token") { first.gridVersion > beforeEdit && pane.guidanceToken != editToken }
        let afterEdit = await pane.answerClarification("means", token: editToken)
        try check(!afterEdit && pane.clarification != nil, "a late click on the card drawn before an edit is refused")
        try await wait("The card's selection was not read after the edit") { pane.guidanceFingerprint != nil }
        // Keyboard focus on an answer stays on it when the card is drawn again. Buttons take focus only with Full
        // Keyboard Access, so without it the check is reported and skipped.
        let focusTarget: NSButton? = control("worksheet-ai-choice-ordered", in: pane.view)
        if let focusTarget, viewer.window.makeFirstResponder(focusTarget), viewer.window.firstResponder === focusTarget {
            let focusToken = pane.guidanceToken
            try await grid(first, "statsDirectGrid.selectCells({x:2,y:2,width:1,height:1})")
            try await wait("A selection change did not draw the card again") { pane.guidanceToken != focusToken }
            let responder = viewer.window.firstResponder as? WorksheetAIChoiceButton
            try check(responder?.choice == "ordered" && responder?.token == pane.guidanceToken && responder !== focusTarget,
                      "keyboard focus stays on the same answer when the card is drawn again")
            try await wait("The card's selection was not read after the redraw") { pane.guidanceFingerprint != nil }
        } else {
            print("INFO: answer buttons do not take keyboard focus here (Full Keyboard Access is off); focus across a redraw not exercised")
        }
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
        let readLine = "Fictional.xlsx · Parametric · A1 (headings), A2 (part of the worksheet’s used range)"
        let stoppedLines = await lastReceipt().lines
        try check((await text(pane)).contains("[Reply stopped before any text.]") && stoppedLines == [readLine],
                  "a reply stopped after a read but before any text keeps its Data used receipt: \(stoppedLines)")
        try check(pane.input.string == "READ_STOP_A", "after Stop the question waits in the composer, as on Windows")

        // Stopped after a sent read and some streamed text: the partial text keeps the receipt.
        pane.input.string = "READ_TEXT_STOP_A"
        pane.send()
        try await wait("The fixture did not stream after its read") {
            guard exists("text-streamed") else { return false }
            return (await text(pane)).contains("Partial text after a read.")
        }
        pane.stop()
        try await wait("Stop did not end the streamed reply") { !pane.isBusy }
        let streamedLines = await lastReceipt().lines
        try check((await text(pane)).contains("[Reply stopped before completion.]") && streamedLines == [readLine],
                  "a reply stopped after a read and some text keeps its partial text and its receipt: \(streamedLines)")

        pane.input.string = "READ_FAIL_A"
        pane.send()
        try await wait("The failed reply did not end") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("[No reply was received.]")
        }
        let failedLines = await lastReceipt().lines
        try check(failedLines == [readLine] && pane.input.string == "READ_FAIL_A",
                  "a reply that fails after a read keeps its receipt and returns the question to the composer: \(failedLines)")
        pane.input.string = ""

        // Codex's boundary: two cells within the grid's character limit whose result exceeds the tutor's byte limit.
        let beforeBig = first.gridVersion
        _ = try await first.web.callAsyncJavaScript("""
            const cell = '\\\\'.repeat(20000);
            statsDirectGrid.setCellText({col:3,row:1,text:cell});
            statsDirectGrid.setCellText({col:3,row:2,text:cell});
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        try await wait("The large cells did not settle") { first.gridVersion >= beforeBig + 2 }
        pane.input.string = "READ_BIG_A"
        pane.send()
        try await wait("The refused read did not end its reply") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Big read refused.")
        }
        let big = await lastReceipt()
        try check(big.lines.isEmpty && big.none, "a read the tutor refuses as too large never appears in Data used: \(big.lines)")

        // A read that was sent, then one refused as too large, in one reply: only the first counts, in Data used and in
        // the R data that Open in R gives the reply's code.
        pane.input.string = "READ_MIX_A"
        pane.send()
        try await wait("The mixed reply did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Mixed reads.")
        }
        let mixed = await lastReceipt()
        try check(mixed.lines == [readLine], "after a sent read and a refused one, Data used lists only the sent read: \(mixed.lines)")
        _ = try await pane.transcript.web.evaluateJavaScript("""
            (() => { const rows = document.querySelectorAll('article.assistant'), last = rows[rows.length - 1];
              last.querySelector('details[data-r-block]').open = true; last.querySelector('[data-code=r]').click(); return true; })()
            """)
        try await wait("Open in R did not open the mixed reply's code") { viewer.active?.rConsolePane != nil && viewer.active !== first }
        let mixedReview = viewer.active!
        let mixedSource = mixedReview.rConsolePane?.sourceText ?? ""
        try check(mixedSource.contains("142741") && !mixedSource.contains(String(repeating: "\\", count: 100)),
                  "Open in R carries the sent read's values and none of the refused read's")
        viewer.remove(mixedReview)
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A after Open in R") { pane.workbookID == first.id }

        // A real heading that reads like the stand-in still counts (Codex's recheck); a blank one does not (the node
        // and receipt-rule checks).
        let beforeHeadings = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:2,row:0,text:'Column C'})")
        try await wait("The heading edit did not settle") { first.gridVersion > beforeHeadings }
        pane.input.string = "READ_PLACEHOLDER_A"
        pane.send()
        try await wait("The heading read did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Placeholder heading read.")
        }
        let placeholder = await lastReceipt().lines
        try check(placeholder == ["Fictional.xlsx · Parametric · C1 (headings), C2 (part of the worksheet’s used range)"],
                  "a heading that reads \"Column C\" is listed as sent: \(placeholder)")

        // The same boundary without a provider: a read waits until the tutor reports its result sent, as it does not
        // when Stop comes first or the result is refused.
        let direct = ScriptAIContext(viewer: viewer, script: nil, workbook: first, usesSessionConsent: false, worksheetAssist: true) { true }
        let held = try await direct.call("statsdirect_read_data", ["documentId": first.id, "columns": [0], "firstRow": 2, "lastRow": 2])
        try check(direct.reads.isEmpty && direct.rData.isEmpty,
                  "a read made but not reported sent adds neither a Data used line nor R data")
        direct.delivered("statsdirect_read_data", held)
        direct.delivered("statsdirect_read_data", held)
        direct.delivered("statsdirect_workspace", held)
        let heldID = held["datasetId"] as? String ?? "missing"
        try check(WorksheetAIRead.ranges(columns: [3, 0, 1], headingColumns: [0, 3], firstRow: 2, lastRow: 5)
                  == ["A1 (headings)", "D1 (headings)", "A2:B5", "D2:D5"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": true,
                                              "columns": [["index": 0, "title": "Before"], ["index": 2, "title": "Column C"]]],
                                             used: nil, headings: [0], workbook: "W.xlsx")?.ranges == ["A1 (headings)", "A2:A3", "C2:C3"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": true,
                                              "columns": [["index": 0, "title": "Before"], ["index": 2, "title": "Column C"]]],
                                             used: nil, headings: [0, 2], workbook: "W.xlsx")?.ranges == ["A1 (headings)", "C1 (headings)", "A2:A3", "C2:C3"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": false,
                                              "columns": [["index": 0, "title": "Column A"]]],
                                             used: nil, headings: [0], workbook: "W.xlsx")?.ranges == ["A2:A3"],
                  "receipts group adjacent columns and list the headings whose cells hold text, whatever their text")
        try check(direct.reads.map(\.line) == [readLine] && direct.rData.components(separatedBy: heldID).count == 2 && direct.rData.contains("142741"),
                  "once reported sent, the read joins Data used and the R data, once")

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
        let browse: NSButton? = control("worksheet-ai-choose-method", in: pane.view)
        try check((await text(pane)).contains("This workbook is empty.") && workbookHelp?.isHiddenOrHasHiddenAncestor == false
                  && browse?.isHiddenOrHasHiddenAncestor != false && !shown("worksheet-ai-help-choose"),
                  "an empty workbook offers the example workbook and the workbook Help instead of method guidance")
        try await grid(blank, "statsDirectGrid.setCellText({col:0,row:0,text:'7'})")
        try await wait("Data did not bring back the general choices") {
            let guide: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
            return guide?.isHiddenOrHasHiddenAncestor == false
        }
        let titled: NSButton? = control("worksheet-ai-help-choose", in: pane.view), chooser: NSButton? = control("worksheet-ai-choose-method", in: pane.view)
        try check(!(await text(pane)).contains("This workbook is empty.") && titled?.title == "Help me choose a method"
                  && chooser?.title == "Choose a method" && chooser?.isHiddenOrHasHiddenAncestor == false,
                  "a workbook with data offers Help me choose a method and Choose a method")
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

        // Windows 5.3.22's distribution decision cards (Windows pull requests 40 to 42): the study-design question and the
        // paired and independent interval cards, which the engine checks on this Mac. The texts are the Windows cards' and
        // tests' (W:tests/Learning/WorksheetAnalysis.cs); the engine's own test holds their numbers to R 4.6.1.
        var cells: [[String: Any]] = []
        func column(_ col: Int, _ heading: String, _ values: [String]) {
            cells.append(["col": col, "row": 0, "text": heading, "kind": "text"])
            for (row, text) in values.enumerated() {
                cells.append(["col": col, "row": row + 1, "text": text, "kind": Double(text) == nil ? "text" : "number"])
            }
        }
        func texts(_ values: [Int]) -> [String] { values.map(String.init) }
        let spread = Array(-5...5) + [1000]                        // Windows' D1:E13: one far-out difference in 12
        let symmetric = Array(repeating: -1, count: 25) + Array(repeating: 0, count: 51) + Array(repeating: 1, count: 25)
        func rate(_ middle: Int) -> [Int] {                        // one far-out difference in 1,000 or 1,001 pairs
            zip(-3...3, [16, 94, 234, middle, 234, 94, 16]).flatMap { Array(repeating: $0.0, count: $0.1) } + [8]
        }
        column(0, "Other Before", texts(spread.map { 20 + $0 })); column(1, "Other After", texts(spread.map { _ in 20 }))
        column(6, "Boundary before", texts((1...101).map { $0 + $0 % 5 }) + ["102"]); column(7, "Boundary after", texts(Array(1...101)))
        column(9, "Heavy before", texts(symmetric + [-4, 4])); column(10, "Heavy after", texts(Array(repeating: 0, count: 103)))
        column(12, "Outlier before", texts(symmetric + [30])); column(13, "Outlier after", texts(Array(repeating: 0, count: 102)))
        column(18, "Rate before", texts(rate(311))); column(19, "Rate after", texts(Array(repeating: 0, count: 1000)))
        column(21, "Rate before", texts(rate(312))); column(22, "Rate after", texts(Array(repeating: 0, count: 1001)))
        column(24, "Group X", texts(Array(2...8))); column(25, "Group Y", texts([1, 3, 5, 7]))
        column(27, "Large X", texts(Array(2...102))); column(28, "Large Y", texts(Array(stride(from: 1, through: 203, by: 2))))
        column(30, "Uneven X", texts(Array(2...102))); column(31, "Uneven Y", texts([1, 3, 5, 7]))
        column(36, "Big before", ["1e+308"]); column(37, "Big after", ["-1e+308"])
        column(39, "Text before", ["1", "2", "3", "abc", "5"]); column(40, "Text after", ["1", "1", "1", "1", "1"])
        for (row, pair) in zip([11, 14, 17, 22, 23], [10, 11, 15, 20, 19]).enumerated() {   // numbers in row 1 too
            cells += [["col": 42, "row": row, "text": String(pair.0), "kind": "number"], ["col": 43, "row": row, "text": String(pair.1), "kind": "number"]]
        }
        let cards = viewer.newDocument(kind: "grid", title: "Card checks", url: viewer.root.appendingPathComponent("Grid/index.html"))
        cards.workbookName = "Card checks.xlsx"
        cards.pendingWorkbook = ["name": "Card checks", "formulaCount": 0,
                                 "sheets": [["name": "Cards", "rows": 1100, "columns": 44, "headerRow": true, "cells": cells]]]
        try await wait("AI Assist did not follow the card workbook") {
            pane.workbookID == cards.id && cards.pendingWorkbook == nil && cards.aiWorksheet?.hasData == true
        }
        func select(_ doc: Document, _ script: String, _ caption: String) async throws {
            try await grid(doc, "statsDirectGrid." + script)
            try await wait("The selection label did not show " + caption) { pane.selectionLabel.stringValue == caption }
        }
        let checkbox = "document.querySelector('.worksheet-options input[type=checkbox]').click()"
        let unpaired = "Select two adjacent, visible columns of matched measurements in one worksheet range."
        let chooseLine = "Were these measurements taken from the same people or units?"
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)

        // The tool without a design: Windows' study-design question, then Same people or units checks the selection at once.
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        pane.input.string = "DESIGN_A"
        pane.send()
        let design = try await waitCard("choose", [chooseLine], "The study-design question did not appear")
        try check(design.choices == ["paired", "independent"] && design.titles == ["Same people or units", "Separate groups"]
                  && pane.clarification == nil && pane.guidance.accessibilityLabel() == "Study design" && !shown("worksheet-ai-help-choose"),
                  "the tool without a design shows Windows' study-design question in place of the general choices")
        let designReceipt = await lastReceipt()
        try check(designReceipt.none && designReceipt.lines.isEmpty, "offering a card reads no cells, and the reply says so")
        let quiet = dataTraffic()
        try click("paired")
        let four = try await waitCard("paired-interval", ["Local check found 4 complete pairs. Shapiro–Wilk W = 0.9929, P = 0.9719.", "Suggested branch"],
                                      "Same people or units did not check Y1:Z8 as pairs")
        try check(four.titles == ["Large sample (more than 100 complete pairs)", "Suggested · Small or medium · Approximately normal differences",
                                  "Non-normal differences", "Change design"] && four.token != design.token
                  && pane.guidance.accessibilityLabel() == "Paired interval measurements" && dataTraffic() == quiet,
                  "Same people or units checks the selection on this Mac at once, suggests a branch and sends nothing")

        // Stale clicks (Windows' WorksheetAnalysis.cs:432-448): a selection change before the page reports it, then an edit.
        try await grid(cards, "statsDirectGrid.selectCells({x:0,y:0,width:2,height:13})")
        let earlyBranch = await pane.answerCard("normal", token: four.token)
        try check(!earlyBranch && pane.offer == nil, "a branch clicked before the page reports a new selection is refused against the live grid")
        // The page's report comes once the selection settles, and reads the card again too; an edit before it would put
        // the report off until after the edit.
        try await wait("The page did not report A1:B13") { pane.selectionLabel.stringValue == "Selection: Cards!A1:B13" }
        let twelve = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.3371, P = 1.396E-06.",
            "Review the differences\nThe box-plot check flagged an unusually distant difference. Review whether it reflects a data error or strongly affects the mean before choosing."],
            "A1:B13 was not checked")
        try check(twelve.token != four.token && !twelve.choices.contains("check") && !twelve.titles.contains { $0.hasPrefix("Suggested · ") },
                  "the card is read again for the new selection, so a stale click cannot skip its box-plot warning")
        let beforeCardEdit = cards.gridVersion
        try await grid(cards, "statsDirectGrid.setCellText({col:0,row:12,text:'26'})")
        try await wait("The edit did not retire the card's token") { cards.gridVersion > beforeCardEdit && pane.guidanceToken != twelve.token }
        let edited = await pane.answerCard("normal", token: twelve.token)
        let six = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757.",
                                                         "Suggested · Small or medium · Approximately normal differences"], "The edited pairs were not checked again")
        try check(!edited && six.token != twelve.token, "an edit checks the selection again, and a click on the card drawn before it is refused")

        // A branch offers its method with the card's check and Windows' advice; Change sample choice comes back to the card.
        try click("normal")
        let pairedOffer = try await offered("Paired Student t test")
        let sample: NSButton? = control("worksheet-ai-change-sample", in: pane.view)
        try check(pairedOffer.contains("Menu: Analysis › Parametric › Paired t") && pairedOffer.contains("Selection: A1:B13")
                  && pairedOffer.contains("Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757.\nThe paired t test addresses the mean difference. This branch assumes approximately normal differences.")
                  && card() == nil && sample?.title == "Change sample choice" && sample?.isHiddenOrHasHiddenAncestor == false,
                  "Small or medium offers the paired t test with the card's check and Windows' advice, in place of the card")
        sample?.performClick(nil)
        let returned = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."],
                                          "Change sample choice did not return to the card")
        try check(pane.offer == nil && returned.token != six.token, "Change sample choice returns to the card as it was, with a new token")

        // More than 100 pairs: the shape checks instead of Shapiro–Wilk; the size conflict; Wilcoxon still offered (PR 41).
        try await select(cards, "selectCells({x:6,y:0,width:2,height:103})", "Selection: Cards!G1:H103")
        let large = try await waitCard("paired-interval", ["Local check found 101 complete pairs\nShape check · 0 beyond the 3× IQR fences\nSkewness 0.0175 · Excess kurtosis -1.3",
            "Suggested branch\nThere are more than 100 complete pairs and the shape checks found no substantial departure. A paired t test answers the question about the mean difference."],
            "G1:H103 was not checked as 101 pairs")
        try check(large.titles == ["Suggested · Large sample (more than 100 complete pairs)", "Small or medium · Approximately normal differences",
                                   "Non-normal differences", "Change design"] && !large.text.contains("W ="),
                  "above 100 pairs the card gives Windows' shape checks without Shapiro–Wilk and suggests the large-sample branch")
        try click("normal")
        try await feedback("The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks.",
                           "Small or medium above 100 pairs gave no feedback")
        try check(pane.offer == nil && card()?.token == large.token, "a branch of the other size gets Windows' feedback on the card, which keeps its token")
        try click("non-normal")
        let wilcoxon = try await offered("Wilcoxon signed ranks test")
        try check(wilcoxon.contains("Menu: Analysis › Nonparametric › Wilcoxon Signed Ranks")
                  && wilcoxon.contains("The signed-rank test concerns a shift in location and assumes roughly symmetric differences. If the aim is specifically to estimate or test the mean difference, consider whether this answers your question."),
                  "Wilcoxon signed ranks stays available above 100 pairs, with Windows' advice")
        _ = await pane.changeSample()
        try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "Change sample choice did not return to the 101 pairs")
        try check(label("worksheet-ai-distribution-feedback").isEmpty, "the card comes back without its earlier feedback")
        try click("large")
        let largeOffer = try await offered("Paired Student t test")
        try check(largeOffer.contains("The large-sample branch recommends the paired t test for the mean difference."),
                  "the large-sample branch offers the paired t test with Windows' advice")
        _ = await pane.changeSample()
        try await select(cards, "selectCells({x:6,y:0,width:2,height:101})", "Selection: Cards!G1:H101")
        try await waitCard("paired-interval", ["Local check found 100 complete pairs. Shapiro–Wilk W = 0.8876, P = 3.853E-07.",
            "Suggested branch\nShapiro–Wilk found evidence of non-normal differences. Consider Wilcoxon signed-rank if the differences look roughly symmetric and a shift in location answers your question.",
            "Suggested · Non-normal differences"], "G1:H101 was not checked as 100 pairs")
        try check(true, "at exactly 100 pairs Shapiro–Wilk still decides, and suggests the non-normal branch")

        // In the narrowest dock the split allows (its delegate, HelpPane, stops the divider 340 points from the right edge),
        // the card's widest title is wider than the pane's content: it wraps within the pane instead of widening it.
        let split = viewer.workspaceSplit, dock = pane.view.frame.width
        split.setPosition(split.bounds.width - 300 - split.dividerThickness, ofDividerAt: 0)
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        let cardButtons = views(WorksheetAIChoiceButton.self, in: pane.view)
        let widest = cardButtons.map { $0.cell?.cellSize.width ?? 0 }.max() ?? 0
        let fitted = cardButtons.allSatisfy { button in
            let frame = pane.view.convert(button.bounds, from: button)
            let title = button.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: button.frame.width, height: 10_000)).height ?? .infinity
            return frame.minX >= -0.5 && frame.maxX <= pane.view.bounds.width + 0.5 && button.frame.height >= title - 0.5
        }
        let paragraphs = views(NSTextField.self, in: control("worksheet-ai-distribution", in: pane.view) ?? NSView()).allSatisfy { field in
            (field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: 10_000)).height ?? .infinity) <= field.frame.height + 0.5
        }
        let measured = cardButtons.map { button in
            "\(button.choice) \(pane.view.convert(button.bounds, from: button)) title \(button.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: button.frame.width, height: 10_000)) ?? .zero)"
        }
        let narrow = cardButtons.count == 4 && pane.view.frame.width < dock && pane.view.frame.width - 20 < widest && fitted && paragraphs
        try check(narrow, "in the narrowest dock the card's titles and text wrap within the pane instead of widening it"
                  + (narrow ? "" : " (pane \(pane.view.frame.width), widest title \(widest), fitted \(fitted), paragraphs \(paragraphs): \(measured))"))
        split.setPosition(split.bounds.width - dock - split.dividerThickness, ofDividerAt: 0)
        viewer.window.contentView?.layoutSubtreeIfNeeded()

        // Heavy tails, and a far-out difference with skew: no branch suggested, and Wilcoxon still offered.
        try await select(cards, "selectCells({x:9,y:0,width:2,height:104})", "Selection: Cards!J1:K104")
        let heavy = try await waitCard("paired-interval", ["Local check found 103 complete pairs\nShape check · 0 beyond the 3× IQR fences\nSkewness 0 · Excess kurtosis 5.61",
            "Review the differences\nThe shape checks flagged heavy tails. Consider Wilcoxon signed ranks for a shift in location if the differences look roughly symmetric. A paired t test still answers the question about the mean difference. Review any influential differences before choosing."],
            "J1:K104 was not checked")
        try check(!heavy.titles.contains { $0.hasPrefix("Suggested · ") }, "heavy tails above 100 pairs suggest no branch")
        // Keyboard focus on a choice stays on it when the card is read and drawn again. Buttons take focus only with
        // Full Keyboard Access, so without it the check is reported and skipped.
        let cardFocus: WorksheetAIChoiceButton? = control("worksheet-ai-card-non-normal", in: pane.view)
        let focusable = cardFocus.map { viewer.window.makeFirstResponder($0) && viewer.window.firstResponder === $0 } ?? false
        try await select(cards, "selectCells({x:12,y:0,width:2,height:103})", "Selection: Cards!M1:N103")
        try await waitCard("paired-interval", ["Local check found 102 complete pairs\nShape check · 1 beyond the 3× IQR fences\nSkewness 9.15 · Excess kurtosis 86.7",
            "The shape checks flagged far-out differences, pronounced skew, heavy tails. Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful. A paired t test still answers the question about the mean difference. Review any influential differences before choosing."],
            "M1:N103 was not checked")
        if focusable {
            let responder = viewer.window.firstResponder as? WorksheetAIChoiceButton
            try check(responder?.choice == "non-normal" && responder?.token == pane.guidanceToken && responder !== cardFocus,
                      "keyboard focus stays on the same choice when the card is read and drawn again")
        } else {
            print("INFO: card buttons do not take keyboard focus here (Full Keyboard Access is off); focus across a redraw not exercised")
        }
        try click("non-normal")
        _ = try await offered("Wilcoxon signed ranks test")
        _ = await pane.changeSample()
        try check(true, "a far-out difference with skew and heavy tails still leaves Wilcoxon signed ranks to choose")
        try await select(cards, "selectCells({x:18,y:0,width:2,height:1001})", "Selection: Cards!S1:T1001")
        try await waitCard("paired-interval", ["Local check found 1000 complete pairs\nShape check · 1 beyond the 3× IQR fences\nSkewness 0.241 · Excess kurtosis 1.11",
                                               "The shape checks flagged far-out differences. Consider Wilcoxon signed ranks"], "S1:T1001 was not checked")
        try await select(cards, "selectCells({x:21,y:0,width:2,height:1002})", "Selection: Cards!V1:W1002")
        try await waitCard("paired-interval", ["Local check found 1001 complete pairs\nShape check · 1 beyond the 3× IQR fences",
                                               "Suggested · Large sample (more than 100 complete pairs)"], "V1:W1002 was not checked")
        try check(true, "one far-out difference flags 1,000 pairs but not 1,001 (Windows' 0.1% rule)")

        // "First row has column names" decides whether row 1 is checked, as it does for the analysis; a heading read as
        // data is refused as the analysis would refuse it, naming the cell and the setting.
        try await select(cards, "selectCells({x:42,y:0,width:2,height:5})", "Selection: Cards!AQ1:AR5")
        let headed = try await waitCard("paired-interval", ["Local check found 4 complete pairs. Shapiro–Wilk W = 0.8634, P = 0.2725."], "AQ1:AR5 was not checked without row 1")
        try await grid(cards, checkbox)
        let toggled = await pane.answerCard("normal", token: headed.token)
        try await waitCard("paired-interval", ["Local check found 5 complete pairs. Shapiro–Wilk W = 0.9609, P = 0.814."], "Row 1 was not checked with the setting off")
        try check(!toggled, "turning off First row has column names checks row 1 too, and a click on the card drawn before is refused")
        try await select(cards, "selectCells({x:0,y:0,width:2,height:13})", "Selection: Cards!A1:B13")
        try await waitCard("paired-interval", ["How many complete pairs are there?\nHow are the within-pair differences distributed?\nLook at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive.",
                                               "Check selected pairs"], "A heading read as data did not leave the card unread")
        try click("check")
        try await feedback("Cell A1: ‘Other Before’ is not numeric. Correct it or use * for a missing value. If row 1 holds column names, tick “First row has column names”.",
                           "Check did not name the heading cell")
        try check(card()?.choices.first == "check", "Check refuses a heading read as data, naming the cell and the setting, and stays offered")
        let beforeHeader = dataTraffic()
        try await grid(cards, checkbox)
        try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."], "Ticking the setting did not check the pairs")
        try check(label("worksheet-ai-distribution-feedback").isEmpty && dataTraffic() == beforeHeader,
                  "ticking the setting checks the pairs again on this Mac, without the feedback, and sends nothing")

        // Selections that cannot be read leave the card unread; Check gives Windows' text, which each new selection clears.
        for (script, caption) in [("selectCells({x:0,y:0,width:1,height:1})", "Current cell: Cards!A1"),
                                  ("selectCells({x:0,y:0,width:3,height:13})", "Selection: Cards!A1:C13"),
                                  ("selectCells({x:0,y:0,width:1,height:13,stack:[{x:1,y:0,width:1,height:13}]})", "Selection: Cards!A1:A13,B1:B13"),
                                  ("selectRows([[0,13]])", "Selection: Cards!1:13")] {
            try await select(cards, script, caption)
            try await waitCard("paired-interval", ["How many complete pairs are there?", "Check selected pairs"], caption + " did not leave the card unread",
                               absent: [unpaired])
            try click("check")
            try await feedback(unpaired, caption + " was not refused")
        }
        try check(true, "a single cell, three columns, two areas and whole rows are refused with Windows' text, which each new selection clears")
        try await select(cards, "selectCells({x:36,y:0,width:2,height:2})", "Selection: Cards!AK1:AL2")
        try await waitCard("paired-interval", ["How many complete pairs are there?"], "AK1:AL2 did not leave the card unread", absent: [unpaired])
        try click("check")
        try await feedback("A paired difference is too large to check. Rescale the measurements and try again.", "The overflow was not refused")
        try await select(cards, "selectCells({x:39,y:0,width:2,height:6})", "Selection: Cards!AN1:AO6")
        try await waitCard("paired-interval", ["How many complete pairs are there?"], "AN1:AO6 did not leave the card unread", absent: ["too large"])
        try click("check")
        try await feedback("Cell AN5: ‘abc’ is not numeric. Correct it or use * for a missing value.", "Text in a pair was not refused")
        try check(true, "Check refuses a difference too large to check and text in a pair, with the cell named, as the analysis would")
        // Five areas read "A1,B1,C1,D1,…", so a change to the fifth leaves the caption, and the page, quiet.
        try await select(cards, "selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,4].map(x => ({x, y:0, width:1, height:1}))})", "Selection: Cards!A1,B1,C1,D1,…")
        let areas = try await waitCard("paired-interval", ["How many complete pairs are there?"], "Five areas did not leave the card unread", absent: ["Cell AN5"])
        try await grid(cards, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,5].map(x => ({x, y:0, width:1, height:1}))})")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == areas.token, "the page reports nothing for a change its short caption does not show")
        let unseen = await pane.answerCard("check", token: areas.token)
        try check(!unseen && pane.guidanceToken != areas.token, "a click after a change the caption does not show is refused against the live grid, and the card is read again")

        // Change design, and the independent card: counts first, then Windows' confirmation of separate samples.
        try await waitCard("paired-interval", ["Change design"], "The card was not read again after the refused click")
        try click("back")
        let chosen = try await waitCard("choose", [chooseLine], "Change design did not return to the study-design question")
        try check(!chosen.text.contains("How many complete pairs"), "Change design returns to the study-design question without the evidence")
        try click("independent")
        try await waitCard("independent-interval", ["How many observations are there in each group?\nHow are the observations distributed within each group?", "Check two sample columns"],
                           "Separate groups did not give the unread independent card")
        try click("check")
        try await feedback("Select the two adjacent, visible sample columns in one worksheet range.", "The independent Check was not refused")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        let counts = try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:\nColumn 1: n = 7. Shapiro–Wilk W = 0.978, P = 0.9493.\nColumn 2: n = 4. Shapiro–Wilk W = 0.9929, P = 0.9719.\nHow are the observations distributed within each group?\nLook at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive."],
                                        "Y1:Z8 was not counted as two samples")
        try check(counts.choices == ["check", "large", "normal", "non-normal", "back"]
                  && counts.titles == ["Use these as separate samples", "Large samples (more than 100 in each group)", "Small or medium · Approximately normal within groups",
                                       "Non-normal distributions within groups", "Change design"]
                  && pane.guidance.accessibilityLabel() == "Independent interval measurements",
                  "the independent card counts each column and asks to use them as separate samples")
        try click("check")
        let separate = try await waitCard("independent-interval", ["Column 1: n = 7. Shapiro–Wilk W = 0.978, P = 0.9493."], "Use these as separate samples did not confirm them",
                                          absent: ["Selected columns, if they hold"])
        try check(!separate.choices.contains("check") && separate.token != counts.token, "Use these as separate samples confirms the counts, with a new token")
        try click("large")
        try await feedback("The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.",
                           "Large samples at 7 and 4 gave no feedback")
        try click("non-normal")
        let mannWhitney = try await offered("Mann-Whitney U (two-sample Wilcoxon) test")
        try check(mannWhitney.contains("Menu: Analysis › Nonparametric › Mann-Whitney")
                  && mannWhitney.contains("Mann–Whitney compares relative ordering between groups. Use that question to decide whether it fits your goal."),
                  "the non-normal branch offers Mann–Whitney with Windows' advice")
        _ = await pane.changeSample()
        let kept = try await waitCard("independent-interval", ["Column 1: n = 7"], "Change sample choice did not return to the samples", absent: ["Selected columns, if they hold"])
        try check(!kept.choices.contains("check"), "Change sample choice keeps the confirmation of separate samples while the selection is unchanged")
        try await select(cards, "selectCells({x:0,y:0,width:1,height:1})", "Current cell: Cards!A1")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:", "Use these as separate samples"],
                           "A new selection did not ask again whether the columns are separate samples")
        try check(true, "a new selection asks again whether the columns hold separate samples")
        try await select(cards, "selectCells({x:27,y:0,width:2,height:103})", "Selection: Cards!AB1:AC103")
        pane.input.string = "INDEPENDENT_A"
        pane.send()
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 102", "Use these as separate samples"], "The tool did not stage the independent card for AB1:AC103")
        let independentReply = await text(pane)
        try check(independentReply.contains("Check the independent card below.") && pane.clarification == nil,
                  "the tool with design independent stages the independent card, which counts the selection when the reply completes")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 102"], "AB1:AC103 was not confirmed", absent: ["Selected columns, if they hold"])
        try click("normal")
        try await feedback("The local check found more than 100 observations in each sample. Review their distributions before choosing a method.",
                           "Small or medium at 101 and 102 gave no feedback")
        try click("large")
        let zTest = try await offered("Unpaired two-sample z(normal distribution) test")
        try check(zTest.contains("Menu: Analysis › Parametric › Unpaired z")
                  && zTest.contains("The Help routes large, well-behaved samples to the two-sample Z test for the difference in means."),
                  "more than 100 in each sample offers the z test with Windows' advice")
        _ = await pane.changeSample()
        try await select(cards, "selectCells({x:30,y:0,width:2,height:102})", "Selection: Cards!AE1:AF102")
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 4. Shapiro–Wilk W = 0.9929, P = 0.9719."], "AE1:AF102 was not counted")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 101"], "AE1:AF102 was not confirmed", absent: ["Selected columns, if they hold"])
        try click("large")
        try await feedback("The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.",
                           "Large samples at 101 and 4 gave no feedback")
        try check(true, "the large-sample branch needs more than 100 in each sample")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        try await waitCard("independent-interval", ["Use these as separate samples"], "Y1:Z8 was not counted again")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 7"], "Y1:Z8 was not confirmed again", absent: ["Selected columns, if they hold"])
        try click("normal")
        let unpairedT = try await offered("Unpaired Student t test")
        try check(unpairedT.contains("Menu: Analysis › Parametric › Unpaired t")
                  && unpairedT.contains("The unpaired t test compares means. Consider the spread in each group before using an equal-variance result."),
                  "Small or medium offers the unpaired t test with Windows' advice")
        button("Cancel")?.performClick(nil)
        try await wait("Cancel did not return to the general choices") { pane.offer == nil && shown("worksheet-ai-help-choose") }
        try check(pane.distribution == nil && card() == nil, "Cancel dismisses the offer and the card it came from")

        // A design, with Windows' validation and one staged card a reply; then a method that is not available.
        try await select(cards, "selectCells({x:0,y:0,width:2,height:13})", "Selection: Cards!A1:B13")
        pane.input.string = "PAIRED_A"
        pane.send()
        try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."], "The paired card was not staged and checked")
        let pairedReply = await text(pane)
        try check(pane.clarification == nil && pairedReply.contains("Check the paired card below."),
                  "the tool refuses a bad design, an extra argument and a second card, and stages one paired card")
        guard let unavailable = viewer.worksheetCommands.firstIndex(where: { $0.id == "Wilcoxon" }) else {
            throw ChatGPTTutor.Failure(message: "Wilcoxon is not in the Analyse catalogue")
        }
        viewer.worksheetCommands[unavailable].disabled = true
        try click("non-normal")
        try await wait("An unavailable method did not clear the card") {
            pane.distribution == nil && label("worksheet-ai-notice") == "That method is unavailable. Choose another method in Analyse."
        }
        viewer.worksheetCommands[unavailable].disabled = false
        try check(pane.offer == nil, "a branch whose method is unavailable clears the card with Windows' text")
        pane.input.string = "CLARIFY_THEN_CARD_A"
        pane.send()
        try await wait("The clarifying question did not appear") { !pane.isBusy && pane.clarification != nil }
        try check(pane.distribution == nil && card() == nil, "after a clarifying question, the reply's card tool is refused: one card a reply")

        // Hidden while a reply runs; read when it completes, not when it was staged; dropped by Stop and by a new send.
        pane.input.string = "HOLD_CARD_A"
        pane.send()
        try await wait("The card reply did not stage its card") {
            guard exists("card-staged") else { return false }
            return (await text(pane)).contains("Card staged; reply still running.")
        }
        try check(pane.isBusy && card() == nil && !shown("worksheet-ai-help-choose"), "no card or choices show while the reply runs")
        try await grid(cards, "statsDirectGrid.selectCells({x:6,y:0,width:2,height:103})")
        try await wait("The selection label did not follow during the reply") { pane.selectionLabel.stringValue == "Selection: Cards!G1:H103" }
        try Data().write(to: storage.appendingPathComponent("card-release"))
        try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "The completed reply's card was not read")
        try check(!pane.isBusy, "the card staged during a reply is read when the reply completes")
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        try check(card()?.kind == "paired-interval" && pane.share.state == .off, "changing the sharing options keeps the card, which sends nothing")
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        let rowsBeforeHold = await assistantRows(), holds = requestLines().filter { $0.contains("HOLD_A") }.count
        pane.input.string = "HOLD_A"
        pane.send()
        try check(card() == nil, "a new question hides the card at once")
        try await wait("The held question did not reach the fixture") { requestLines().filter { $0.contains("HOLD_A") }.count > holds }
        pane.stop()
        try await wait("Stop did not end the held reply") { !pane.isBusy }
        let rowsAfterHold = await assistantRows()
        try check(pane.distribution == nil && card() == nil && rowsAfterHold == rowsBeforeHold, "after Stop the card does not come back")
        pane.input.string = "STOP_CARD_A"
        pane.send()
        try await wait("The card reply did not stream before Stop") {
            guard exists("stop-card-staged") else { return false }
            return (await text(pane)).contains("Card staged before Stop.")
        }
        pane.stop()
        try await wait("Stop did not end the card reply") { !pane.isBusy && shown("worksheet-ai-help-choose") }
        let stoppedCard = await text(pane)
        try check(pane.distribution == nil && stoppedCard.contains("[Reply stopped before completion.]"), "a card staged by a stopped reply is dropped")

        // The card never travels: no card wording in any request, and no card choice in the conversation (Windows :120-126).
        pane.input.string = "AFTER_CARD_A"
        pane.send()
        try await wait("The follow-up did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Follow-up without the card.")
        }
        let cardLog = requestLines().joined(separator: "\n")
        try check(!["Local check found", "Suggested branch", "Review the differences", "Shape check ·", "Suggested · ", "Use these as separate samples",
                    "Change sample choice", "is not numeric"].contains(where: cardLog.contains),
                  "no request carries a card's wording, and the follow-up's conversation holds no card choice")

        // A new conversation, hiding the dock and switching workbook each retire the card.
        for retire in ["New conversation", "Close", "workbook"] {
            pane.input.string = "DESIGN_A"
            pane.send()
            try await waitCard("choose", [chooseLine], "The study-design question did not appear before " + retire)
            switch retire {
            case "New conversation": button("New conversation")?.performClick(nil)
            case "Close":
                pane.hide()
                try await toolbar(cards, "worksheetAI")
                try await wait("AI Assist did not reopen on the card workbook") { pane.visible && pane.workbookID == cards.id }
            default:
                viewer.tabs.selectTabViewItem(first.item)
                try await wait("AI Assist did not follow workbook A") { pane.workbookID == first.id }
                viewer.tabs.selectTabViewItem(cards.item)
                try await wait("AI Assist did not return to the card workbook") { pane.workbookID == cards.id }
            }
            try check(pane.distribution == nil && card() == nil, retire == "workbook" ? "switching workbook retires the card" : retire + " retires the card")
        }

        // The card is offered only with the workbook in front (Windows: the grid must be the active window).
        viewer.tabs.selectTabViewItem(report.item)
        pane.input.string = "NO_CARD_A"
        pane.send()
        try await wait("The shared question without the workbook in front did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("No card offered.")
        }
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        pane.input.string = "NO_CARD_QO"
        pane.send()
        try await wait("The question-only question without the workbook in front did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).components(separatedBy: "No card offered.").count == 3
        }
        try check(pane.workbookID == cards.id, "with another document in front, neither mode offers the card's tool")

        // Question only (Windows guidance-only): the card's tool alone, completed on this Mac, and nothing about the
        // workbook in any request. The PEFR values of the example workbook, shifted, under private names.
        var privateCells: [[String: Any]] = [["col": 0, "row": 0, "text": "Qzbefore", "kind": "text"], ["col": 1, "row": 0, "text": "Qzafter", "kind": "text"]]
        for (row, pair) in zip([312, 242, 340, 388, 296, 254, 391, 402, 290], [300, 201, 232, 312, 220, 256, 328, 330, 231]).enumerated() {
            privateCells += [["col": 0, "row": row + 1, "text": String(100_000 + pair.0), "kind": "number"],
                             ["col": 1, "row": row + 1, "text": String(100_000 + pair.1), "kind": "number"]]
        }
        let secret = ["QZPRIVATE_BOOK", "QZPRIVATE_SHEET", "Qzbefore", "Qzafter", "100312", "100300", "Local check found", "W = 0.9393"]
        try JSONSerialization.data(withJSONObject: secret).write(to: storage.appendingPathComponent("private.json"))
        let qz = viewer.newDocument(kind: "grid", title: "QZPRIVATE_BOOK", url: viewer.root.appendingPathComponent("Grid/index.html"))
        qz.workbookName = "QZPRIVATE_BOOK.xlsx"
        qz.pendingWorkbook = ["name": "QZPRIVATE_BOOK", "formulaCount": 0,
                              "sheets": [["name": "QZPRIVATE_SHEET", "rows": 100, "columns": 8, "headerRow": true, "cells": privateCells]]]
        try await wait("AI Assist did not follow the private workbook") {
            pane.workbookID == qz.id && qz.pendingWorkbook == nil && qz.aiWorksheet?.hasData == true
        }
        try await select(qz, "selectColumns([[0,2]])", "Selection: QZPRIVATE_SHEET!A:B")
        let start = requestLines().count
        pane.input.string = "PAIRED_QO"
        pane.send()
        let local = try await waitCard("paired-interval", ["Local check found 9 complete pairs. Shapiro–Wilk W = 0.9393, P = 0.5746.",
            "Suggested branch\nA paired t test answers the question about the mean difference. Shapiro–Wilk found no clear departure from normality, and the shape checks flagged no unusual differences. With this sample, those checks provide limited evidence."],
            "The question-only card did not check the whole columns")
        let localReply = await text(pane)
        try check(local.titles == ["Large sample (more than 100 complete pairs)", "Suggested · Small or medium · Approximately normal differences",
                                   "Non-normal differences", "Change design"] && localReply.contains("Decision card offered without workbook data."),
                  "question only offers exactly the card's tool, masks its refusals, and the card checks whole columns A:B to their last values")
        let quietQuestion = dataTraffic()
        try click("large")
        try await feedback("The local check found at most 100 complete pairs. Choose the branch for the distribution of the differences.", "Large sample at 9 pairs gave no feedback")
        try click("normal")
        let questionOffer = try await offered("Paired Student t test")
        try check(questionOffer.contains("Selection: Columns A:B")
                  && questionOffer.contains("The paired t test addresses the mean difference. This branch assumes approximately normal differences."),
                  "in question-only mode a branch offers its method on this Mac")
        _ = await pane.changeSample()
        try await waitCard("paired-interval", ["Local check found 9 complete pairs."], "Change sample choice did not return in question-only mode")
        try click("back")
        try await waitCard("choose", [chooseLine], "Change design did not work in question-only mode")
        try click("independent")
        try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:\nColumn 1: n = 9. Shapiro–Wilk W = 0.919, P = 0.3843.\nColumn 2: n = 9. Shapiro–Wilk W = 0.8906, P = 0.2023."],
                           "Separate groups did not count the private columns")
        try click("check")
        try await waitCard("independent-interval", ["Column 2: n = 9. Shapiro–Wilk W = 0.8906, P = 0.2023."], "Use these as separate samples did not work in question-only mode",
                           absent: ["Selected columns, if they hold"])
        try click("back")
        try await waitCard("choose", [chooseLine], "Change design did not return again")
        try click("paired")
        try await waitCard("paired-interval", ["Local check found 9 complete pairs."], "Same people or units did not check the private pairs again")
        try click("non-normal")
        _ = try await offered("Wilcoxon signed ranks test")
        let documents = viewer.documents.count
        pane.continueAnalysis()
        try await wait("Continue did not open Wilcoxon signed ranks") { viewer.documents.count == documents + 1 && viewer.active?.kind == "operation" }
        let operation = viewer.active!
        try check(operation.operationName == "Wilcoxon" && operation.operationSourceID == qz.id && pane.offer == nil && pane.distribution == nil
                  && dataTraffic() == quietQuestion,
                  "Continue opens the chosen method for the private workbook on this Mac, retires the card and sends nothing")
        viewer.remove(operation)
        let questionLog = requestLines()[start...].joined(separator: "\n")
        try check(!secret.contains(where: questionLog.contains), "no question-only request carries the workbook, its sheet, headings, cells or the card's wording")

        // The example workbook's PEFR columns, whole (Windows' A:B case): nine pairs, as Windows and R give them.
        guard let example = viewer.documents.last(where: { $0.kind == "grid" && $0.workbookName == "test.xlsx" }) else {
            throw ChatGPTTutor.Failure(message: "The example workbook is not open")
        }
        try JSONSerialization.data(withJSONObject: ["PEFR Before", "PEFR After", "test.xlsx", "Local check found"]).write(to: storage.appendingPathComponent("private.json"))
        viewer.tabs.selectTabViewItem(example.item)
        try await wait("AI Assist did not follow the example workbook") { pane.workbookID == example.id }
        try await select(example, "selectColumns([[0,2]])", "Selection: Parametric!A:B")
        pane.input.string = "PAIRED_QO"
        pane.send()
        let pefr = try await waitCard("paired-interval", ["Local check found 9 complete pairs. Shapiro–Wilk W = 0.9393, P = 0.5746.",
                                                          "Suggested · Small or medium · Approximately normal differences"], "The example's PEFR columns were not checked")
        try check(!pefr.choices.contains("check"), "the example's PEFR columns A:B give Windows' 9 pairs, W = 0.9393 and P = 0.5746 (R 4.6.1: 0.939305, 0.574604)")

        // A policy that disables AI hides the card and refuses its clicks. Setting it can end the ChatGPT connection, so it comes last.
        UserDefaults.standard.set(true, forKey: "DisableOnlineTutor")
        pane.updateControls()
        let disabledClick = await pane.answerCard("normal", token: pefr.token)
        try check(card() == nil && !disabledClick, "a policy that disables AI hides the card and refuses its clicks")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
        try? FileManager.default.removeItem(at: storage.appendingPathComponent("private.json"))
        viewer.remove(qz)
        viewer.remove(cards)
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A after the card checks") { pane.workbookID == first.id }
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
