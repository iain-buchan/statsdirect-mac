import Cocoa
import WebKit

extension RConsoleIntegrationTests {
    /// Qualifies the production console's AI entry point and approved snapshots
    /// against a local protocol fixture. No real account or external AI is used.
    @MainActor static func consoleAIChecks(_ viewer: Viewer, _ doc: Document) async throws -> [URL] {
        guard let pane = doc.rConsolePane else {
            throw ChatGPTTutor.Failure(message: "The AI fixture requires the production R console")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageRoot = root.appendingPathComponent(".build/r-console-ai-" + UUID().uuidString)
        let storage = storageRoot.appendingPathComponent("chatgpt-mock")
        let originalProvider = viewer.chatGPTTutor
        let originalPolicy = UserDefaults.standard.object(forKey: "DisableOnlineTutor")
        let originalDataID = viewer.aiSharing.dataDocumentID
        let originalAnalysisSourceID = viewer.analysisSourceID
        let originalAccepted = viewer.aiSharing.accepted
        let originalApprovedIDs = Set(viewer.documents.filter {
            $0.kind == "grid" && viewer.aiSharing.accepts([$0.id])
        }.map(\.id))
        let originalShareDocument = viewer.aiSharing.shareDocument
        let originalShareWorkbook = viewer.aiSharing.shareWorkbook
        let originalDocumentIDs = Set(viewer.documents.map(\.id))
        let mock = ChatGPTTutor(executable: root.appendingPathComponent("Tests/mock-script-ai-server.py"),
                               storage: storage, resources: viewer.root.appendingPathComponent("Tutor"))
        let ai = viewer.scriptAI
        var createdDirectories: [URL] = []
        var completed = false
        defer {
            ai.hide()
            mock.changed = nil; mock.shutdown()
            viewer.chatGPTTutor = originalProvider
            for extra in viewer.documents.filter({ !originalDocumentIDs.contains($0.id) }) {
                let directory = extra.rConsolePane?.session.workingDirectory
                extra.rConsolePane?.shutdown(); extra.rPane?.shutdown(); viewer.remove(extra)
                if !completed, let directory { try? FileManager.default.removeItem(at: directory) }
            }
            viewer.tabs.selectTabViewItem(doc.item)
            viewer.analysisSourceID = originalAnalysisSourceID
            viewer.aiSharing.selectDataDocument(originalDataID)
            viewer.aiSharing.revoke()
            if originalAccepted { viewer.aiSharing.approve(originalApprovedIDs) }
            viewer.aiSharing.shareDocument = originalShareDocument
            viewer.aiSharing.shareWorkbook = originalShareWorkbook
            if let originalPolicy { UserDefaults.standard.set(originalPolicy, forKey: "DisableOnlineTutor") }
            else { UserDefaults.standard.removeObject(forKey: "DisableOnlineTutor") }
            try? FileManager.default.removeItem(at: storageRoot)
        }
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
        viewer.chatGPTTutor = mock
        mock.changed = { [weak viewer] in viewer?.scriptAI.updateConnection() }
        viewer.aiSharing.revoke()
        viewer.aiSharing.shareDocument = false; viewer.aiSharing.shareWorkbook = false

        func requests() -> [[String: Any]] {
            let lines = (try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? ""
            return lines.split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
        func turns() -> [[String: Any]] { requests().filter { $0["method"] as? String == "turn/start" } }
        func lastContext() throws -> [String: Any] {
            guard let params = turns().last?["params"] as? [String: Any],
                  let input = params["input"] as? [[String: Any]], let text = input.first?["text"] as? String,
                  let body = text.split(separator: "\n", maxSplits: 1).last,
                  let payload = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let reference = payload["referenceContext"] as? String,
                  let context = try JSONSerialization.jsonObject(with: Data(reference.utf8)) as? [String: Any] else {
                throw ChatGPTTutor.Failure(message: "The local console AI fixture recorded no valid reference context")
            }
            return context
        }
        func transcriptText() async -> String {
            (try? await ai.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
        }
        func setSource(_ source: String) async throws {
            _ = try await evaluate(doc, """
            (() => {const input=document.getElementById('script-source');
              input.value=\(try literal(source)); input.dispatchEvent(new Event('input',{bubbles:true})); return true;})()
            """)
            try await wait("console source reaching the native AI snapshot") { pane.sourceText == source }
        }

        try await makeConsoleVisible(viewer, doc)
        try await ready(doc)
        try await console(doc, "cat('AI_CONSOLE_CONTEXT_READY\\n')")
        try await expectOutput(doc, "AI_CONSOLE_CONTEXT_READY\n")
        let approvedSource = "before <- c(312,242,340,388,296,254,391,402,290)\nafter <- c(300,201,232,312,220,256,328,330,231)\nconsole_ai_must_not_execute <- TRUE"
        try await setSource(approvedSource)
        let approvedOutput = String(pane.outputText.suffix(8000))
        _ = try await evaluate(doc, "document.getElementById('ai').click(); true")
        try await wait("the production console AI toolbar opening its dock") { ai.visible && ai.scriptID == doc.id }
        try check(viewer.workspaceSplit.arrangedSubviews.count == 2 && ai.view.window === viewer.window,
                  "the production WebKit console AI button opens the dock beside its own script")
        try check(turns().isEmpty && !requests().contains { $0["method"] as? String == "thread/start" },
                  "opening console AI sends no question or document contents")

        _ = try await mock.signIn(); try await mock.refreshAccount(); ai.updateConnection()
        ai.input.string = "NO_SHARING"; ai.sendButton.performClick(nil)
        try await wait("question-only console AI reply") {
            let text = await transcriptText(); return !ai.isBusy && text.contains("General R guidance")
        }
        let questionOnly = try lastContext()
        try check((questionOnly["documents"] as? [Any])?.isEmpty == true && questionOnly["currentScript"] == nil,
                  "console AI question-only mode excludes the open script and all R output")

        ai.shareScript.state = .on; ai.shareWorkbook.state = .off; ai.sharingChanged()
        let countBeforeConfirmation = turns().count
        ai.input.string = "PEFR_CONTEXT"; ai.send()
        try check(!ai.isBusy && turns().count == countBeforeConfirmation && !ai.sendButton.isEnabled,
                  "console AI refuses source and output sharing before session confirmation")
        ai.acknowledgement.performClick(nil)
        try check(viewer.aiSharing.accepted && ai.contextPanel.isHidden && ai.sendButton.isEnabled,
                  "one session confirmation enables console sharing and collapses its controls")
        ai.sendButton.performClick(nil)
        try await wait("approved console AI code reply") {
            let text = await transcriptText(); return !ai.isBusy && text.contains("wilcox.test")
        }
        let shared = try lastContext(), snapshot = shared["currentScript"] as? [String: Any] ?? [:]
        let documents = shared["documents"] as? [[String: Any]] ?? []
        try check(documents.count == 1 && documents.first?["documentId"] as? String == doc.id
                  && snapshot["script"] as? String == approvedSource && snapshot["output"] as? String == approvedOutput
                  && approvedOutput.contains("AI_CONSOLE_CONTEXT_READY") && snapshot["snapshot"] as? Bool == true
                  && snapshot["running"] as? Bool == false,
                  "console AI receives only the approved fixed source and real R output with an idle status")

        try await setSource("before <- 999\nafter <- 1")
        ai.openCodeButton.performClick(nil)
        guard let suggestion = viewer.active, suggestion !== doc, let suggestionPane = suggestion.rConsolePane else {
            throw ChatGPTTutor.Failure(message: "Open in R did not create a production console suggestion")
        }
        try await makeConsoleVisible(viewer, suggestion)
        try await ready(suggestion)
        if let directory = suggestionPane.session.workingDirectory { createdDirectories.append(directory) }
        try check(suggestion.rPane == nil && suggestionPane.sourceText.contains(approvedSource)
                  && !suggestionPane.sourceText.contains("before <- 999")
                  && suggestionPane.sourceText.contains("d <- before - after") && suggestionPane.sourceText.contains("wilcox.test")
                  && suggestionPane.hasUnsavedChanges && !suggestionPane.hasWorkspace && !suggestionPane.isBusy
                  && !suggestionPane.outputText.contains("console_ai_must_not_execute"),
                  "Open in R preserves the approved console source and suggested blocks in an unsaved, unexecuted console")
        ai.open(suggestion)
        try check(viewer.aiSharing.accepted && ai.acknowledgement.state == .on && ai.contextPanel.isHidden,
                  "opening the suggestion AI dock reuses acceptance within the same data session")
        let report = viewer.newDocument(kind: "report", title: "Console AI consent fixture")
        ai.open(report)
        try check(viewer.aiSharing.accepted && ai.acknowledgement.state == .on && ai.contextPanel.isHidden,
                  "report and console AI reuse the same app-session sharing acceptance")
        _ = viewer.newDocument(kind: "grid", title: "New console AI data boundary",
                               url: viewer.root.appendingPathComponent("Grid/index.html"))
        try await wait("a different workbook revoking console AI consent") { !viewer.aiSharing.accepted }
        ai.open(doc)
        try check(ai.acknowledgement.state == .off && !ai.contextPanel.isHidden && !ai.sendButton.isEnabled,
                  "selecting a new workbook requires fresh console AI sharing confirmation")
        completed = true
        return createdDirectories
    }
}
