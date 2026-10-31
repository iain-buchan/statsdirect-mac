import Cocoa
import WebKit
import PDFKit

/// Exercises the actual WebKit page, native message handler and embedded-R
/// worker together. Commands enter through the same controls as user input.
@main struct RConsoleIntegrationTests {
    @MainActor private static var sessionFolders: [URL] = []

    @MainActor static func check(_ ok: Bool, _ message: String) throws {
        guard ok else { throw NSError(domain: "RConsoleIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: " + message); fflush(stdout)
    }
    @MainActor static func wait(_ name: String, seconds: TimeInterval = 20, _ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw NSError(domain: "RConsoleIntegration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + name])
    }
    static func literal(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }
    @MainActor static func evaluate(_ doc: Document, _ code: String) async throws -> Any {
        try await doc.web.evaluateJavaScript(code) ?? NSNull()
    }
    @MainActor static func snapshot(_ doc: Document) async throws -> [String: Any] {
        try await evaluate(doc, "window.StatsDirectRConsole?.snapshot()") as? [String: Any] ?? [:]
    }
    @MainActor static func renderedOutput(_ doc: Document) async throws -> String {
        let state = try await snapshot(doc)
        return (state["transcript"] as? [[String: Any]] ?? [])
            .filter { $0["kind"] as? String == "output" }.compactMap { $0["text"] as? String }.joined()
    }
    @MainActor static func ready(_ doc: Document) async throws {
        try await wait("native and rendered ready prompts") { try await readyState(doc) }
    }
    @MainActor static func console(_ doc: Document, _ source: String) async throws {
        _ = try await evaluate(doc, """
        (() => {
          StatsDirectRConsole.setMode('console');
          const input = document.getElementById('console-input');
          input.value = \(try literal(source)); input.dispatchEvent(new Event('input', {bubbles:true}));
          document.getElementById('run').click(); return true;
        })()
        """)
    }
    @MainActor static func expectOutput(_ doc: Document, _ marker: String) async throws {
        try await wait("R output " + marker) {
            let idle = try await readyState(doc), output = try await renderedOutput(doc)
            return idle && output.contains(marker)
        }
    }
    @MainActor static func post(_ doc: Document, _ action: String, fields: [String: Any] = [:], envelope: [String: Any]? = nil) async throws {
        let current = try await snapshot(doc)
        var body: [String: Any] = ["protocolVersion": 1, "action": action,
                                   "sessionId": current["sessionId"] ?? "", "generation": current["generation"] ?? -1]
        if let envelope { body["sessionId"] = envelope["sessionId"]; body["generation"] = envelope["generation"] }
        for (key, value) in fields { body[key] = value }
        _ = try await evaluate(doc, "window.webkit.messageHandlers.statsDirectRConsole.postMessage(\(try literal(body))); true")
    }
    @MainActor static func cleanup(_ viewer: Viewer) async {
        for doc in viewer.documents { doc.rConsolePane?.shutdown(); doc.rPane?.shutdown() }
        // Session shutdown preserves user files. These directories were created
        // solely by this test, so remove them after their workers have exited.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for url in sessionFolders { try? FileManager.default.removeItem(at: url) }
        sessionFolders = []
    }
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        let viewer = Viewer(); app.delegate = viewer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                var passed = false
                do { try await run(viewer); passed = true; print("PASS: live WebKit interactive R console integration completed"); fflush(stdout) }
                catch { print("FAIL: " + error.localizedDescription); fflush(stdout) }
                await cleanup(viewer)
                if passed { viewer.closeApproved = true; app.terminate(nil) }
                else { exit(1) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            Task { @MainActor in
                print("FAIL: interactive R console integration watchdog timed out"); fflush(stdout)
                await cleanup(viewer); exit(1)
            }
        }
        app.run()
    }

    @MainActor static func run(_ viewer: Viewer) async throws {
        try check(RRuntime.executable() != nil, "R is installed for the real runtime integration test")
        viewer.window.setContentSize(NSSize(width: 1100, height: 800))
        let doc = viewer.makeRConsole(), pane = doc.rConsolePane!
        defer { pane.shutdown() }
        try await ready(doc)
        if let directory = pane.session.workingDirectory { sessionFolders.append(directory) }
        try check((try await snapshot(doc))["sessionId"] as? String == pane.session.sessionId,
                  "WebKit and native transport agree on the active session")

        try await console(doc, "saved <- 41; cat('INITIAL_READY\\n')")
        try await expectOutput(doc, "INITIAL_READY\n")
        try await console(doc, "cat('PERSIST=', saved + 1, '\\n', sep='')")
        try await expectOutput(doc, "PERSIST=42\n")
        try check(pane.sourceText.contains("saved <- 41") && pane.outputText.contains("PERSIST=42"),
                  "console commands use one persistent R workspace and reach native AI snapshots")

        try await console(doc, "reloadCounter <- if (exists('reloadCounter')) reloadCounter + 1 else 1; cat('RECOVERY_READY\\n')")
        try await expectOutput(doc, "RECOVERY_READY\n")
        let recoverySource = pane.sourceText, recoveryOutput = try await renderedOutput(doc)
        let previousTimeOrigin = try await evaluate(doc, "performance.timeOrigin") as? Double ?? 0
        pane.load()
        try await wait("a reloaded WebKit document") {
            let timeOrigin = try? await evaluate(doc, "performance.timeOrigin") as? Double
            return !doc.web.isLoading && (timeOrigin ?? 0) > previousTimeOrigin
        }
        try await wait("replayed renderer state") {
            let state = try await snapshot(doc), output = try await renderedOutput(doc)
            return state["state"] as? String == "ready" && state["script"] as? String == recoverySource && output == recoveryOutput
        }
        try check(pane.sourceText == recoverySource, "renderer reload restores exact source and output without duplicating input echoes")
        try await console(doc, "stopifnot(saved == 41, reloadCounter == 1); cat('RECOVERY_NO_RERUN\\n')")
        try await expectOutput(doc, "RECOVERY_NO_RERUN\n")
        try check(true, "renderer recovery preserves the existing R workspace and does not rerun commands")

        let beforeRejectedSource = pane.sourceText
        try await console(doc, "saved <- -999\u{0}; cat('NUL_MUST_NOT_RUN\\n')")
        try await ready(doc)
        try check(pane.sourceText == beforeRejectedSource,
                  "a rejected NUL submission restores the ready prompt without entering executable history")
        try await console(doc, "stopifnot(saved == 41); cat('NUL_REJECTION_RECOVERED\\n')")
        try await expectOutput(doc, "NUL_REJECTION_RECOVERED\n")

        try await console(doc, "if (TRUE) {")
        try await wait("continuation prompt") { (try await snapshot(doc))["state"] as? String == "continuation" }
        let continuationID = pane.session.commandId
        try await console(doc, "continued <- saved + 1; cat('CONTINUED=', continued, '\\n', sep='')")
        try await wait("second continuation prompt") { (try await snapshot(doc))["state"] as? String == "continuation" }
        try check(pane.session.commandId == continuationID, "multiline input retains its original command identity")
        try await console(doc, "}")
        try await expectOutput(doc, "CONTINUED=42\n")
        try check(true, "multiline R input executes only after the expression is complete")

        try await console(doc, "answer <- readline('Colour? '); cat('ANSWER=', answer, '\\n', sep='')")
        try await wait("readline input request") { (try await snapshot(doc))["state"] as? String == "input" }
        let beforeAnswer = pane.sourceText, reply = "chartreuse-reply-token-741"
        try await console(doc, reply)
        try await expectOutput(doc, "ANSWER=" + reply + "\n")
        let afterAnswer = try await snapshot(doc)
        try check(pane.sourceText == beforeAnswer && !(afterAnswer["history"] as? [String] ?? []).contains(reply)
                  && !(afterAnswer["script"] as? String ?? "").contains(reply),
                  "readline answers appear in output but never become executable script or command history")

        try await console(doc, "shortAnswer <- readline('Short answer? '); cat('RETRY=', shortAnswer, '\\n', sep='')")
        try await wait("bounded readline answer request") { (try await snapshot(doc))["state"] as? String == "input" }
        let retryRequest = pane.session.inputRequestId!, sourceBeforeRetry = pane.sourceText
        try await console(doc, String(repeating: "🙂", count: 100_000))
        try await wait("the same input request after oversized answer rejection") {
            let state = try await snapshot(doc)
            return state["state"] as? String == "input" && state["requestId"] as? String == retryRequest
        }
        try check(pane.session.inputRequestId == retryRequest && pane.sourceText == sourceBeforeRetry,
                  "an oversized UTF-8 answer retains the original native and WebKit request for retry")
        try await console(doc, "short-retry-answer")
        try await expectOutput(doc, "RETRY=short-retry-answer\n")
        try check(pane.sourceText == sourceBeforeRetry, "a valid retry answers the original question without entering the script")

        try await console(doc, "repeat { Sys.sleep(0.03) }; loopSentinel <- TRUE")
        try await wait("running loop") { (try await snapshot(doc))["state"] as? String == "busy" }
        _ = try await evaluate(doc, "document.getElementById('stop').click(); true")
        try await ready(doc)
        try await console(doc, "stopifnot(saved == 41, !exists('loopSentinel')); cat('LOOP_STOP_PRESERVED\\n')")
        try await expectOutput(doc, "LOOP_STOP_PRESERVED\n")
        try check(true, "Stop unwinds a running loop and preserves R variables")

        try await console(doc, "stoppedAnswer <- readline('Stop answer? '); inputSentinel <- TRUE")
        try await wait("second readline request") { (try await snapshot(doc))["state"] as? String == "input" }
        let retiredRequest = pane.session.inputRequestId!
        _ = try await evaluate(doc, "document.getElementById('stop').click(); true")
        try await ready(doc)
        try await post(doc, "inputReply", fields: ["requestId": retiredRequest, "text": "must-not-execute"])
        try await console(doc, "stopifnot(saved == 41, !exists('stoppedAnswer'), !exists('inputSentinel')); cat('INPUT_STOP_PRESERVED\\n')")
        try await expectOutput(doc, "INPUT_STOP_PRESERVED\n")
        try check(true, "Stop cancels readline without submitting an answer or running following code, and rejects its stale reply")

        let board = NSPasteboard.general
        let clipboard = board.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        defer {
            board.clearContents()
            board.writeObjects(clipboard.map { values in
                let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
            })
        }
        func plotEntries() async throws -> [[String: Any]] {
            (try await snapshot(doc))["transcript"] as? [[String: Any]] ?? []
        }
        func copyPlot(_ index: Int) async throws -> Data {
            let prior = board.changeCount
            _ = try await evaluate(doc, "Array.from(document.querySelectorAll('figure.plot'))[\(index)].querySelectorAll('button')[1].click(); true")
            try await wait("native vector PDF copy") { board.changeCount != prior && board.data(forType: .pdf) != nil }
            return board.data(forType: .pdf)!
        }
        try await console(doc, "plot(1:5, 1:5, main='Console integration chart')")
        try await wait("first inline PDF preview") {
            let idle = try await readyState(doc), entries = try await plotEntries()
            return idle && entries.filter { $0["kind"] as? String == "plot" }.count == 1
        }
        try await wait("decoded inline preview") {
            (try await evaluate(doc, "!!document.querySelector('figure.plot img')?.complete && document.querySelector('figure.plot img').naturalWidth > 0")) as? Bool == true
        }
        let originalPDF = try await copyPlot(0)
        let previewPNG = board.data(forType: .png), previewBitmap = previewPNG.flatMap { NSBitmapImageRep(data: $0) }
        try check(PDFDocument(data: originalPDF)?.pageCount == 1 && !(previewPNG?.isEmpty ?? true)
                  && (previewBitmap?.pixelsWide ?? 0) > 0 && (previewBitmap?.pixelsHigh ?? 0) > 0,
                  "inline chart maps to its original vector PDF and a valid nonempty PNG preview")
        try await console(doc, "abline(a=0, b=1, col='red', lwd=3)")
        try await wait("updated chart snapshot") {
            let idle = try await readyState(doc), entries = try await plotEntries()
            return idle && entries.filter { $0["kind"] as? String == "plot" }.count == 2
        }
        let firstStillOriginal = try await copyPlot(0), updatedPDF = try await copyPlot(1)
        try check(firstStillOriginal == originalPDF && updatedPDF != originalPDF && PDFDocument(data: updatedPDF)?.pageCount == 1,
                  "plot then abline creates a new inline snapshot while earlier charts retain their original PDF mapping")

        let originalSession = pane.session.sessionId
        let script = "scriptValue <- saved + 9; cat('SCRIPT_SHARED=', scriptValue, '\\n', sep='')\n"
        _ = try await evaluate(doc, """
        (() => {
          StatsDirectRConsole.setMode('script');
          const source = document.getElementById('script-source');
          source.value = \(try literal(script)); source.setSelectionRange(0,0);
          source.dispatchEvent(new Event('input', {bubbles:true}));
          document.getElementById('run').click(); return true;
        })()
        """)
        try await expectOutput(doc, "SCRIPT_SHARED=50\n")
        try check(pane.sourceText == script && pane.session.sessionId == originalSession,
                  "Run Script uses the existing console workspace without duplicating script text")
        try await console(doc, "cat('SCRIPT_VARIABLE=', scriptValue, '\\n', sep='')")
        try await expectOutput(doc, "SCRIPT_VARIABLE=50\n")

        let scriptBeforeRestart = pane.sourceText, oldEnvelope = try await snapshot(doc), oldGeneration = pane.session.generation
        _ = try await evaluate(doc, "document.getElementById('restart').click(); true")
        try await wait("Restart confirmation") { viewer.window.attachedSheet != nil }
        viewer.window.endSheet(viewer.window.attachedSheet!, returnCode: .alertFirstButtonReturn)
        try await wait("new R generation") { pane.session.generation > oldGeneration }
        try await ready(doc)
        if let directory = pane.session.workingDirectory { sessionFolders.append(directory) }
        let restartedScript = try await snapshot(doc)["script"] as? String
        try check(pane.session.sessionId != originalSession && pane.sourceText == scriptBeforeRestart
                  && restartedScript == scriptBeforeRestart,
                  "Restart creates a fresh workspace and preserves the editable script")
        try await post(doc, "submit", fields: ["source": "staleSentinel <- TRUE", "origin": "console"], envelope: oldEnvelope)
        try await console(doc, "cat('RESTART_CLEAR=', !exists('saved') && !exists('scriptValue') && !exists('staleSentinel'), '\\n', sep='')")
        try await expectOutput(doc, "RESTART_CLEAR=TRUE\n")
        try check(!pane.sourceText.contains("staleSentinel <- TRUE"), "retired-generation bridge commands cannot alter the new workspace or script")
    }

    @MainActor static func readyState(_ doc: Document) async throws -> Bool {
        let current = try await snapshot(doc)
        return doc.rConsolePane?.session.state == "ready" && current["state"] as? String == "ready"
    }
}
