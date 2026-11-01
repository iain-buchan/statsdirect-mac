import Cocoa
import WebKit

extension RConsoleIntegrationTests {
    /// Exercises actual R requests, WebKit recovery and the question field's
    /// accessible name/live-region contract. It does not automate VoiceOver.
    @MainActor static func consoleQuestionChecks(_ viewer: Viewer) async throws -> [URL] {
        let originalIDs = Set(viewer.documents.map(\.id)), originalActive = viewer.active
        var directories: [URL] = [], completed = false
        defer {
            if !completed { sessionFolders += directories }
            for doc in viewer.documents.filter({ !originalIDs.contains($0.id) }) {
                doc.rConsolePane?.shutdown(); viewer.remove(doc)
            }
            if let originalActive, viewer.documents.contains(where: { $0.id == originalActive.id }) {
                viewer.tabs.selectTabViewItem(originalActive.item)
            }
        }
        let doc = viewer.makeRConsole(script: "# Authored source stays separate from question data.\n", saved: true)
        guard let pane = doc.rConsolePane else { throw LegacyReportError("The question fixture did not create an R console") }
        try await makeConsoleVisible(viewer, doc); try await ready(doc)
        if let directory = pane.session.workingDirectory { directories.append(directory) }
        let sessionID = pane.session.sessionId, generation = pane.session.generation
        func questions(_ state: [String: Any]) -> [[String: Any]] {
            (state["transcript"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "question" }
        }
        func replies(_ state: [String: Any]) -> [[String: Any]] {
            (state["transcript"] as? [[String: Any]] ?? []).filter { $0["origin"] as? String == "input" }
        }
        func waiting(_ prompt: String) async throws {
            try await wait("the rendered R question " + prompt) {
                let state = try await snapshot(doc)
                guard pane.session.state == "input", state["state"] as? String == "input", state["prompt"] as? String == prompt else { return false }
                return try await evaluate(doc, "Array.from(document.querySelectorAll('.question-entry')).some(node=>node.textContent===\(try literal(prompt)))") as? Bool == true
            }
        }
        func reload() async throws {
            let previous = try await evaluate(doc, "performance.timeOrigin") as? Double ?? 0
            pane.load()
            try await wait("the recovered question WebKit document") {
                guard !doc.web.isLoading else { return false }
                return ((try? await evaluate(doc, "performance.timeOrigin")) as? Double ?? 0) > previous
            }
            try await makeConsoleVisible(viewer, doc)
        }

        // Split the literal so the full question is never present in executable
        // source/history; only the nonexecuting transcript owns its complete text.
        let unanswered = "UNANSWERED_QUESTION? "
        let command = "answer <- readline(paste0('UNANSWERED_', 'QUESTION? '))"
        try await console(doc, command); try await waiting(unanswered)
        let pending = try await snapshot(doc), pendingQuestions = questions(pending)
        let requestID = pending["requestId"] as? String ?? ""
        let commandID = pendingQuestions.first?["commandId"] as? String ?? ""
        let source = pane.sourceText, history = pending["history"] as? [String] ?? []
        try check(pendingQuestions.count == 1 && pendingQuestions[0]["text"] as? String == unanswered
                  && pendingQuestions[0]["answered"] as? Bool == false && !requestID.isEmpty && !commandID.isEmpty
                  && replies(pending).isEmpty && !source.contains(unanswered) && history == [command],
                  "a real unanswered R question appears immediately as transcript data with request/command identity, without an invented answer or executable history entry")

        let accessibility = try await evaluate(doc, """
        (()=>{
          const input=document.getElementById('console-input'),prompt=document.getElementById('prompt'),announcement=document.getElementById('question-announcement');
          const names=(input.getAttribute('aria-labelledby')||'').split(/\\s+/).filter(Boolean),descriptions=(input.getAttribute('aria-describedby')||'').split(/\\s+/).filter(Boolean);
          const row=document.querySelector('.question-entry');
          window.__questionMutations=0;
          window.__questionObserver=new MutationObserver(records=>window.__questionMutations+=records.length);
          for(const node of [prompt,announcement,document.getElementById('state')])window.__questionObserver.observe(node,{childList:true,subtree:true,characterData:true});
          return {names,namedText:names.map(id=>document.getElementById(id)?.textContent||'').join(' '),
            describedText:descriptions.map(id=>document.getElementById(id)?.textContent||'').join(' '),
            masked:input.hasAttribute('aria-label')||prompt.hasAttribute('aria-label'),enabled:!input.disabled,
            live:announcement.getAttribute('aria-live'),atomic:announcement.getAttribute('aria-atomic'),role:announcement.getAttribute('role'),announcement:announcement.textContent,
            transcriptLive:document.getElementById('transcript').getAttribute('aria-live'),footer:document.getElementById('state').textContent,
            request:row.dataset.requestId,command:row.dataset.commandId,questionColor:getComputedStyle(row).color};
        })()
        """) as? [String: Any] ?? [:]
        try check(accessibility["enabled"] as? Bool == true && accessibility["masked"] as? Bool == false
                  && accessibility["names"] as? [String] == ["console-input-label", "prompt"]
                  && (accessibility["namedText"] as? String ?? "").contains(unanswered)
                  && (accessibility["describedText"] as? String ?? "").contains("Shift+Enter")
                  && accessibility["role"] as? String == "status" && accessibility["live"] as? String == "polite"
                  && accessibility["atomic"] as? String == "true" && accessibility["announcement"] as? String == "R question 1: " + unanswered
                  && accessibility["transcriptLive"] as? String == "off" && accessibility["footer"] as? String == "R is waiting for your answer"
                  && accessibility["request"] as? String == requestID && accessibility["command"] as? String == commandID
                  && accessibility["questionColor"] as? String == "rgb(32, 33, 36)",
                  "WebKit exposes the current question in the enabled input's accessible name and one polite question region, keeps keyboard instructions, and renders black question text without announcing the full transcript")
        _ = try await evaluate(doc, "StatsDirectRConsole.setMode('script');StatsDirectRConsole.setMode('console');true")
        let mutations = try await evaluate(doc, "window.__questionObserver.disconnect();window.__questionMutations") as? Int ?? -1
        try check(mutations == 0, "ordinary control renders do not rewrite the question label or live announcements")

        try await reload(); try await waiting(unanswered)
        let recoveredPending = try await snapshot(doc)
        try check(questions(recoveredPending).count == 1 && recoveredPending["requestId"] as? String == requestID
                  && questions(recoveredPending).first?["commandId"] as? String == commandID && replies(recoveredPending).isEmpty
                  && pane.sourceText == source && recoveredPending["history"] as? [String] == history
                  && pane.session.sessionId == sessionID && pane.session.generation == generation,
                  "WebKit recovery restores one pending question and its actual reply target without rerunning R or changing source/history")
        _ = try await evaluate(doc, "document.getElementById('stop').click();true")
        try await ready(doc)
        try await reload(); try await ready(doc)
        let stopped = try await snapshot(doc)
        try check(questions(stopped).count == 1 && questions(stopped)[0]["text"] as? String == unanswered
                  && questions(stopped)[0]["answered"] as? Bool == false && replies(stopped).isEmpty
                  && pane.sourceText == source && stopped["history"] as? [String] == history,
                  "Stop and subsequent WebKit recovery retain the unanswered question without fabricating a reply or adding prompt text to source/history")

        let answered = "ANSWERED_QUESTION? "
        let errorCommand = "reply <- readline(paste0('ANSWERED_', 'QUESTION? ')); stop('EXPECTED_QUESTION_ERROR')"
        try await console(doc, errorCommand); try await waiting(answered)
        let beforeAnswer = try await snapshot(doc), answerSource = pane.sourceText
        let answerRequest = beforeAnswer["requestId"] as? String ?? ""
        let answerCommand = questions(beforeAnswer).last?["commandId"] as? String ?? ""
        try await console(doc, "student answer"); try await ready(doc)
        try await wait("the intentional error following the R answer") { try await renderedOutput(doc).contains("EXPECTED_QUESTION_ERROR") }
        try await reload(); try await ready(doc)
        try await wait("recovered question and reply DOM") {
            try await evaluate(doc, "document.querySelectorAll('.question-entry').length===2 && !!document.querySelector('.input-entry.reply pre:last-child')") as? Bool == true
        }
        let afterAnswer = try await snapshot(doc), echoedReplies = replies(afterAnswer), allQuestions = questions(afterAnswer)
        let questionCount = try await evaluate(doc, "Array.from(document.querySelectorAll('.question-entry')).filter(node=>node.textContent===\(try literal(answered))).length") as? Int ?? 0
        let replyColor = try await evaluate(doc, "getComputedStyle(document.querySelector('.input-entry.reply pre:last-child')).color") as? String
        let announcement = try await evaluate(doc, "document.getElementById('question-announcement').textContent") as? String
        try check(allQuestions.count == 2 && allQuestions.last?["answered"] as? Bool == true && questionCount == 1
                  && echoedReplies.count == 1 && echoedReplies[0]["text"] as? String == "student answer"
                  && echoedReplies[0]["prompt"] as? String == "" && echoedReplies[0]["requestId"] as? String == answerRequest
                  && echoedReplies[0]["commandId"] as? String == answerCommand && !answerRequest.isEmpty && !answerCommand.isEmpty
                  && pane.sourceText == answerSource && afterAnswer["history"] as? [String] == [command, errorCommand]
                  && !answerSource.contains(answered) && !answerSource.contains("student answer")
                  && replyColor == "rgb(6, 69, 173)" && announcement == "",
                  "a real reply stays blue answer data with its command/request identity, its question appears once after error/recovery, and neither prompt nor answer enters executable source/history")
        completed = true
        return directories
    }
}
