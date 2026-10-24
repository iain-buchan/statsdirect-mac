import Cocoa
import WebKit

extension ReportExportTests {
    @MainActor static func notebookImports(_ v: Viewer, output: URL) async throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw NSError(domain: "NotebookImportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func typed<T>(_ value: Any?, _ name: String) throws -> T {
            guard let value = value as? T else { throw NSError(domain: "NotebookImportTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing " + name]) }
            return value
        }
        func object(_ bytes: Data) throws -> [String: Any] { try typed(JSONSerialization.jsonObject(with: bytes), "JSON object") }
        func encode(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        // JSON's optional \/ escape is valid JavaScript but not an R string.
        func rQuote(_ value: String) -> String { v.jsString(value).replacingOccurrences(of: "\\/", with: "/") }
        func js(_ doc: Document, _ source: String) async throws -> Any? {
            try await withCheckedThrowingContinuation { c in doc.web.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { c.resume(with: $0) } }
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let example = output.appendingPathComponent("review-notebook.ipynb")
        if !FileManager.default.fileExists(atPath: example.path) { try await notebooks(v, output: output) }
        let originalIDs = Set(v.documents.map(\.id)), previous = v.active, oldReport = v.activeReportID, oldSource = v.analysisSourceID
        defer {
            for doc in v.documents.reversed() where !originalIDs.contains(doc.id) { v.remove(doc) }
            if let previous, v.documents.contains(where: { $0 === previous }) { v.tabs.selectTabViewItem(previous.item) }
            v.activeReportID = oldReport; v.analysisSourceID = oldSource
        }
        var book = try object(Data(contentsOf: example))
        var cells: [[String: Any]] = try typed(book["cells"], "exported cells")
        let marker = output.appendingPathComponent("notebook-must-not-autorun.txt")
        try? FileManager.default.removeItem(at: marker)
        var edited = false, changedCode = false
        for i in cells.indices {
            let source = cells[i]["source"] as? String ?? (cells[i]["source"] as? [String] ?? []).joined()
            if source.contains("Edited clinical interpretation") {
                cells[i]["source"] = source.replacingOccurrences(of: "Edited clinical interpretation", with: "Colleague clarified this interpretation")
                edited = true
            }
            if cells[i]["cell_type"] as? String == "code", !changedCode {
                cells[i]["source"] = [source + "\n", "writeLines('NOTEBOOK_IMPORT_MUST_NOT_RUN', " + rQuote(marker.path) + ")\n"]
                cells[i]["outputs"] = [["output_type": "stream", "name": "stdout", "text": ["Saved colleague R output\n"]]]
                cells[i]["execution_count"] = 1; changedCode = true
            }
        }
        try require(edited && changedCode, "fixture edits current report/code cells rather than stale metadata")
        cells.insert(["id": "new-colleague-note", "cell_type": "markdown", "metadata": [:], "source": "## Colleague note\nA **new explanation**.\n<script>window.NOTEBOOK_UNSAFE=true</script><img src='https://example.invalid/tracker.png' onerror='window.NOTEBOOK_UNSAFE=true'>"], at: 0)
        book["cells"] = cells
        let source = output.appendingPathComponent("colleague-edits.ipynb"), bytes = try encode(book)
        try bytes.write(to: source)
        let before = Set(v.documents.map(\.id))
        let report = try await v.importNotebook(source)
        let opened = v.documents.filter { !before.contains($0.id) }
        try require(opened.filter { $0.kind == "report" }.count == 1 && opened.filter { $0.kind == "r" }.count == 1 && opened.filter { $0.kind == "grid" }.count == 1, "one report, R script and recovered data workbook open")
        let script: Document = try typed(opened.first { $0.kind == "r" }, "recovered R script")
        let grid: Document = try typed(opened.first { $0.kind == "grid" }, "recovered data workbook")
        try require(report.title == "colleague-edits" && report.reportDirty && report.reportEditing && report.reportFileURL == nil && grid.gridDirty && grid.openedFileURL == nil && grid.workbookSourceURL == nil && script.openedFileURL == nil && script.rPane?.hasUnsavedChanges == true, "import creates editable unsaved copies named for the current notebook file")
        try require(script.rPane?.language == "R" && script.rPane?.editor.string.contains("NOTEBOOK_IMPORT_MUST_NOT_RUN") == true && script.rPane?.isRunning == false && script.rPane?.console.string.isEmpty == true && !FileManager.default.fileExists(atPath: marker.path), "current edited R code is restored without execution")
        try require(v.active === report && v.window.firstResponder !== script.rPane?.editor, "the selected report does not leave keyboard focus in the hidden script editor")
        let visible: String = try typed(await js(report, "return document.getElementById('report-results').innerText;"), "recovered report text")
        try require(visible.contains("Colleague clarified this interpretation") && visible.contains("new explanation") && visible.contains("Saved colleague R output") && !visible.contains("Edited clinical interpretation"), "current notebook cells and saved R output replace stale metadata report text")
        let safe = try await js(report, "return !document.querySelector('.report-body script,.report-body img[src^=http]') && !window.NOTEBOOK_UNSAFE && document.querySelectorAll('.report-body svg').length>=2 && document.querySelectorAll('.report-body img').length>=1;") as? Bool
        try require(safe == true, "Markdown and attachments are sanitized; SVG/raster charts survive without external images or scripts")
        try require(report.notebookImportProvenance?.contains("Edited clinical interpretation") == true && (try Data(contentsOf: source)) == bytes, "original provenance stays separate and the source notebook is unchanged")
        let info: [String: Any] = try typed(await js(grid, "return statsDirectGrid.tutorInfo();"), "recovered grid information")
        try require((info["sheets"] as? [[String: Any]])?.isEmpty == false, "embedded datasets are loaded as data worksheets")
        let html = output.appendingPathComponent("notebook-recovered.html")
        try await v.reportExportData(report, format: .html).write(to: html)
        let reopened = try await v.importReport(html); try await settled(reopened)
        try require(reopened.notebookImportProvenance == report.notebookImportProvenance && reopened.reportEntries?.contains(where: { $0.operation == "TPaired" && $0.record != nil }) == true, "HTML save/reopen retains raw notebook provenance and native replay records")

        // The exported moved-input example has no original workbook on disk or
        // in this fresh workspace. Import must restore held data for replay.
        let moved = try await v.importNotebook(output.appendingPathComponent("moved-notebook.ipynb"))
        let paired: ReportEntry = try typed(moved.reportEntries?.first { $0.operation == "TPaired" && $0.record != nil }, "restored paired record")
        let record: String = try typed(paired.record, "restored run record")
        let requests = try await v.recordFrames(record)
        try require(requests.isEmpty, "rehydrated records need no original workbook")
        let replay: [String: Any] = try await withCheckedThrowingContinuation { c in v.analysisRequest(["record": record, "frames": []], entry: "statsdirect_r_script") { c.resume(with: $0) } }
        let code: String = try typed(replay["text"], "rehydrated R replay")
        try require(replay["hasRecipe"] as? Bool == true && replay["dataUnavailable"] as? Bool == false && (replay["asked"] as? [String])?.isEmpty == true && code.contains("t.test("), "Continue in R writes a complete analysis from the imported data")
        try Data(("pdf(" + rQuote(output.appendingPathComponent("imported-replay.pdf").path) + ")\n" + code + "\ndev.off()\n").utf8).write(to: output.appendingPathComponent("imported-replay.R"))

        let typedSource = v.makeReport()
        let textRecord = #"{"version":1,"operation":"NotebookTypedData","title":"Typed data","run":"2026-10-24T10:00:00+01:00","inputs":[{"name":"data","kind":"entered","columns":[{"title":"Mixed values","values":[1.25,null,true,false,"=1+2","2026-10-24","00123"]}]}],"parameters":{},"values":{}}"#
        typedSource.reportEntries = [ReportEntry(id: "typed-data", title: "Typed data", operation: "NotebookTypedData", body: "<p>Typed data preservation</p>", record: textRecord)]
        v.renderReport(typedSource); try await settled(typedSource)
        let typedURL = output.appendingPathComponent("typed-notebook.ipynb")
        try await v.notebookExportData(typedSource).write(to: typedURL)
        let beforeTyped = Set(v.documents.map(\.id)); _ = try await v.importNotebook(typedURL)
        let typedGrid: Document = try typed(v.documents.first { !beforeTyped.contains($0.id) && $0.kind == "grid" }, "typed restored worksheet")
        let values: [String: Any] = try typed(await js(typedGrid, "return statsDirectGrid.columnValues({sheet:0,columns:[0],first:2,last:8});"), "typed values")
        let columns: [[String: Any]] = try typed(values["columns"], "typed columns")
        let restoredValues: [Any] = try typed(columns.first?["values"], "typed cells")
        let kinds: [String] = try typed(columns.first?["kinds"], "typed cell kinds")
        try require(restoredValues.count == 7 && kinds[0] == "number" && kinds[1] == "blank" && kinds[2] == "boolean" && kinds[4] == "text" && kinds[5] == "text" && restoredValues[4] as? String == "=1+2" && restoredValues[6] as? String == "00123", "numbers, missing values, booleans and literal formula/date/identifier text are recovered without coercion")

        // As on Windows, a notebook whose R cells were all deleted opens its report and data without a script tab.
        var codeless = try object(Data(contentsOf: example))
        codeless["cells"] = (try typed(codeless["cells"], "exported cells") as [[String: Any]]).filter { $0["cell_type"] as? String != "code" }
        let codelessURL = output.appendingPathComponent("codeless-notebook.ipynb"); try encode(codeless).write(to: codelessURL)
        let beforeCodeless = Set(v.documents.map(\.id)); _ = try await v.importNotebook(codelessURL)
        let codelessOpened = v.documents.filter { !beforeCodeless.contains($0.id) }
        try require(codelessOpened.contains { $0.kind == "report" } && codelessOpened.contains { $0.kind == "grid" } && !codelessOpened.contains { $0.kind == "r" }, "a notebook without R code opens its report and data but no script tab, as on Windows")

        // Invalid formats and cancellation must retain all existing work.
        var rejected = book
        rejected["metadata"] = ["kernelspec": ["name": "python3", "language": "python", "display_name": "Python"]]
        let bad = output.appendingPathComponent("unsupported-notebook.ipynb"); try encode(rejected).write(to: bad)
        let keep = Set(v.documents.map(\.id)), keepActive = v.active?.id, keepReport = v.activeReportID, keepData = v.analysisSourceID
        var refused = false
        do { _ = try await v.importNotebook(bad) } catch { refused = true }
        try require(refused && Set(v.documents.map(\.id)) == keep && v.active?.id == keepActive && v.activeReportID == keepReport && v.analysisSourceID == keepData, "unsupported notebooks fail without changing the workspace")
        let oldSnapshots = Set(try FileManager.default.contentsOfDirectory(atPath: SnapshotStore.shared.directory.path))
        let cancelled = Task { @MainActor in try await v.importNotebook(source) }
        var staged = false
        for _ in 0..<500 {
            let files = Set(try FileManager.default.contentsOfDirectory(atPath: SnapshotStore.shared.directory.path))
            if !files.subtracting(oldSnapshots).isEmpty { staged = true; cancelled.cancel(); break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        var cancellation = false
        do { _ = try await cancelled.value } catch { cancellation = true }
        try require(staged && cancellation && Set(v.documents.map(\.id)) == keep && Set(try FileManager.default.contentsOfDirectory(atPath: SnapshotStore.shared.directory.path)) == oldSnapshots, "cancelled staged import rolls back only its own documents and snapshot files")
        try require(!FileManager.default.fileExists(atPath: marker.path) && (try Data(contentsOf: source)) == bytes, "all import paths leave original notebook and unexecuted code untouched")
        print("PASS: notebook opening restores current report/code/data, sanitized images and saved output; original files and prior workspace survive errors/cancellation"); fflush(stdout)

        // Restored data may exceed the old record-only4MB cap while the whole
        // report is still within the30MB saved-HTML envelope.
        let longValues = Array(repeating: String(repeating: "a", count: 4500), count: 1000)
        let longObject: [String: Any] = ["version": 1, "operation": "NotebookText", "title": "Long held data", "run": "2026-10-24T10:00:00+01:00", "inputs": [["name": "data", "kind": "entered", "columns": [["title": "Text", "values": longValues]]]], "parameters": [:], "values": [:]]
        let longRaw = String(decoding: try encode(longObject), as: UTF8.self)
        let wholeRaw = #"{"version":1,"operation":"NotebookHeld","title":"Held whole column","run":"2026-10-24T10:00:00+01:00","inputs":[{"name":"data","kind":"frame","file":"absent.xlsx","sheet":"Data","columns":[{"title":"x","column":1,"rows":[1,-1]}]}],"data":{"data":{"x":[1,2,3]}},"parameters":{},"values":{}}"#
        try require(longRaw.utf8.count > 4_000_000 && RunRecordR.validated(longRaw) == longRaw && RunRecordR.validated(wholeRaw) == wholeRaw, "large records, long cell strings and held whole-column provenance remain valid")
        var unheld = try object(Data(wholeRaw.utf8)); unheld.removeValue(forKey: "data")
        try require(RunRecordR.validated(String(decoding: try encode(unheld), as: UTF8.self)) == nil, "unresolved negative-row pointers remain rejected")
        typedSource.reportEntries = [ReportEntry(id: "long-text", title: "Long text data", operation: "NotebookText", body: "<p>Long recovered text</p>", record: longRaw), ReportEntry(id: "held-whole", title: "Held column", operation: "NotebookHeld", body: "<p>Whole column provenance</p>", record: wholeRaw)]
        v.renderReport(typedSource); try await settled(typedSource)
        let archive = output.appendingPathComponent("large-recovered-records.html")
        try await v.reportExportData(typedSource, format: .html).write(to: archive)
        let restored = try await v.importReport(archive)
        try require(restored.reportEntries?.contains(where: { $0.record == longRaw }) == true && restored.reportEntries?.contains(where: { $0.record == wholeRaw }) == true, "HTML round trip retains complete recovered records beyond4MB and whole-column held data")
        print("PASS: recovered records retain large/long data and held whole-column provenance through HTML save/reopen"); fflush(stdout)
    }
}
