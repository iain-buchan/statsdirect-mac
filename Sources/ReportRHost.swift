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
        if body["action"] as? String != "continueInR" { editReport(doc,body);return }
        guard let id = body["resultID"] as? String else { return }
        continueResultInR(doc, id: id)
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
        // R cannot hold U+0000 in a string, and the writer's escape for it stops R's parser before any line of the script runs.
        guard RunRecordR.scriptable(record) else { status.stringValue = "The R script was not written: a title, name or value in the record of \(entry.title) holds a NUL character, which R cannot take"; return }
        guard !rGenerating.contains(entry.id) else { return }
        rGenerating.insert(entry.id)
        status.stringValue = "Preparing the R script for \(entry.title)…"
        Task { @MainActor in
            defer { self.rGenerating.remove(entry.id) }
            do {
                let frames = try await self.recordFrames(record)
                let script: [String: Any] = try await withCheckedThrowingContinuation { continuation in
                    self.analysisRequest(["record": record, "title": NSNull(), "frames": frames], entry: "statsdirect_r_script") { continuation.resume(with: $0) }
                }
                guard let text = script["text"] as? String else { throw RunRecordR.Failure(message: "the engine wrote no script") }
                self.openReportInR(text: text, title: entry.title)
                // The Windows report's status lines, with the columns the head's NOTE lines say have changed since the analysis.
                var status = script["dataUnavailable"] as? Bool == true ? "R script opened, but its data could not be read from the workbook: see the head of the script"
                    : script["hasRecipe"] as? Bool == true ? "R script of the analysis opened" : "R script with the data and settings opened"
                let changed = text.components(separatedBy: "\n").prefix { $0.hasPrefix("#") }.filter { $0.hasPrefix("# NOTE:") }.count
                if changed > 0 { status += " · \(changed) column\(changed == 1 ? "" : "s") changed since the analysis: see the NOTE lines" }
                self.status.stringValue = status
            } catch { self.showError("The R script could not be generated: " + error.localizedDescription) }
        }
    }
    /// The values of the frames the record points to and does not hold, for the engine's writer, as the Windows FrameReader finds
    /// them: from the grid showing the workbook (by path, then by name), else from the file read through the engine, else the reason.
    func recordFrames(_ record: String) async throws -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any] else { throw RunRecordR.Failure(message: "the record of the run is not readable") }
        var frames: [[String: Any]] = []
        var readers: [String: EngineWorkbookReader] = [:]
        for request in RunRecordR.requests(in: object) {
            guard let frame = request.frame else { frames.append(["name": request.name, "unavailable": RunRecordR.plain(request.unavailable ?? "the record does not say where its columns are")]); continue }
            do {
                let columns: [[String: Any]]
                if let grid = documents.first(where: { $0.kind == "grid" && $0.workbookSourceURL?.path == frame.path }) ?? documents.first(where: { $0.kind == "grid" && $0.workbookName == frame.file }) {
                    columns = try await RunRecordR.read(frame, fromGrid: grid)
                } else {
                    var isDirectory: ObjCBool = false
                    guard frame.path.contains("/"), FileManager.default.fileExists(atPath: frame.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                          Self.excelExtensions.contains(URL(fileURLWithPath: frame.path).pathExtension.lowercased()) else {
                        throw RunRecordR.Failure(message: "the workbook \(frame.file) is not open and was not found at \(frame.path)")
                    }
                    status.stringValue = "Reading \(frame.file) for R…"
                    let reader: EngineWorkbookReader
                    if let open = readers[frame.path] { reader = open }
                    else {
                        reader = EngineWorkbookReader(path: frame.path, snapshotDirectory: SnapshotStore.shared.directory) { request in
                            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in self.workbookRequest(request) { continuation.resume(with: $0) } }
                        }
                        try await reader.open()
                        readers[frame.path] = reader
                    }
                    columns = try await reader.read(frame)
                }
                frames.append(["name": frame.name, "columns": columns])
            } catch { frames.append(["name": frame.name, "unavailable": RunRecordR.plain(error.localizedDescription)]) }
        }
        for reader in readers.values { for note in await reader.close() { status.stringValue = note } }
        return frames
    }
    func openReportInR(text: String, title: String) {
        rNumber += 1
        let doc = newDocument(kind: "r", title: "R · \(title) · \(rNumber)")
        let pane = RPane(script: text)
        doc.rPane = pane; doc.item.view = pane.view
        pane.runScript()
        status.stringValue = "R session from " + title
    }
}
