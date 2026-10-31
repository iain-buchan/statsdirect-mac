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
    @MainActor static func pdfViews(_ view: NSView) -> [PDFView] {
        (view as? PDFView).map { [$0] } ?? view.subviews.flatMap(pdfViews)
    }
    @MainActor static func vectorWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "StatsDirectRConsolePDF" && $0.isVisible }
    }
    @MainActor static func vectorBytes(_ window: NSWindow) -> Data? {
        guard let content = window.contentView, let document = pdfViews(content).first?.document else { return nil }
        if let url = document.documentURL { return try? Data(contentsOf: url) }
        return document.dataRepresentation()
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
        let survivesFocus = try await doc.web.callAsyncJavaScript("""
        const button = document.querySelector('figure.plot button');
        window.__rConsoleFocusOpen = button;
        button.focus(); document.dispatchEvent(new Event('selectionchange'));
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return button.isConnected && document.querySelector('figure.plot button') === button;
        """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        try check(survivesFocus, "focusing a chart action and changing selection preserves the original clickable DOM node")
        _ = try await evaluate(doc, "window.__rConsoleFocusOpen.click(); delete window.__rConsoleFocusOpen; true")
        try await wait("the native vector PDF window") { vectorWindows().count == 1 }
        let vectorWindow = vectorWindows()[0]
        defer { vectorWindow.performClose(nil) }
        let vectorDocument = vectorWindow.contentView.flatMap { pdfViews($0).first?.document }
        try check(vectorDocument?.pageCount == 1 && vectorBytes(vectorWindow) == originalPDF,
                  "Open vector PDF displays the original chart in a visible native PDFKit window")
        viewer.window.makeKeyAndOrderFront(nil)
        try await console(doc, "abline(a=0, b=1, col='red', lwd=3)")
        try await wait("updated chart snapshot") {
            let idle = try await readyState(doc), entries = try await plotEntries()
            return idle && entries.filter { $0["kind"] as? String == "plot" }.count == 2
        }
        let firstStillOriginal = try await copyPlot(0), updatedPDF = try await copyPlot(1)
        try check(firstStillOriginal == originalPDF && updatedPDF != originalPDF && PDFDocument(data: updatedPDF)?.pageCount == 1,
                  "plot then abline creates a new inline snapshot while earlier charts retain their original PDF mapping")
        let pointerGate = pane.session.workingDirectory!.appendingPathComponent("pointer-output-gate")
        try await console(doc, "cat('POINTER_READY\\n'); while (!file.exists('pointer-output-gate')) Sys.sleep(0.02); cat('POINTER_OUTPUT\\n')")
        try await wait("R waiting to emit output during a chart click") {
            (try await renderedOutput(doc)).contains("POINTER_READY\n")
        }
        _ = try await evaluate(doc, """
        (() => {
          const button = document.querySelector('figure.plot button');
          window.__rConsolePointerOpen = button;
          button.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, pointerId:71, button:0, isPrimary:true}));
          button.focus(); document.dispatchEvent(new Event('selectionchange')); return true;
        })()
        """)
        try Data("go".utf8).write(to: pointerGate, options: .atomic)
        try await expectOutput(doc, "POINTER_OUTPUT\n")
        let survivesOutput = try await doc.web.callAsyncJavaScript("""
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const button = window.__rConsolePointerOpen;
        return button.isConnected && document.querySelector('figure.plot button') === button;
        """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        try check(survivesOutput, "real R output arriving during pointer-down preserves the original chart action until pointer-up")
        _ = try await evaluate(doc, """
        (() => {
          const button = window.__rConsolePointerOpen;
          button.dispatchEvent(new PointerEvent('pointerup', {bubbles:true, pointerId:71, button:0, isPrimary:true}));
          button.click(); delete window.__rConsolePointerOpen; return true;
        })()
        """)
        try await wait("the reused native vector PDF window") { vectorWindow.isKeyWindow }
        try check(vectorWindows().count == 1 && vectorWindows().first === vectorWindow
                  && vectorBytes(vectorWindow) == originalPDF,
                  "opening an earlier chart after abline reuses its PDF window and preserves that chart version")
        let documentCountBeforePDFClose = viewer.documents.count
        viewer.closeTab()
        try await wait("the vector PDF window to close") { !vectorWindow.isVisible }
        try check(viewer.documents.count == documentCountBeforePDFClose && viewer.documents.contains { $0 === doc }
                  && pane.session.isRunning,
                  "the native Close command closes the PDF window and retains the R console document and workspace")
        viewer.window.makeKeyAndOrderFront(nil)

        try await console(doc, "cat(paste0('WHEEL_ROW_', seq_len(120), collapse='\\n'), '\\n', sep='')")
        try await expectOutput(doc, "WHEEL_ROW_120\n")
        try await wait("long, scrollable console history") {
            (try await evaluate(doc, "document.getElementById('transcript').scrollHeight > document.getElementById('transcript').clientHeight * 4")) as? Bool == true
        }
        let sourceBeforeWheel = pane.sourceText
        let wheel = try await doc.web.callAsyncJavaScript("""
        const log = document.getElementById('transcript'), input = document.getElementById('console-input');
        const prompt = document.getElementById('prompt'), row = document.querySelector('.input-row');
        const source = StatsDirectRConsole.snapshot().script, history = JSON.stringify(StatsDirectRConsole.snapshot().history);
        const sendWheel = (target, deltaY, deltaMode=0, fields={}) => {
          const event = new WheelEvent('wheel', {bubbles:true, cancelable:true, deltaY, deltaMode, ...fields});
          target.dispatchEvent(event); return event.defaultPrevented;
        };
        const settle = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        StatsDirectRConsole.setMode('console'); input.value = draft;
        input.dispatchEvent(new Event('input', {bubbles:true})); input.focus(); input.setSelectionRange(5,8);
        await settle();
        log.scrollTop = log.scrollHeight;
        const bottom = log.scrollTop, upPrevented = sendWheel(input,-120), afterUp = log.scrollTop;
        const downPrevented = sendWheel(prompt,120), afterDown = log.scrollTop;
        log.scrollTop = 0; const topPrevented = sendWheel(row,-120), atTop = log.scrollTop;
        const middle = Math.min(log.scrollHeight-log.clientHeight, log.clientHeight*2+200);
        log.scrollTop = middle; const pixelPrevented = sendWheel(row,-1,0), pixelDistance = middle-log.scrollTop;
        log.scrollTop = middle; const linePrevented = sendWheel(input,-1,1), lineDistance = middle-log.scrollTop;
        log.scrollTop = middle; const pagePrevented = sendWheel(prompt,-1,2), pageDistance = middle-log.scrollTop;
        const shortDraftPreserved = input.value === draft && document.activeElement === input && input.selectionStart === 5 && input.selectionEnd === 8;
        const unchangedSource = StatsDirectRConsole.snapshot().script === source && JSON.stringify(StatsDirectRConsole.snapshot().history) === history;

        const longDraft = Array.from({length:200},(_,i)=>'# unsent multiline draft '+i).join('\\n');
        input.value = longDraft; input.dispatchEvent(new Event('input',{bubbles:true})); input.focus(); await settle();
        input.scrollTop = (input.scrollHeight-input.clientHeight)/2; log.scrollTop = middle;
        const localInput = input.scrollTop, localLog = log.scrollTop, localPrevented = sendWheel(input,80);
        const textareaLocal = input.scrollHeight > input.clientHeight && !localPrevented && log.scrollTop === localLog && input.scrollTop === localInput && input.value === longDraft;
        input.scrollTop = input.scrollHeight; log.scrollTop = middle;
        const downStart = log.scrollTop, textareaDownPrevented = sendWheel(input,80), textareaDown = log.scrollTop;
        input.scrollTop = 0; log.scrollTop = middle;
        const upStart = log.scrollTop, textareaUpPrevented = sendWheel(input,-80), textareaUp = log.scrollTop;
        const multilinePreserved = input.value === longDraft && document.activeElement === input;
        log.scrollTop = middle; const modifiersStart = log.scrollTop;
        const ignored = [{ctrlKey:true},{metaKey:true},{shiftKey:true},{deltaX:300}].every(fields=>!sendWheel(input,-80,0,fields));
        const modifiersUntouched = ignored && log.scrollTop === modifiersStart && input.value === longDraft;

        StatsDirectRConsole.setMode('script');
        const script = document.getElementById('script-source'), scriptText = script.value, scriptLog = log.scrollTop;
        const scriptPrevented = sendWheel(script,80);
        const scriptUntouched = !scriptPrevented && script.value === scriptText && log.scrollTop === scriptLog && StatsDirectRConsole.snapshot().mode === 'script';
        StatsDirectRConsole.setMode('console'); input.value = draft;
        input.dispatchEvent(new Event('input',{bubbles:true})); input.focus(); input.setSelectionRange(5,8);
        return {
          forwardsUpDown:upPrevented && afterUp < bottom && downPrevented && Math.abs(afterDown-bottom)<1,
          topBounded:!topPrevented && atTop===0,
          units:pixelPrevented && linePrevented && pagePrevented && pixelDistance>0 && lineDistance>pixelDistance*8 && lineDistance<100 && Math.abs(pageDistance-log.clientHeight)<2,
          shortDraftPreserved, unchangedSource, textareaLocal,
          textareaBoundaries:textareaDownPrevented && textareaDown>downStart && textareaUpPrevented && textareaUp<upStart && multilinePreserved,
          modifiersUntouched, scriptUntouched,
          finalSource:StatsDirectRConsole.snapshot().script === source && JSON.stringify(StatsDirectRConsole.snapshot().history) === history
        };
        """, arguments: ["draft":"# unsubmitted draft\nsqrt(144)"], in: nil, contentWorld: .page) as? [String:Any] ?? [:]
        try check(wheel["forwardsUpDown"] as? Bool == true && wheel["topBounded"] as? Bool == true,
                  "wheel input over the prompt, input row and short draft scrolls console history in both directions and respects its top boundary")
        try check(wheel["units"] as? Bool == true, "pixel, line and page wheel deltas scroll console history in their expected units")
        try check(wheel["shortDraftPreserved"] as? Bool == true && wheel["unchangedSource"] as? Bool == true,
                  "prompt wheel scrolling preserves unsent draft text, selection, keyboard focus, script and command history")
        try check(wheel["textareaLocal"] as? Bool == true && wheel["textareaBoundaries"] as? Bool == true,
                  "a multiline draft retains native textarea scrolling until its boundary, then forwards wheel movement to console history")
        try check(wheel["modifiersUntouched"] as? Bool == true && wheel["scriptUntouched"] as? Bool == true,
                  "modified or horizontal wheel gestures and the Script view retain their normal browser behavior")
        try check(wheel["finalSource"] as? Bool == true && pane.sourceText == sourceBeforeWheel,
                  "wheel handling never changes or executes the editable R source")

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
