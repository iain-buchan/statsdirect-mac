import Cocoa
import WebKit

extension Viewer {
    /// Whether the operation has an R recipe (Content/R/analysis-recipes.json), read once: for results whose recipe flag the engine
    /// did not supply with their record, such as a report reopened from a file.
    func recipeAvailable(for operation: String) -> Bool {
        if recipeManifestCache == nil { recipeManifestCache = RunRecordR.manifest(resources: root) }
        return !operation.isEmpty && recipeManifestCache?[operation] != nil
    }
    func handleReport(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let web = message.webView, let doc = document(for: web),
              doc.kind == "report", doc.initialURL == nil,
              web.url?.standardizedFileURL.path == root.standardizedFileURL.path,
              let body = message.body as? [String: Any] else { return }
        if let action = body["action"] as? String, ["continueInR", "methodHelp"].contains(action) {
            performReportAction(doc, action: action, resultID: body["resultID"] as? String); return
        }
        editReport(doc, body)
    }
    func performReportAction(_ doc: Document, action: String, resultID: String?) {
        guard let entry = doc.reportEntries?.first(where: { $0.id == resultID }) else {
            // the toolbar's R button with no result to continue (a report with no recorded result): the status line says so, as on Windows
            if action == "continueInR" { status.stringValue = "No result to continue in R: run an analysis into this report first." }
            return
        }
        if action == "continueInR" { openRecordInR(entry) }
        if action == "methodHelp", let path = entry.helpPath ?? (analysisCatalog[entry.operation]?["help"] as? String) {
            openHelp(root.appendingPathComponent(path), title: entry.title)
        }
    }
    @objc func continueActiveReportInR() { if let doc = active { continueReportInR(doc) } }
    func continueResultInR(_ doc: Document, id: String) {
        guard let entry = doc.reportEntries?.first(where: { $0.id == id }) else { status.stringValue = "That result is no longer in the report"; return }
        openRecordInR(entry)
    }
    func continueReportInR(_ report: Document) {
        guard let entry = report.lastRecordEntry else { status.stringValue = "The report has no result with a record of its run to continue in R"; return }
        openRecordInR(entry)
    }
    /// Writes the R script of a result from the record of its run through the engine's writer (reading the worksheet columns the
    /// record points to when it does not hold their values) and opens it in a new R pane; a second click while the first is still
    /// reading does nothing. The script is titled by the record's own title, the operation's friendly name, as on Windows.
    func openRecordInR(_ entry: ReportEntry) {
        guard let record = entry.record else { status.stringValue = "\(entry.title) has no record of its run to continue in R"; return }
        guard !rGenerating.contains(entry.id) else { return }
        rGenerating.insert(entry.id)
        status.stringValue = "Preparing the R script for \(entry.title)…"
        Task { @MainActor in
            defer { self.rGenerating.remove(entry.id) }
            let reader = RecordFrameReader(viewer: self)
            do {
                var frames = try await reader.frames(of: record)
                @MainActor func write() async throws -> [String: Any] {
                    try await withCheckedThrowingContinuation { continuation in
                        self.analysisRequest(["record": record, "title": NSNull(), "frames": frames], entry: "statsdirect_r_script") { continuation.resume(with: $0) }
                    }
                }
                var script = try await write()
                // A column not at its recorded place may have moved along the sheet (output columns written to its left, a column inserted
                // or removed by hand): the engine names the columns it could not match, the band either side of each is read, and the
                // engine looks for the column there by its hash and title, as the Windows reader does.
                if let relocate = script["relocate"] as? [[String: Any]], !relocate.isEmpty {
                    frames = try await reader.candidates(for: relocate, in: frames, of: record)
                    script = try await write()
                }
                await reader.close()   // the engine's copies of closed workbooks go before the script shows
                guard let text = script["text"] as? String else { throw RunRecordR.Failure(message: "the engine wrote no script") }
                self.openReportInR(text: text, title: entry.title, operation: entry.operation, helpPath: entry.helpPath)
                // The Windows report's status lines, with the columns the head's NOTE lines say have changed since the analysis.
                var status = script["dataUnavailable"] as? Bool == true ? "R script opened, but its data could not be read from the workbook: see the head of the script"
                    : script["hasRecipe"] as? Bool == true ? "R script of the analysis opened" : "R script with the data and settings opened"
                let notes = text.components(separatedBy: "\n").prefix { $0.hasPrefix("#") }.filter { $0.hasPrefix("# NOTE:") }
                let changed = notes.filter { $0.contains(" has changed ") }.count, moved = notes.filter { $0.contains(" has moved ") }.count
                if changed > 0 { status += " · \(changed) column\(changed == 1 ? "" : "s") changed since the analysis: see the NOTE lines" }
                if moved > 0 { status += " · \(moved) column\(moved == 1 ? "" : "s") moved along the sheet since the analysis, found again: see the NOTE lines" }
                self.status.stringValue = status
            } catch { await reader.close(); self.showError("The R script could not be generated: " + error.localizedDescription) }
        }
    }
    /// The values of the frames a record points to and does not hold, for the engine's writer, as the Windows FrameReader finds them:
    /// from the grid showing the workbook (by path, then by name), else from the file read through the engine, else the reason; and the
    /// band of columns either side of a column the engine could not match, for the engine to find the column by its hash and title.
    /// Each frame goes to the engine with its index, by which the engine names a column to look for.
    @MainActor final class RecordFrameReader {
        unowned let viewer: Viewer
        var readers: [String: EngineWorkbookReader] = [:]
        private let cacheReads: Bool
        private let maxReadCells: Int?
        private var readCells = 0
        private var readCache: [Data: [[String: Any]]] = [:]
        private struct ReadBudgetFailure: LocalizedError {
            var errorDescription: String? { "Notebook data recovery would read too many worksheet cells. Export fewer analyses in one notebook." }
        }
        static let reach = 64
        init(viewer: Viewer, cacheReads: Bool = false, maxReadCells: Int? = nil) {
            self.viewer = viewer; self.cacheReads = cacheReads
            self.maxReadCells = cacheReads ? maxReadCells.map { max(0, $0) } : nil
        }
        func frames(of record: String) async throws -> [[String: Any]] {
            guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any] else { throw RunRecordR.Failure(message: "the record of the run is not readable") }
            var frames: [[String: Any]] = []
            for (index, request) in RunRecordR.requests(in: object).enumerated() {
                guard let frame = request.frame else { frames.append(["index": index, "name": request.name, "unavailable": RunRecordR.plain(request.unavailable ?? "the record does not say where its columns are")]); continue }
                do { frames.append(["index": index, "name": frame.name, "columns": try await read(frame)]) }
                catch { frames.append(["index": index, "name": frame.name, "unavailable": RunRecordR.plain(error.localizedDescription)]) }
            }
            return frames
        }
        /// The frames with the candidate columns the engine asked for: for each column to look for, the columns within reach to either
        /// side of its recorded place (as many as the cell limit allows), each read with the sheet's own title in its title row when the
        /// pointer has one, over the recorded rows. A band that cannot be read leaves the column as the engine read it.
        func candidates(for relocate: [[String: Any]], in frames: [[String: Any]], of record: String) async throws -> [[String: Any]] {
            guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any] else { return frames }
            let requests = RunRecordR.requests(in: object)
            var result = frames
            var bands: [Int: [Int: [String: Any]]] = [:]   // by frame index, the candidates by column
            for item in relocate {
                guard let index = RunRecordR.integer(item["frame"]), index >= 0, index < requests.count, index < result.count, let frame = requests[index].frame,
                      let place = RunRecordR.integer(item["place"]), let firstRow = RunRecordR.integer(item["firstRow"]), let lastRow = RunRecordR.integer(item["lastRow"]), firstRow >= 1, lastRow >= firstRow else { continue }
                let hasTitle = item["hasTitle"] as? Bool ?? false
                let rows = lastRow - firstRow + 1
                let reach = max(1, min(Self.reach, RunRecordR.maxFrameCells / (2 * max(rows, 1))))
                let columns = ((place - reach)...(place + reach)).filter { $0 != place && (1...RunRecordR.maxColumn).contains($0) && bands[index]?[$0] == nil }
                guard !columns.isEmpty else { continue }
                let band = RunRecordR.Frame(name: frame.name, file: frame.file, path: frame.path, sheet: item["sheet"] as? String ?? frame.sheet,
                                            columns: columns.map { RunRecordR.Pointer(title: "", column: $0, rows: firstRow...lastRow, hasTitle: false) }, blankBeyond: true)
                let texts: [[String: Any]]
                do { texts = try await read(band) }
                catch let error as ReadBudgetFailure { throw error }
                catch { continue }
                for (column, read) in zip(columns, texts) {
                    let values = read["values"] as? [String] ?? [], kinds = read["kinds"] as? [String] ?? []
                    let title: String = values.first ?? ""
                    bands[index, default: [:]][column] = hasTitle
                        ? ["column": column, "title": title, "values": Array(values.dropFirst()), "kinds": Array(kinds.dropFirst())]
                        : ["column": column, "title": "", "values": values, "kinds": kinds]
                }
            }
            for (index, band) in bands { result[index]["candidates"] = band.keys.sorted().map { band[$0]! } }
            return result
        }
        func read(_ frame: RunRecordR.Frame) async throws -> [[String: Any]] {
            guard cacheReads else { return try await readUncached(frame) }
            // Notebook export resolves a selected input once for every result
            // which references it. Ordinary Continue in R keeps its live reads.
            let pointer: [String: Any] = ["file": frame.file, "path": frame.path, "sheet": frame.sheet,
                                          "blankBeyond": frame.blankBeyond,
                                          "columns": frame.columns.map { ["title": $0.title, "column": $0.column,
                                                                          "rows": [$0.rows.lowerBound, $0.rows.upperBound],
                                                                          "hasTitle": $0.hasTitle] }]
            let key = try JSONSerialization.data(withJSONObject: pointer, options: [.sortedKeys])
            if let cached = readCache[key] { return cached }
            if let limit = maxReadCells {
                let first = frame.columns.map(\.firstRow).min() ?? 1
                let last = frame.columns.map(\.rows.upperBound).max() ?? 0
                let span = max(0, last - first + 1)
                let asked = Set(frame.columns.map(\.column)).count.multipliedReportingOverflow(by: span)
                guard !asked.overflow, asked.partialValue <= limit - readCells else { throw ReadBudgetFailure() }
                // Reserve before suspending; a failed read is not retried into
                // an unbounded allocation. Cache hits consume no extra budget.
                readCells += asked.partialValue
            }
            let value = try await readUncached(frame)
            readCache[key] = value
            return value
        }
        private func readUncached(_ frame: RunRecordR.Frame) async throws -> [[String: Any]] {
            if let grid = viewer.documents.first(where: { $0.kind == "grid" && $0.workbookSourceURL?.path == frame.path }) ?? viewer.documents.first(where: { $0.kind == "grid" && $0.workbookName == frame.file }) {
                return try await RunRecordR.read(frame, fromGrid: grid)
            }
            var isDirectory: ObjCBool = false
            guard frame.path.contains("/"), FileManager.default.fileExists(atPath: frame.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  Viewer.excelExtensions.contains(URL(fileURLWithPath: frame.path).pathExtension.lowercased()) else {
                throw RunRecordR.Failure(message: "the workbook \(frame.file) is not open and was not found at \(frame.path)")
            }
            viewer.status.stringValue = "Reading \(frame.file) for R…"
            let reader: EngineWorkbookReader
            if let open = readers[frame.path] { reader = open }
            else {
                reader = EngineWorkbookReader(path: frame.path, snapshotDirectory: SnapshotStore.shared.directory) { [viewer] request in
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in viewer.workbookRequest(request) { continuation.resume(with: $0) } }
                }
                try await reader.open()
                readers[frame.path] = reader
            }
            return try await reader.read(frame)
        }
        func close() async {
            for reader in readers.values { for note in await reader.close() { viewer.status.stringValue = note } }
            readers = [:]
            readCache = [:]
            readCells = 0
        }
    }
    /// The values of the frames the record points to, through a reader of its own (the native checks call this).
    func recordFrames(_ record: String) async throws -> [[String: Any]] {
        let reader = RecordFrameReader(viewer: self)
        do { let frames = try await reader.frames(of: record); await reader.close(); return frames }
        catch { await reader.close(); throw error }
    }
    func openReportInR(text: String, title: String, operation: String? = nil, helpPath: String? = nil) {
        if InteractiveRConsolePrototype.enabled {
            let doc = makeRConsole(script: text, title: title, saved: true, autoRun: true)
            doc.operationName = operation
            if let helpPath { doc.followOnDefinition = ["help": helpPath] }
            status.stringValue = "R console from " + title
            return
        }
        let doc = makeRScript(script: text, title: title, saved: true)
        doc.operationName = operation
        if let helpPath { doc.followOnDefinition = ["help": helpPath] }
        doc.rPane?.runScript()
        status.stringValue = "R script from " + title
    }
}
