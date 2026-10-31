import Cocoa
import PDFKit
import WebKit

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
    @MainActor static func webViews(_ view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
    }
    @MainActor static func vectorWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "StatsDirectRConsoleSVG" && $0.isVisible }
    }
    @MainActor static func vectorBytes(_ window: NSWindow) -> Data? {
        guard let controller = window.windowController as? RConsoleSVGWindow else { return nil }
        return try? Data(contentsOf: controller.fileURL)
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
        let clearCommand = pane.session.commandId, clearRequest = pane.session.inputRequestId, clearState = pane.session.state
        let cleared = try await evaluate(doc, """
        (() => {
          const input = document.getElementById('console-input');
          input.value = 'unsent answer draft'; input.dispatchEvent(new Event('input', {bubbles:true}));
          input.focus(); input.setSelectionRange(2, 10, 'backward');
          const draft = input.value, selection = [input.selectionStart, input.selectionEnd, input.selectionDirection];
          const before = StatsDirectRConsole.snapshot();
          const retained = ({transcript, outputText, trimmed, ...state}) => JSON.stringify(state);
          StatsDirectRConsole.clearOutput();
          const after = StatsDirectRConsole.snapshot();
          return {
            hadTranscript: before.transcript.length > 0 && before.state === 'input' && !!before.requestId,
            emptyOutput: after.transcript.length === 0 && after.outputText === '' && !after.trimmed,
            retainedState: retained(before) === retained(after),
            retainedDraft: input.value === draft,
            retainedSelection: JSON.stringify([input.selectionStart, input.selectionEnd, input.selectionDirection]) === JSON.stringify(selection),
            retainedFocus: document.activeElement === input
          };
        })()
        """) as? [String: Any] ?? [:]
        try await wait("cleared rendered R transcript") {
            try await evaluate(doc, "document.querySelectorAll('#transcript .input-entry, #transcript .output-entry, #transcript .plot').length === 0 && document.getElementById('transcript').textContent.includes('Enter R commands below')") as? Bool == true
        }
        try check(["hadTranscript", "emptyOutput", "retainedState", "retainedDraft", "retainedSelection", "retainedFocus"].allSatisfy { cleared[$0] as? Bool == true }
                  && pane.sourceText == beforeAnswer && pane.session.commandId == clearCommand
                  && pane.session.inputRequestId == clearRequest && pane.session.state == clearState,
                  "Clear Output removes only the rendered transcript while preserving the unsent draft, selection, focus, script, history, session and pending real R question")
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
        func svgDataURI(_ value: String) throws -> Data {
            let prefix = "data:image/svg+xml;base64,"
            guard value.hasPrefix(prefix), let data = Data(base64Encoded: String(value.dropFirst(prefix.count))), !data.isEmpty else {
                throw NSError(domain:"RConsoleIntegration",code:3,userInfo:[NSLocalizedDescriptionKey:"The chart does not contain an original SVG image"])
            }
            return data
        }
        func inlineSVG(_ index: Int) async throws -> Data {
            let source = try await evaluate(doc, "Array.from(document.querySelectorAll('figure.plot img'))[\(index)].src") as? String ?? ""
            return try svgDataURI(source)
        }
        let nativeSVGType = NSPasteboard.PasteboardType("public.svg-image")
        func copyPlot(_ index: Int) async throws -> Data {
            let prior = board.changeCount
            _ = try await evaluate(doc, "Array.from(document.querySelectorAll('figure.plot'))[\(index)].querySelectorAll('button')[1].click(); true")
            try await wait("original SVG and Office SVG with PNG fallback") {
                board.changeCount != prior && board.data(forType: nativeSVGType) != nil
                    && board.data(forType: ReportImageClipboard.officeSVGType) != nil
                    && !(board.data(forType: .png)?.isEmpty ?? true)
            }
            return board.data(forType: nativeSVGType)!
        }
        func retainedSVGURL(matching expected: Data) throws -> URL {
            let files = try FileManager.default.contentsOfDirectory(at: pane.session.workingDirectory!, includingPropertiesForKeys: nil)
            guard let file = files.first(where: { $0.pathExtension == "svg" && (try? Data(contentsOf: $0)) == expected }) else {
                throw NSError(domain: "RConsoleIntegration", code: 7, userInfo: [NSLocalizedDescriptionKey: "The original SVG asset was not retained in the R session"])
            }
            return file
        }
        try await console(doc, "plot(1:5, 1:5, main='Console integration chart')")
        try await wait("first inline SVG chart") {
            let idle = try await readyState(doc), entries = try await plotEntries()
            return idle && entries.filter { $0["kind"] as? String == "plot" }.count == 1
        }
        try await wait("decoded inline preview") {
            (try await evaluate(doc, "!!document.querySelector('figure.plot img')?.complete && document.querySelector('figure.plot img').naturalWidth > 0")) as? Bool == true
        }
        let copiedOriginalSVG = try await copyPlot(0), originalSVG = try await inlineSVG(0)
        let canonicalOriginalSVG = Data(try ReportImageClipboard.svgMarkup(originalSVG).utf8)
        func svgClipboardMatches(_ expected: Data, label: String) -> Bool {
            let actualTypes = board.pasteboardItems?.first?.types ?? []
            print("INFO: \(label) combined image clipboard types: \(actualTypes.map(\.rawValue).joined(separator: ", "))")
            fflush(stdout)
            let png = board.data(forType: .png)
            let bitmap = png.flatMap { NSBitmapImageRep(data: $0) }
            return board.pasteboardItems?.count == 1 && board.data(forType: nativeSVGType) == expected
                && board.data(forType: ReportImageClipboard.officeSVGType) == expected
                && actualTypes.contains(.png) && (bitmap?.pixelsWide ?? 0) > 0 && (bitmap?.pixelsHigh ?? 0) > 0
                && !actualTypes.contains(.fileURL)
        }
        let firstPlot = (try await plotEntries()).first { $0["kind"] as? String == "plot" }
        try check(firstPlot?["mime"] as? String == "image/svg+xml" && copiedOriginalSVG == originalSVG,
                  "Copy chart preserves the exact original SVG bytes without Office XML rewriting")
        try check(svgClipboardMatches(originalSVG, label: "Original chart"),
                  "one Copy chart publishes original SVG under both Mac and Office types alongside a valid PNG fallback")
        let importedClipboardSVG = try ReportImageClipboard.svgHTML(from: board)
        try check(importedClipboardSVG.map { Data($0.utf8) } == canonicalOriginalSVG,
                  "the report clipboard reader prefers the original vector markup over the PNG fallback")

        let guardBoard = NSPasteboard.withUniqueName()
        defer { guardBoard.releaseGlobally() }
        let guardDirectory = pane.session.workingDirectory!.appendingPathComponent("clipboard-guards", isDirectory: true)
        try FileManager.default.createDirectory(at: guardDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: guardDirectory) }
        let invalidSVG = guardDirectory.appendingPathComponent("invalid.svg")
        try Data("<html/>".utf8).write(to: invalidSVG)
        let wrongExtension = guardDirectory.appendingPathComponent("chart.txt")
        try originalSVG.write(to: wrongExtension)
        let directorySVG = guardDirectory.appendingPathComponent("directory.svg", isDirectory: true)
        try FileManager.default.createDirectory(at: directorySVG, withIntermediateDirectories: true)
        let largeSVG = guardDirectory.appendingPathComponent("large.svg")
        _ = FileManager.default.createFile(atPath: largeSVG.path, contents: nil)
        let sparseFile = try FileHandle(forWritingTo: largeSVG)
        try sparseFile.truncate(atOffset: UInt64(ReportImageClipboard.maximumBytes + 1)); try sparseFile.close()
        let invalidURLs = [URL(string: "https://example.invalid/chart.svg")!, wrongExtension, invalidSVG,
                           directorySVG, largeSVG, guardDirectory.appendingPathComponent("missing.svg")]
        var rejectedAll = true
        for url in invalidURLs {
            guardBoard.clearContents(); guardBoard.setString("clipboard must survive", forType: .string)
            let prior = guardBoard.changeCount
            do { try ReportImageClipboard.writeSVGFile(url, to: guardBoard); rejectedAll = false }
            catch { }
            rejectedAll = rejectedAll && guardBoard.changeCount == prior && guardBoard.string(forType: .string) == "clipboard must survive"
        }
        try check(rejectedAll, "invalid, missing, nonlocal, oversized and non-SVG chart files leave the existing clipboard unchanged")
        let survivesFocus = try await doc.web.callAsyncJavaScript("""
        const button = document.querySelector('figure.plot button');
        window.__rConsoleFocusOpen = button;
        button.focus(); document.dispatchEvent(new Event('selectionchange'));
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return button.isConnected && document.querySelector('figure.plot button') === button;
        """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        try check(survivesFocus, "focusing a chart action and changing selection preserves the original clickable DOM node")
        _ = try await evaluate(doc, "window.__rConsoleFocusOpen.click(); delete window.__rConsoleFocusOpen; true")
        try await wait("the native SVG window") { vectorWindows().count == 1 }
        let vectorWindow = vectorWindows()[0]
        defer { vectorWindow.performClose(nil) }
        guard let originalPlotURL = (vectorWindow.windowController as? RConsoleSVGWindow)?.fileURL else {
            throw NSError(domain: "RConsoleIntegration", code: 7, userInfo: [NSLocalizedDescriptionKey: "The native SVG window has no original chart file"])
        }
        guard let vectorWeb = vectorWindow.contentView.flatMap({ webViews($0).first }) else {
            throw NSError(domain:"RConsoleIntegration",code:3,userInfo:[NSLocalizedDescriptionKey:"The SVG window has no WebView"])
        }
        try await wait("the original SVG image in the chart WebView") {
            if let detail = (vectorWindow.windowController as? RConsoleSVGWindow)?.loadError {
                throw NSError(domain:"RConsoleIntegration",code:4,userInfo:[NSLocalizedDescriptionKey:"The native SVG window failed to load: " + detail])
            }
            return (try? await vectorWeb.evaluateJavaScript("!!document.querySelector('img')?.complete && document.querySelector('img').naturalWidth > 0 && document.querySelector('img').src.startsWith('data:image/svg+xml;base64,')")) as? Bool == true
        }
        let windowImageSource = try await vectorWeb.evaluateJavaScript("document.querySelector('img').src") as? String ?? ""
        let windowSVG = try svgDataURI(windowImageSource)
        try check(vectorBytes(vectorWindow) == originalSVG && windowSVG == originalSVG,
                  "Open chart displays the original SVG in a visible native WebView window")
        viewer.window.makeKeyAndOrderFront(nil)
        try await console(doc, "abline(a=0, b=1, col='red', lwd=3)")
        try await wait("updated chart snapshot") {
            let idle = try await readyState(doc), entries = try await plotEntries()
            return idle && entries.filter { $0["kind"] as? String == "plot" }.count == 2
        }
        try await wait("decoded updated SVG image") {
            (try await evaluate(doc, "document.querySelectorAll('figure.plot img').length === 2 && document.querySelectorAll('figure.plot img')[1].complete && document.querySelectorAll('figure.plot img')[1].naturalWidth > 0")) as? Bool == true
        }
        let firstStillOriginalSVG = try await copyPlot(0)
        let earlierSVGPreserved = svgClipboardMatches(originalSVG, label: "Earlier chart after abline")
        let updatedSVG = try await copyPlot(1), updatedOriginalSVG = try await inlineSVG(1)
        let updatedPlotURL = try retainedSVGURL(matching: updatedOriginalSVG)
        try check(firstStillOriginalSVG == originalSVG && updatedPlotURL != originalPlotURL
                  && (try Data(contentsOf: originalPlotURL)) == originalSVG
                  && updatedOriginalSVG != originalSVG && updatedSVG == updatedOriginalSVG,
                  "plot then abline creates a new inline SVG while earlier charts retain their original SVG mapping")
        try check(earlierSVGPreserved && svgClipboardMatches(updatedOriginalSVG, label: "Updated chart"),
                  "both SVG clipboard representations and PNG preserve the selected earlier or updated chart version")

        func chartContextMenu(_ index: Int?) async throws -> NSMenu {
            _ = try await doc.web.callAsyncJavaScript("""
            const target = index === null ? document.getElementById('console-input') : document.querySelectorAll('figure.plot img')[index];
            target.dispatchEvent(new MouseEvent('contextmenu', {bubbles:true, cancelable:true, button:2}));
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            return true;
            """, arguments: ["index": index.map { $0 as Any } ?? NSNull()], in: nil, contentWorld: .page)
            let menu = NSMenu()
            menu.addItem(withTitle: "Standard text command", action: nil, keyEquivalent: "")
            pane.extendChartMenu(menu)
            return menu
        }
        func performChartAction(_ menu: NSMenu, _ prefix: String) throws {
            guard let item = menu.items.first(where: { $0.title.hasPrefix(prefix) }), let action = item.action else {
                throw NSError(domain: "RConsoleIntegration", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing native chart menu command: " + prefix])
            }
            guard NSApp.sendAction(action, to: item.target, from: item) else { throw CocoaError(.featureUnsupported) }
        }
        let earlierChartMenu = try await chartContextMenu(0)
        try check(earlierChartMenu.items.map(\.title) == ["Open Chart in New Window", "Copy Chart", "Save Chart as SVG…"],
                  "the injected context-menu bridge replaces inert WebKit image commands with native Open, combined Copy and Save SVG actions")
        try performChartAction(earlierChartMenu, "Copy Chart")
        try check(svgClipboardMatches(originalSVG, label: "Earlier image context-menu copy"),
                  "right-click Copy on an earlier chart copies that exact original SVG rather than the latest chart")
        try performChartAction(earlierChartMenu, "Open Chart")
        try await wait("context-menu original chart window") { vectorWindow.isKeyWindow }
        try check(vectorWindows().count == 1 && vectorBytes(vectorWindow) == originalSVG,
                  "right-click Open targets the selected original chart and reuses its native SVG window")
        viewer.window.makeKeyAndOrderFront(nil)
        try performChartAction(earlierChartMenu, "Save Chart")
        try await wait("native chart Save SVG panel") { viewer.window.attachedSheet is NSSavePanel }
        let cancelledSave = viewer.window.attachedSheet as! NSSavePanel
        try check(cancelledSave.nameFieldStringValue.hasSuffix(".svg") && cancelledSave.allowedContentTypes.contains { $0.identifier == "public.svg-image" },
                  "right-click Save opens a real SVG save dialog instead of downloading an image-data URL")
        cancelledSave.cancel(nil)
        try await wait("cancelled chart Save panel closes") { viewer.window.attachedSheet == nil }
        try check((try Data(contentsOf: originalPlotURL)) == originalSVG,
                  "cancelling Save SVG leaves the original chart file unchanged")
        // Successful Save is checked through the real macOS dialog in desktop
        // QA. Forcing a remote NSSavePanel's acceptance bypasses that UI path.
        let updatedChartMenu = try await chartContextMenu(1)
        try performChartAction(updatedChartMenu, "Copy Chart")
        try check(svgClipboardMatches(updatedOriginalSVG, label: "Updated image context-menu copy"),
                  "the context-menu bridge identifies the updated image separately from its earlier chart version")
        let textMenu = try await chartContextMenu(nil)
        try check(textMenu.items.map(\.title) == ["Standard text command"],
                  "right-clicking ordinary console text retains the supplied standard menu without stale chart actions")
        try await post(doc, "chartContext", fields: ["preview": "data:image/svg+xml;base64,PHN2Zy8+"])
        _ = try await doc.web.callAsyncJavaScript("await new Promise(resolve => requestAnimationFrame(resolve)); return true", arguments: [:], in: nil, contentWorld: .page)
        let unknownMenu = NSMenu(); unknownMenu.addItem(withTitle: "Standard text command", action: nil, keyEquivalent: "")
        pane.extendChartMenu(unknownMenu)
        try check(unknownMenu.items.map(\.title) == ["Standard text command"],
                  "unregistered image previews cannot create native chart commands or access a file")
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
        try await wait("the reused native SVG window") { vectorWindow.isKeyWindow }
        try check(vectorWindows().count == 1 && vectorWindows().first === vectorWindow
                  && vectorBytes(vectorWindow) == originalSVG,
                  "opening an earlier chart after abline reuses its SVG window and preserves that chart version")
        let documentCountBeforeChartClose = viewer.documents.count
        viewer.closeTab()
        try await wait("the SVG window to close") { !vectorWindow.isVisible }
        try check(viewer.documents.count == documentCountBeforeChartClose && viewer.documents.contains { $0 === doc }
                  && pane.session.isRunning,
                  "the native Close command closes the SVG window and retains the R console document and workspace")
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

        try await console(doc, "cat('PALETTE_STDOUT\\n'); warning('PALETTE_WARNING', immediate.=TRUE); stop('PALETTE_ERROR')")
        try await expectOutput(doc, "PALETTE_ERROR")
        try await wait("rendered palette stdout, warning and error") {
            (try await evaluate(doc, "Array.from(document.querySelectorAll('.output-entry.stdout')).some(x=>x.textContent.includes('PALETTE_STDOUT')) && Array.from(document.querySelectorAll('.output-entry.stderr')).some(x=>x.textContent.includes('PALETTE_WARNING') && x.textContent.includes('PALETTE_ERROR'))")) as? Bool == true
        }
        let palette = try await evaluate(doc, """
        (() => {
          const code = Array.from(document.querySelectorAll('.input-entry:not(.reply) pre:not(.echo-prompt)')).find(x=>x.textContent.includes('PALETTE_STDOUT'));
          const echoPrompt = code?.closest('.input-entry').querySelector('.echo-prompt');
          const stdout = Array.from(document.querySelectorAll('.output-entry.stdout')).find(x=>x.textContent.includes('PALETTE_STDOUT'));
          const stderr = Array.from(document.querySelectorAll('.output-entry.stderr')).find(x=>x.textContent.includes('PALETTE_ERROR'));
          const notice = Array.from(document.querySelectorAll('.notice')).find(x=>x.textContent.includes('NUL character'));
          const reply = Array.from(document.querySelectorAll('.input-entry.reply pre:not(.echo-prompt)')).find(x=>x.textContent.includes('chartreuse-reply-token-741'));
          const prompt = document.getElementById('prompt'), input = document.getElementById('console-input');
          const color = node => node ? getComputedStyle(node).color : '';
          const colors = {code:color(code),echoPrompt:color(echoPrompt),prompt:color(prompt),input:color(input),reply:color(reply),stdout:color(stdout),stderr:color(stderr),notice:color(notice)};
          const scriptBefore = StatsDirectRConsole.snapshot().script;
          StatsDirectRConsole.setMode('script'); colors.script = color(document.getElementById('script-source'));
          StatsDirectRConsole.setMode('console');
          return {
            blue:['code','echoPrompt','prompt','input','reply','script'].every(role=>colors[role]==='rgb(6, 69, 173)'),
            stdout:colors.stdout==='rgb(32, 33, 36)',stderr:colors.stderr==='rgb(163, 36, 36)',notice:colors.notice==='rgb(96, 117, 131)',
            markers:echoPrompt?.textContent.trim()==='>' && prompt.textContent.trim()==='>' && stdout?.textContent.includes('PALETTE_STDOUT') && stderr?.textContent.includes('PALETTE_WARNING') && stderr?.textContent.includes('PALETTE_ERROR') && notice?.textContent.includes('NUL character'),
            sourceUnchanged:StatsDirectRConsole.snapshot().script===scriptBefore,colors
          };
        })()
        """) as? [String:Any] ?? [:]
        try check(palette["blue"] as? Bool == true,
                  "echoed R code, replies, prompts, current input and Script editor use the shared dark-blue code color")
        try check(palette["stdout"] as? Bool == true && palette["stderr"] as? Bool == true && palette["notice"] as? Bool == true,
                  "real R stdout is near black, warnings and errors are red, and application notices are muted gray")
        try check(palette["markers"] as? Bool == true && palette["sourceUnchanged"] as? Bool == true,
                  "palette roles retain actual R prompt, output and diagnostic text without changing source")

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
        let clipboardBeforeStaleMenu = board.changeCount
        let windowsBeforeStaleMenu = vectorWindows().count
        for prefix in ["Open Chart", "Copy Chart", "Save Chart"] { try performChartAction(earlierChartMenu, prefix) }
        try await post(doc, "chartContext", fields: ["preview": "data:image/svg+xml;base64," + originalSVG.base64EncodedString()], envelope: oldEnvelope)
        _ = try await doc.web.callAsyncJavaScript("await new Promise(resolve => requestAnimationFrame(resolve)); return true", arguments: [:], in: nil, contentWorld: .page)
        let retiredMenu = NSMenu(); retiredMenu.addItem(withTitle: "Standard text command", action: nil, keyEquivalent: "")
        pane.extendChartMenu(retiredMenu)
        try check(board.changeCount == clipboardBeforeStaleMenu && vectorWindows().count == windowsBeforeStaleMenu
                  && viewer.window.attachedSheet == nil && retiredMenu.items.map(\.title) == ["Standard text command"],
                  "Restart retires old context-menu actions and bridge previews without reopening, copying or saving charts")
        try check((try Data(contentsOf: originalPlotURL)) == originalSVG && (try Data(contentsOf: updatedPlotURL)) == updatedOriginalSVG
                  && svgClipboardMatches(updatedOriginalSVG, label: "Copied chart after Restart"),
                  "Restart retains both original chart files while the combined SVG and PNG clipboard remains available")
        try await post(doc, "submit", fields: ["source": "staleSentinel <- TRUE", "origin": "console"], envelope: oldEnvelope)
        try await console(doc, "cat('RESTART_CLEAR=', !exists('saved') && !exists('scriptValue') && !exists('staleSentinel'), '\\n', sep='')")
        try await expectOutput(doc, "RESTART_CLEAR=TRUE\n")
        try check(!pane.sourceText.contains("staleSentinel <- TRUE"), "retired-generation bridge commands cannot alter the new workspace or script")
        pane.shutdown()
        try check((try Data(contentsOf: originalPlotURL)) == originalSVG && (try Data(contentsOf: updatedPlotURL)) == updatedOriginalSVG
                  && svgClipboardMatches(updatedOriginalSVG, label: "Copied chart after console shutdown"),
                  "closing R retains its original chart assets and leaves both SVG clipboard types and PNG available")

        try await graphicsDeviceChecks(viewer)
    }

    @MainActor static func graphicsDeviceChecks(_ viewer: Viewer) async throws {
        let doc = viewer.makeRConsole(title: "Graphics device checks"), pane = doc.rConsolePane!
        defer { pane.shutdown() }
        try await ready(doc)
        guard let directory = pane.session.workingDirectory else { throw CocoaError(.fileNoSuchFile) }
        sessionFolders.append(directory)
        try await narrowConsoleChecks(viewer, doc)

        var command = 0
        func renderedPlotsReady() async throws {
            try await wait("rendered graphics-device previews match the retained transcript") {
                try await evaluate(doc, """
                (() => {
                  const images = Array.from(document.querySelectorAll('figure.plot img'));
                  const expected = StatsDirectRConsole.snapshot().transcript.filter(entry => entry.kind === 'plot').length;
                  return images.length === expected && images.every(image => image.complete && image.naturalWidth > 0);
                })()
                """) as? Bool == true
            }
        }
        func newPlots(_ source: String) async throws -> [Data] {
            try await renderedPlotsReady()
            let previous = try await evaluate(doc, "document.querySelectorAll('figure.plot img').length") as? Int ?? 0
            command += 1
            let marker = "DEVICE_CASE_\(command)_FINISHED"
            try await console(doc, source + "; cat('\(marker)\\n')")
            try await expectOutput(doc, marker + "\n")
            try await renderedPlotsReady()
            let sources = try await evaluate(doc, "Array.from(document.querySelectorAll('figure.plot img')).slice(\(previous)).map(image => image.src)") as? [String] ?? []
            return try sources.map { source in
                let prefix = "data:image/svg+xml;base64,"
                guard source.hasPrefix(prefix), let data = Data(base64Encoded: String(source.dropFirst(prefix.count))) else {
                    throw NSError(domain: "RConsoleIntegration", code: 8, userInfo: [NSLocalizedDescriptionKey: "A graphics-device preview is not original SVG"])
                }
                _ = try ReportImageClipboard.svgMarkup(data)
                return data
            }
        }
        func contains(_ svg: Data, _ text: String) -> Bool { String(decoding: svg, as: UTF8.self).contains(text) }
        func points(_ svg: Data) -> Int { String(decoding: svg, as: UTF8.self).components(separatedBy: "<circle ").count - 1 }
        func pdfPages(_ name: String) -> Int { PDFDocument(url: directory.appendingPathComponent(name))?.pageCount ?? 0 }

        let closed = try await newPlots("plot(1:3, pch=16, main='Closed final page'); mtext('Final close annotation'); grDevices::dev.off()")
        try check(closed.count == 1 && points(closed[0]) == 3 && contains(closed[0], "Final close annotation"),
                  "qualified dev.off preserves one completed final SVG page and its last annotation in the same submission")
        let characterClosed = try await newPlots("plot(1:3, pch=16, main='Character device close'); characterDeviceID <- dev.cur(); mtext('Character close final'); grDevices::dev.off(as.character(dev.cur()))")
        let afterCharacterClose = try await newPlots("grDevices::pdf('character-reused.pdf'); stopifnot(dev.cur() == characterDeviceID); plot(1:4, pch=16, main='After character close'); mtext('Fresh character ID page'); dev.off()")
        let characterCloseMatches = characterClosed.count == 1 && points(characterClosed[0]) == 3 && contains(characterClosed[0], "Character close final")
                  && afterCharacterClose.count == 1 && points(afterCharacterClose[0]) == 4 && contains(afterCharacterClose[0], "Fresh character ID page")
                  && pdfPages("character-reused.pdf") == 1
        if !characterCloseMatches {
            print("INFO: character close previews=\(characterClosed.count), points=\(characterClosed.map { points($0) }), annotation=\(characterClosed.map { contains($0, "Character close final") }); reused previews=\(afterCharacterClose.count), points=\(afterCharacterClose.map { points($0) }), annotation=\(afterCharacterClose.map { contains($0, "Fresh character ID page") }), PDF pages=\(pdfPages("character-reused.pdf"))")
            fflush(stdout)
        }
        try check(characterCloseMatches,
                  "a character-valued device number closes with its complete annotation and allows the same device ID to register a fresh named PDF page")
        let allClosed = try await newPlots("plot(1:4, pch=16, main='Graphics off final page'); mtext('Final graphics off annotation'); graphics.off()")
        try check(allClosed.count == 1 && points(allClosed[0]) == 4 && contains(allClosed[0], "Final graphics off annotation"),
                  "graphics.off preserves the completed final page without an empty or intermediate preview")

        let pdf = try await newPlots("grDevices::pdf('named-device.pdf'); plot(1:5, pch=16, main='Named PDF page'); mtext('PDF final annotation'); dev.off()")
        try check(pdf.count == 1 && points(pdf[0]) == 5 && contains(pdf[0], "PDF final annotation") && pdfPages("named-device.pdf") == 1,
                  "an explicitly named PDF writes its real one-page file and emits exactly one complete five-point SVG preview")
        let png = try await newPlots("grDevices::png('named-device.png', type='quartz', width=400, height=300); plot(1:6, pch=16, main='Named PNG page'); mtext('PNG final annotation'); dev.off()")
        let pngData = try Data(contentsOf: directory.appendingPathComponent("named-device.png")), bitmap = NSBitmapImageRep(data: pngData)
        try check(png.count == 1 && points(png[0]) == 6 && contains(png[0], "PNG final annotation")
                  && pngData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) && bitmap?.pixelsWide == 400 && bitmap?.pixelsHigh == 300,
                  "an explicitly named native PNG writes a valid 400 by 300 raster and emits exactly one complete six-point SVG preview")
        let svg = try await newPlots("svglite::svglite('named-device.svg'); plot(1:7, pch=16, main='Named SVG page'); mtext('SVG final annotation'); dev.off()")
        let namedSVG = try Data(contentsOf: directory.appendingPathComponent("named-device.svg"))
        _ = try ReportImageClipboard.svgMarkup(namedSVG)
        try check(svg.count == 1 && points(svg[0]) == 7 && contains(svg[0], "SVG final annotation")
                  && points(namedSVG) == 7 && contains(namedSVG, "SVG final annotation"),
                  "an explicitly named SVG retains its real seven-point vector file and emits one complete independent preview")

        let noncurrent = try await newPlots("""
        grDevices::pdf('older-device.pdf'); older <- dev.cur(); plot(1:3, pch=16, main='Older device');
        grDevices::pdf('newer-device.pdf'); newer <- dev.cur(); plot(1:4, pch=16, main='Newer device');
        grDevices::dev.off(which=older); stopifnot(dev.cur() == newer); abline(h=2, col='red');
        mtext('Newer final annotation'); dev.off()
        """)
        try check(noncurrent.count == 2 && points(noncurrent[0]) == 3 && points(noncurrent[1]) == 4
                  && contains(noncurrent[0], "Older device") && !contains(noncurrent[0], "Newer final annotation")
                  && contains(noncurrent[1], "Newer final annotation")
                  && !String(decoding: noncurrent[0], as: UTF8.self).uppercased().contains("#FF0000")
                  && String(decoding: noncurrent[1], as: UTF8.self).uppercased().contains("#FF0000")
                  && pdfPages("older-device.pdf") == 1 && pdfPages("newer-device.pdf") == 1,
                  "closing a named noncurrent device preserves the newer active device and emits no unrelated or duplicate chart")
        let firstReuse = try await newPlots("grDevices::pdf('reused-device.pdf'); reusedID <- dev.cur(); plot(1:3, pch=16, main='Reused device'); dev.off()")
        let retainedSource = try await evaluate(doc, "Array.from(document.querySelectorAll('figure.plot img')).at(-1).src") as? String
        let reusedIndex = try await evaluate(doc, "document.querySelectorAll('figure.plot img').length - 1") as? Int ?? -1
        let secondReuse = try await newPlots("grDevices::pdf('reused-device.pdf'); stopifnot(dev.cur() == reusedID); plot(1:3, pch=16, main='Reused device'); dev.off()")
        let retainedAfterReuse = try await evaluate(doc, "document.querySelectorAll('figure.plot img')[\(reusedIndex)].src") as? String
        try check(firstReuse.count == 1 && secondReuse.count == 1 && points(firstReuse[0]) == 3 && points(secondReuse[0]) == 3
                  && retainedSource != nil && retainedSource == retainedAfterReuse && pdfPages("reused-device.pdf") == 1,
                  "reusing a closed device ID and filename emits a fresh identical page while retaining the earlier chart asset")

        let panels = try await newPlots("par(mfrow=c(1,2)); plot(1:3, pch=16, main='Closed left panel'); plot(3:1, pch=16, main='Closed right panel'); dev.off()")
        try check(panels.count == 1 && points(panels[0]) == 6 && contains(panels[0], "Closed left panel") && contains(panels[0], "Closed right panel"),
                  "closing a completed two-panel base page preserves both panels in one SVG")
        let grid = try await newPlots("grid::grid.newpage(); grid::grid.text('Closed grid first'); grid::grid.newpage(); grid::grid.text('Closed grid second'); graphics.off()")
        try check(grid.count == 2 && contains(grid[0], "Closed grid first") && contains(grid[1], "Closed grid second"),
                  "closing grid graphics preserves both completed physical pages without blank snapshots")
        let cleared = try await newPlots("plot(1:8, pch=16, main='Before globals cleared'); mtext('Private capture survives'); rm(list=ls(all.names=TRUE), envir=.GlobalEnv); dev.off(); stopifnot(length(ls(all.names=TRUE)) == 0)")
        let afterClear = try await newPlots("plot(1:9, pch=16, main='After globals cleared'); mtext('Capture still active'); graphics.off()")
        try check(cleared.count == 1 && points(cleared[0]) == 8 && contains(cleared[0], "Private capture survives")
                  && afterClear.count == 1 && points(afterClear[0]) == 9 && contains(afterClear[0], "Capture still active"),
                  "clearing every learner global leaves private capture active for the closing page and subsequent graphics")
    }

    @MainActor static func narrowConsoleChecks(_ viewer: Viewer, _ doc: Document) async throws {
        let originalFrame = viewer.window.frame, originalMinimum = viewer.window.minSize
        defer { viewer.window.minSize = originalMinimum; viewer.window.setFrame(originalFrame, display: true) }
        viewer.window.minSize = NSSize(width: 300, height: 500)
        try await console(doc, "narrowValue <- 41; cat('NARROW_READY\\n')")
        try await expectOutput(doc, "NARROW_READY\n")
        for width in [420, 320] {
            viewer.window.setContentSize(NSSize(width: CGFloat(width), height: 700))
            try await wait("narrow console width \(width)") {
                let actual = try await evaluate(doc, "window.innerWidth") as? Int ?? 0
                return actual > 200 && actual <= width
            }
            let layout = try await doc.web.callAsyncJavaScript("""
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const toolbar = document.querySelector('.toolbar'); toolbar.scrollLeft = 0;
            const buttons = Array.from(toolbar.querySelectorAll('button'));
            const reachable = buttons.every(button => {
              button.scrollIntoView({block:'nearest', inline:'nearest'});
              const bounds = button.getBoundingClientRect(), clip = toolbar.getBoundingClientRect();
              const hit = document.elementFromPoint((bounds.left+bounds.right)/2, (bounds.top+bounds.bottom)/2);
              return bounds.left >= clip.left-1 && bounds.right <= clip.right+1 && bounds.top >= clip.top && bounds.bottom <= clip.bottom && button.contains(hit);
            });
            const didScroll = toolbar.scrollLeft > 0;
            const noBodyOverflow = document.documentElement.scrollWidth <= document.documentElement.clientWidth+1 && document.body.scrollWidth <= document.documentElement.clientWidth+1;
            const nativeScroll = ['auto','scroll'].includes(getComputedStyle(toolbar).overflowX);
            const scriptTab = document.getElementById('script-tab'); scriptTab.scrollIntoView({block:'nearest', inline:'nearest'}); scriptTab.click();
            const scriptWorks = StatsDirectRConsole.snapshot().mode === 'script' && !document.getElementById('script-panel').hidden && !document.getElementById('script-source').disabled;
            const consoleTab = document.getElementById('console-tab'); consoleTab.scrollIntoView({block:'nearest', inline:'nearest'}); consoleTab.click();
            StatsDirectRConsole.focusInput();
            return {reachable, noBodyOverflow, nativeScroll, didScroll, needsScroll:toolbar.scrollWidth > toolbar.clientWidth,
              scriptWorks, consoleWorks:StatsDirectRConsole.snapshot().mode === 'console' && document.activeElement === document.getElementById('console-input')};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
            try await console(doc, "cat('NARROW_CONSOLE_\(width)=', narrowValue+1, '\\n', sep='')")
            try await expectOutput(doc, "NARROW_CONSOLE_\(width)=42\n")
            let narrowScript = "cat('NARROW_SCRIPT_\(width)=', narrowValue+2, '\\n', sep='')"
            _ = try await evaluate(doc, """
            (() => {
              document.getElementById('script-tab').click();
              const source = document.getElementById('script-source');
              source.value = \(try literal(narrowScript));
              source.setSelectionRange(0,0); source.dispatchEvent(new Event('input', {bubbles:true}));
              document.getElementById('run').scrollIntoView({block:'nearest', inline:'nearest'}); document.getElementById('run').click(); return true;
            })()
            """)
            try await expectOutput(doc, "NARROW_SCRIPT_\(width)=43\n")
            try check(["reachable", "noBodyOverflow", "nativeScroll", "scriptWorks", "consoleWorks"].allSatisfy { layout[$0] as? Bool == true }
                      && (layout["needsScroll"] as? Bool != true || layout["didScroll"] as? Bool == true),
                      "at \(width) points every toolbar control remains reachable by horizontal scroll while Console, Script and the persistent R workspace work without body overflow")
        }
    }

    @MainActor static func readyState(_ doc: Document) async throws -> Bool {
        let current = try await snapshot(doc)
        return doc.rConsolePane?.session.state == "ready" && current["state"] as? String == "ready"
    }
}
