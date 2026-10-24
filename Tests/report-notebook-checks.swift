import Cocoa
import CryptoKit
import WebKit

extension ReportExportTests {
    @MainActor static func notebooks(_ v: Viewer, output: URL) async throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw NSError(domain: "NotebookExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func typed<T>(_ value: Any?, _ label: String) throws -> T {
            guard let value = value as? T else { throw NSError(domain: "NotebookExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid " + label]) }
            return value
        }
        func object(_ data: Data) throws -> [String: Any] { try typed(JSONSerialization.jsonObject(with: data), "JSON object") }
        func encoded(_ value: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
        func js(_ doc: Document, _ code: String) async throws -> Any {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Any, Error>) in
                doc.web.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { c.resume(with: $0) }
            }
        }
        let previous = v.active, previousReport = v.activeReportID
        let report = v.makeReport()
        var grid: Document?
        defer {
            if let grid { v.remove(grid) }
            v.remove(report)
            if let previous, v.documents.contains(where: { $0 === previous }) { v.tabs.selectTabViewItem(previous.item) }
            v.activeReportID = previousReport
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let dataset: [String: Any] = ["complete": true, "rowCount": 9, "columns": [
            ["title": "Before", "index": 0, "values": [312,242,340,388,296,254,391,402,290]],
            ["title": "After", "index": 1, "values": [300,201,232,312,220,256,328,330,231]]]]
        let result = try await TutorTools.run(operation: "TPaired", dataset: dataset, agreement: true, studyType: "neither", preferences: [:]) { request in
            try await withCheckedThrowingContinuation { c in v.analysisRequest(request, entry: "statsdirect_operation") { c.resume(with: $0) } }
        }
        let raw: String = try typed(result["record"], "engine run record")
        let pairedHTML: String = try typed(result["html"], "engine report")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<10 { for x in 0..<20 { bitmap.setColor(NSColor(deviceRed: 0.8, green: 0.1, blue: 0.2, alpha: 1), atX: x, y: y) } }
        let raster = bitmap.representation(using: .png, properties: [:])!.base64EncodedString()
        let vector = "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='40' viewBox='0 0 100 40'><rect width='100' height='40' fill='#237040'/><text x='4' y='22' fill='white'>Vector label</text></svg>"
        let note = "<p id='notebook-note' style='color:#123456'>Original interpretation</p><table style='border-collapse:collapse'><tr><th>Estimate</th><th>Value</th></tr><tr><td style='border:2px solid #123456'>Review</td><td style='text-align:right'>12.50</td></tr></table>"
        let dataOnlyRecord = #"{"version":1,"operation":"NotebookNoRecipe","title":"Data only","run":"2026-10-24T10:00:00+01:00","inputs":[{"name":"data","kind":"entered","columns":[{"title":"Review values","values":[1,2,3]}]}],"parameters":{"gamma":0.95},"values":{"precisionProbe":9007199254740993}}"#
        report.title = "Notebook statistical review"
        report.reportEntries = [ReportEntry(id: "notebook-note", title: "Clinical interpretation", operation: "", body: note, record: nil),
            ReportEntry(id: "notebook-paired", title: "Paired t with agreement", operation: "TPaired", body: pairedHTML, record: raw, recipe: true),
            ReportEntry(id: "notebook-pictures", title: "Imported pictures", operation: "", body: vector + "<img alt='Raster label' src='data:image/png;base64," + raster + "'>", record: nil),
            ReportEntry(id: "notebook-data-only", title: "Imported method without a recipe", operation: "NotebookNoRecipe", body: "<p>Saved results without a matching R recipe.</p>", record: dataOnlyRecord)]
        v.renderReport(report); try await settled(report)
        _ = try await js(report, "const p=document.getElementById('notebook-note');getSelection().selectAllChildren(p);document.execCommand('insertText',false,'Edited clinical interpretation');")
        try await settled(report)
        let beforeHTML: String = try typed(await js(report, "return document.getElementById('report-results').innerHTML;"), "live report HTML")
        let revision = report.reportRevision, undo = report.reportUndo.count, dirty = report.reportDirty, savedURL = report.reportFileURL
        let data = try await v.notebookExportData(report)
        let book = try object(data)
        let metadata: [String: Any] = try typed(book["metadata"], "notebook metadata")
        let meta: [String: Any] = try typed(metadata["statsdirect"], "StatsDirect metadata")
        let cells: [[String: Any]] = try typed(book["cells"], "notebook cells")
        let entries: [[String: Any]] = try typed(meta["entries"], "notebook result entries")
        try require(book["nbformat"] as? Int == 4 && book["nbformat_minor"] as? Int == 5, "standard notebook 4.5")
        let kernel: [String: Any] = try typed(metadata["kernelspec"], "R kernel")
        try require(kernel["name"] as? String == "ir" && kernel["language"] as? String == "R", "R kernel metadata")
        try require(Set(cells.compactMap { $0["id"] as? String }).count == cells.count, "every cell has a unique id")
        let code = cells.filter { $0["cell_type"] as? String == "code" }
        func source(_ cell: [String: Any]) -> String { cell["source"] as? String ?? (cell["source"] as? [String] ?? []).joined() }
        try require(!code.isEmpty && code.allSatisfy { $0["execution_count"] is NSNull && ($0["outputs"] as? [Any])?.isEmpty == true }, "native results never masquerade as executed R output")
        try require(code.contains { source($0).contains("local({") && source($0).contains("t.test(") }, "isolated paired replay includes its data and method")
        try require(entries.count == 4 && entries.compactMap { $0["id"] as? String } == (report.reportEntries ?? []).map(\.id), "notebook retains complete report order")
        try require((meta["reportHtml"] as? String)?.contains("Edited clinical interpretation") == true && (entries[0]["html"] as? String)?.contains("12.50") == true, "edited narrative and formatted tables preserved")
        try require((entries[1]["record"] as? NSDictionary) == (try object(Data(raw.utf8)) as NSDictionary), "complete original record preserved")
        try require((entries[1]["datasets"] as? [Any])?.isEmpty == false, "complete analysis datasets are retained separately")
        try require(entries[3]["hasRecipe"] as? Bool == false && !(entries[3]["replayDetail"] as? String ?? "").isEmpty && String(decoding: data, as: UTF8.self).contains("9007199254740993"), "missing recipe is explicit and original record number precision survives both host boundaries")
        var pngs = 0, vectors = 0
        for cell in cells {
            for (_, value) in cell["attachments"] as? [String: [String: Any]] ?? [:] {
                if let svg = value["image/svg+xml"] as? String { vectors += 1; try require(svg.contains("<svg"), "SVG vector attachment") }
                if let png = value["image/png"] as? String, let bytes = Data(base64Encoded: png), let image = NSBitmapImageRep(data: bytes) {
                    var ink = 0
                    for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide {
                        if let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.1 && min(c.redComponent, c.greenComponent, c.blueComponent) < 0.95 { ink += 1 }
                    } }
                    try require(ink > 10, "notebook PNG fallback contains actual chart pixels"); pngs += 1
                }
            }
        }
        try require(vectors >= 2 && pngs >= 3, "native agreement SVG, imported vector and raster retain portable attachments")
        try require(try await js(report, "return document.getElementById('report-results').innerHTML;") as? String == beforeHTML && report.reportRevision == revision && report.reportUndo.count == undo && report.reportDirty == dirty && report.reportFileURL == savedURL, "export leaves edited report, undo and save destination unchanged")
        try data.write(to: output.appendingPathComponent("review-notebook.ipynb"))
        let fileMenu = NSApp.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu
        let notebookItem = fileMenu?.item(withTitle: "Export Jupyter notebook…")
        try require(notebookItem?.action == #selector(Viewer.exportReportNotebook) && notebookItem.map(v.validateMenuItem) == true, "File menu exposes the report notebook command")
        let exportMenu = fileMenu?.item(withTitle: "Export")?.submenu
        try require(exportMenu?.items.contains(where: { $0.action == #selector(Viewer.saveChartSVG) }) == true && exportMenu?.items.contains(where: { $0.action == #selector(Viewer.exportReportPDF) }) == false && ReportFormat.allCases.map(\.rawValue) == ["html", "pdf", "docx"], "chart and workbook exports remain; report format copies use Save As")
        print("PASS: native notebook capture preserves edited report, tables, SVG/PNG images, original records, complete data and unexecuted isolated R replay"); fflush(stdout)

        // Missing or omitted data must never overwrite the recipient's existing file.
        let destination = output.appendingPathComponent("protected-notebook.ipynb"), sentinel = Data("existing notebook must survive".utf8)
        try sentinel.write(to: destination)
        var captureStarted = false
        let changing = Task { @MainActor in
            captureStarted = true
            try await v.writeReportNotebook(report, to: destination)
        }
        while !captureStarted { await Task.yield() }
        report.reportRevision += 1
        var changedFailure = false
        do { try await changing.value } catch { changedFailure = true }
        try require(changedFailure && (try Data(contentsOf: destination)) == sentinel, "a report changed during capture cannot replace an existing notebook")
        func refuse(_ record: String, _ label: String) async throws {
            report.reportEntries = [ReportEntry(id: "notebook-negative", title: label, operation: "TPaired", body: "<p>" + label + "</p>", record: record)]
            v.renderReport(report); try await settled(report); try sentinel.write(to: destination)
            var failure: String?
            do { try await v.writeReportNotebook(report, to: destination) } catch { failure = error.localizedDescription }
            try require(failure != nil && (try Data(contentsOf: destination)) == sentinel, label + " refuses atomically")
        }
        func record(_ inputs: [[String: Any]], operation: String = "TPaired") throws -> String {
            try encoded(["version": 1, "operation": operation, "rootOperation": operation, "title": operation, "run": "2026-10-24T10:00:00+01:00", "inputs": inputs, "parameters": ["gamma": 0.95], "values": [:]])
        }
        try await refuse(try record([["name": "design", "kind": "frame2d", "value": ["omitted": true]]]), "omitted nested data")
        try await refuse(#"{"version":1,"operation":"TPaired","run":"2026-10-24T10:00:00+01:00","parameters":{}}"#, "malformed record without inputs")
        try await refuse(try record([["name": "data", "kind": "frame", "file": "missing.xlsx", "path": "/not-present/notebook-original.xlsx", "sheet": "Sheet1", "mode": "NumericReplaceMissing", "columns": [["title": "x", "column": 1, "rows": [1,3], "hash": "0000000000000000"]]]]), "unreadable original workbook")
        let huge = try record([["name": "data", "kind": "frame", "file": "must-not-be-read.xlsx", "sheet": "Sheet1", "columns": [1,2].map { ["title": "Large", "column": $0, "rows": [1,1_000_000], "hash": "0000000000000000"] }]])
        report.reportEntries = (1...3).map { ReportEntry(id: "budget-\($0)", title: "Large analysis \($0)", operation: "TPaired", body: "<p>Large analysis</p>", record: huge) }
        v.renderReport(report); try await settled(report); try sentinel.write(to: destination)
        var budgetFailure = ""
        do { try await v.writeReportNotebook(report, to: destination) } catch { budgetFailure = error.localizedDescription }
        try require(budgetFailure.lowercased().contains("fewer analyses") && (try Data(contentsOf: destination)) == sentinel, "whole-report acquisition is refused before reading six million cells")

        // An input omitted by the recipe must still be validated and exported.
        v.newWorksheet(); grid = v.documents.last { $0.kind == "grid" }
        let worksheet: Document = try typed(grid, "notebook worksheet")
        for _ in 0..<100 {
            if (try? await js(worksheet, "return !!window.statsDirectGrid;")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = try await js(worksheet, "await statsDirectGrid.loadWorkbook({name:'Notebook original',sheets:[{name:'Sheet1',columns:3,rows:4,headerRow:true,cells:[{col:0,row:0,text:'Inserted',kind:'text'},{col:1,row:0,text:'Original values',kind:'text'},{col:2,row:0,text:'Additional values',kind:'text'},...[1,2,3].map((x,i)=>({col:1,row:i+1,text:String(x),kind:'number'})),...[4,5,6].map((x,i)=>({col:2,row:i+1,text:String(x),kind:'number'}))]}]});return true;")
        try await settled(worksheet)
        let hash = SHA256.hash(data: Data("1\n2\n3".utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
        let pointer: [String: Any] = ["name": "unused", "kind": "frame", "mode": "NumericReplaceMissing", "file": worksheet.workbookName, "sheet": "Sheet1", "columns": [["title": "Original values", "column": 1, "rows": [1,4], "hasTitle": true, "hash": hash]]]
        var pairedRecord = try object(Data(raw.utf8))
        let pairedInputs: [[String: Any]] = try typed(pairedRecord["inputs"], "paired inputs")
        pairedRecord["inputs"] = pairedInputs + [pointer]
        let withPointer = try encoded(pairedRecord)
        let secondHash = SHA256.hash(data: Data("4\n5\n6".utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
        var secondPointer = pointer
        secondPointer["name"] = "unused second"
        secondPointer["columns"] = [["title": "Additional values", "column": 2, "rows": [1,4], "hasTitle": true, "hash": secondHash]]
        var secondRecord = pairedRecord; secondRecord["inputs"] = pairedInputs + [secondPointer]
        let withSecondPointer = try encoded(secondRecord)
        report.reportEntries = [ReportEntry(id: "moved-input", title: "Moved unused input", operation: "TPaired", body: "<p>Original native results</p>", record: withPointer, recipe: true),
            ReportEntry(id: "second-moved-input", title: "Another workbook input", operation: "TPaired", body: "<p>Another original result</p>", record: withSecondPointer, recipe: true),
            ReportEntry(id: "repeated-input", title: "Repeated source", operation: "TPaired", body: "<p>The same source is read once</p>", record: withPointer, recipe: true)]
        v.renderReport(report); try await settled(report)
        _ = try await js(worksheet, "window.notebookReads=0;const notebookOriginalReader=statsDirectGrid.columnValues;statsDirectGrid.columnValues=(...args)=>{window.notebookReads++;return notebookOriginalReader(...args);};return true;")
        let moved = try await v.notebookExportData(report)
        try require(String(decoding: moved, as: UTF8.self).contains("has moved"), "hash-verified moved input is found and its provenance retained")
        let movedBook = try object(moved)
        let movedMetadata: [String: Any] = try typed(movedBook["metadata"], "moved notebook metadata")
        let movedStats: [String: Any] = try typed(movedMetadata["statsdirect"], "moved provenance")
        let movedEntries: [[String: Any]] = try typed(movedStats["entries"], "moved entries")
        let reads = try await js(worksheet, "return window.notebookReads;") as? Int
        try require(movedEntries.count == 3 && reads == 4, "multi-result relocation maps both sources and reads the repeated range only once (\(reads ?? -1) reads)")
        let limited = Viewer.RecordFrameReader(viewer: v, cacheReads: true, maxReadCells: 1)
        let shortFrame = RunRecordR.Frame(name: "limited", file: worksheet.workbookName, path: "", sheet: "Sheet1", columns: [RunRecordR.Pointer(title: "Original values", column: 2, rows: 2...4, hasTitle: false)])
        var limitedFailure = false
        do { _ = try await limited.read(shortFrame) } catch { limitedFailure = true }
        await limited.close()
        try require(limitedFailure, "candidate/read acquisition budget is enforced before reading a range")
        try moved.write(to: output.appendingPathComponent("moved-notebook.ipynb"))
        _ = try await js(worksheet, "await statsDirectGrid.loadWorkbook({name:'Notebook original',sheets:[{name:'Sheet1',columns:2,rows:4,headerRow:true,cells:[{col:0,row:0,text:'Inserted',kind:'text'},{col:1,row:0,text:'Original values',kind:'text'},...[1,2,99].map((x,i)=>({col:1,row:i+1,text:String(x),kind:'number'}))]}]});return true;")
        try await refuse(withPointer, "changed input omitted by the recipe")
        print("PASS: missing/changed/omitted inputs and report changes preserve existing files; multi-result relocation, read deduplication and report-wide budgets are enforced"); fflush(stdout)
    }
}
