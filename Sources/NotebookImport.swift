import Cocoa
import WebKit

extension Viewer {
    func openNotebookURL(_ url: URL) {
        status.stringValue = "Opening \(url.lastPathComponent)…"
        Task { @MainActor in
            do {
                let report = try await importNotebook(url)
                didOpenDocument(report, url: url)
                status.stringValue = "Opened \(url.lastPathComponent) · Recovered copies; R has not run"
            } catch { showError("The notebook could not be opened: " + error.localizedDescription) }
        }
    }

    /// Prepare all content and data offscreen before changing the workspace.
    /// The notebook itself is never a save destination for the recovered files.
    @discardableResult func importNotebook(_ url: URL) async throws -> Document {
        guard url.isFileURL else { throw ReportNotebook.Failure(message: "Open a notebook saved on this computer.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximumBytes = 90_000_000
        var bytes = Data()
        while bytes.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(1_048_576, maximumBytes + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        guard bytes.count <= maximumBytes else { throw ReportNotebook.Failure(message: "This notebook exceeds the 90 MB import limit. Split it into smaller notebooks first.") }
        guard var text = String(data: bytes, encoding: .utf8) else { throw ReportNotebook.Failure(message: "The notebook must contain UTF-8 JSON text.") }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let fallback = url.deletingPathExtension().lastPathComponent
        let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            analysisRequest(["notebookImport": text, "title": fallback], entry: "statsdirect_r_script") { continuation.resume(with: $0) }
        }
        guard let raw = response["notebookImport"] as? String,
              let plan = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              plan["title"] is String,
              let entries = plan["entries"] as? [[String: Any]],
              let script = plan["script"] as? String,
              let tables = plan["tables"] as? [[String: Any]],
              let provenance = plan["provenance"] as? String,
              (try JSONSerialization.jsonObject(with: Data(provenance.utf8))) is [String: Any] else {
            throw ReportNotebook.Failure(message: "The notebook importer returned an incomplete recovery plan.")
        }
        let title = fallback
        let converted = try await ReportImporter.convertNotebook(entries: entries, resources: root)
        guard let rendered = converted["entries"] as? [[String: Any]], rendered.count == entries.count else {
            throw ReportNotebook.Failure(message: "The notebook's report sections could not be recovered.")
        }
        var warnings = plan["warnings"] as? [String] ?? []
        for warning in converted["warnings"] as? [String] ?? [] where !warnings.contains(warning) { warnings.append(warning) }
        let notes = warnings.isEmpty ? "" : "<aside class='report-import-warning'><strong>Notebook import notes</strong><ul>" + warnings.map { "<li>\(htmlEscape($0))</li>" }.joined() + "</ul></aside>"
        var recovered: [ReportEntry] = []
        var reportBytes = notes.utf8.count
        for (index, pair) in zip(entries, rendered).enumerated() {
            let (entry, page) = pair
            guard let body = page["html"] as? String else { throw ReportNotebook.Failure(message: "A notebook report section is unreadable.") }
            reportBytes += body.utf8.count
            guard reportBytes <= 30_000_000 else { throw ReportNotebook.Failure(message: "The recovered report exceeds 30 MB. Split the notebook into smaller reports first.") }
            let record: String?
            if let given = entry["record"], !(given is NSNull) {
                guard let raw = given as? String, (try JSONSerialization.jsonObject(with: Data(raw.utf8))) is [String: Any] else {
                    throw ReportNotebook.Failure(message: "A recovered analysis has an unreadable run record.")
                }
                record = raw
            } else { record = nil }
            let operation = entry["operation"] as? String ?? ""
            recovered.append(ReportEntry(id: UUID().uuidString, title: entry["title"] as? String ?? title,
                                         operation: operation, body: (index == 0 ? notes : "") + body,
                                         record: record, recipe: record != nil && recipeAvailable(for: operation),
                                         helpPath: savedHelpPath(entry["helpPath"] as? String ?? analysisCatalog[operation]?["help"] as? String)))
        }
        if recovered.isEmpty, !notes.isEmpty {
            recovered = [ReportEntry(id: UUID().uuidString, title: title, operation: "", body: notes, record: nil)]
        }

        var prepared = try prepareNotebookWorkbook(tables, title: title)
        var staged: [Document] = []
        var committed: [Document] = []
        let previous = active
        let previousReport = activeReportID
        let previousSource = analysisSourceID
        do {
            try Task.checkCancellation()
            let report = Document(kind: "report", title: title, access: root)
            staged.append(report)
            report.web.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            report.web.configuration.userContentController.add(self, name: "statsDirectReport")
            report.reportEntries = recovered
            report.reportRevision = 1; report.reportSavedRevision = 0
            report.notebookImportProvenance = provenance
            report.reportImportNotice = "Imported from a StatsDirect notebook. Save recovered reports, data and scripts as new files; the notebook is unchanged."
            renderReport(report)
            try await notebookViewReady(report, expression: "typeof StatsDirectReportEditor !== 'undefined' && !!document.getElementById('report-results') && document.getElementById('report-results').isContentEditable")
            var grid: Document?
            if var workbook = prepared.workbook {
                let data = Document(kind: "grid", title: title + " · Data", access: root)
                grid = data; staged.append(data)
                data.web.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
                data.workbookName = workbook["name"] as? String ?? title + ".xlsx"
                data.gridDirty = true; data.gridVersion = 1
                data.web.configuration.userContentController.add(self, name: "statsDirectGrid")
                data.initialURL = root.appendingPathComponent("Grid/index.html")
                data.web.loadFileURL(data.initialURL!, allowingReadAccessTo: root)
                try await notebookViewReady(data, expression: "!!window.statsDirectGrid && typeof window.statsDirectGrid.loadWorkbook === 'function'")
                stageSnapshots(in: &workbook, for: data)
                let loaded = try await NotebookImportJavaScript.call(data.web, script: "return await window.statsDirectGrid.loadWorkbook(data)", arguments: ["data": workbook])
                let expected = (workbook["sheets"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                guard let loaded = loaded as? [String: Any], RunRecordR.integer(loaded["sheets"]) == expected.count,
                      let info = try await NotebookImportJavaScript.call(data.web, script: "return window.statsDirectGrid.tutorInfo()", arguments: [:]) as? [String: Any],
                      info["workbook"] as? String == data.workbookName,
                      (info["sheets"] as? [[String: Any]])?.compactMap({ $0["name"] as? String }) == expected,
                      data.web.url?.standardizedFileURL == data.initialURL?.standardizedFileURL else {
                    throw ReportNotebook.Failure(message: "The recovered data could not be loaded completely. Nothing has been opened.")
                }
                for id in data.snapshotIDs { SnapshotStore.shared.forget(id) }; data.snapshotIDs = []
            }
            try Task.checkCancellation()
            // No suspension or fallible parsing follows the commit. Delaying
            // tab selection also avoids changing the active data scope while
            // an import may still fail.
            for document in staged {
                document.web.navigationDelegate = self; document.web.uiDelegate = self
                documents.append(document); tabs.addTabViewItem(document.item); committed.append(document)
            }
            let r = makeRScript(script: script, title: title + " · Notebook", saved: false)
            committed.append(r); r.rPane?.setLanguage("R")
            r.rPane?.state.stringValue = "Imported from notebook · Choose Run to execute the script"
            if let grid { analysisSourceID = grid.id }
            activeReportID = report.id
            tabs.selectTabViewItem(report.item); updateWindowMenu()
            prepared.files = []
            return report
        } catch {
            for document in committed.reversed() where documents.contains(where: { $0 === document }) { remove(document) }
            for document in staged where !documents.contains(where: { $0 === document }) {
                document.web.stopLoading()
                document.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectReport")
                document.web.configuration.userContentController.removeScriptMessageHandler(forName: "statsDirectGrid")
                for id in document.snapshotIDs { SnapshotStore.shared.forget(id) }; document.snapshotIDs = []
            }
            for file in prepared.files { try? FileManager.default.removeItem(at: file) }
            if let previous, documents.contains(where: { $0 === previous }) { tabs.selectTabViewItem(previous.item) }
            activeReportID = previousReport; analysisSourceID = previousSource
            throw error
        }
    }

    private func notebookViewReady(_ doc: Document, expression: String) async throws {
        let end = Date().addingTimeInterval(30)
        while Date() < end {
            try Task.checkCancellation()
            if !doc.web.isLoading, (try? await NotebookImportJavaScript.call(doc.web, script: "return " + expression, arguments: [:])) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ReportNotebook.Failure(message: "The recovered notebook view did not finish loading. Try opening the notebook again.")
    }

    private func prepareNotebookWorkbook(_ tables: [[String: Any]], title: String) throws -> (workbook: [String: Any]?, files: [URL]) {
        guard !tables.isEmpty else { return (nil, []) }
        var count = 0
        for table in tables {
            guard let columns = table["columns"] as? [[String: Any]], !columns.isEmpty, columns.count <= RunRecordR.maxColumn else {
                throw ReportNotebook.Failure(message: "A recovered table has too many columns or no usable columns.")
            }
            for column in columns {
                guard let values = column["values"] as? [Any], values.count < RunRecordR.maxRow else {
                    throw ReportNotebook.Failure(message: "A recovered table has too many rows to include its column headings in a worksheet.")
                }
                guard values.count <= RunRecordR.maxRecordCells - count else {
                    throw ReportNotebook.Failure(message: "The recovered notebook contains more than five million data values. Split it into smaller notebooks first.")
                }
                count += values.count
                guard values.allSatisfy({ value in
                    value is NSNull || value is String || ((value as? NSNumber).map { $0.doubleValue.isFinite } ?? false)
                }) else { throw ReportNotebook.Failure(message: "A recovered table contains a value that cannot be represented in a data worksheet.") }
            }
        }
        var files: [URL] = [], sheets: [[String: Any]] = [], names = Set<String>()
        do {
            for (index, table) in tables.enumerated() {
                let original = table["title"] as? String ?? "Data \(index + 1)"
                let cleaned = original.replacingOccurrences(of: "[\\\\/?:*\\[\\]\\x00-\\x1f]", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'")))
                let base = String(cleaned.prefix(31))
                let stem = base.isEmpty ? "Data \(index + 1)" : base
                var name = stem, suffix = 2
                while !names.insert(name.lowercased()).inserted { let tail = " (\(suffix))"; name = String(stem.prefix(31 - tail.count)) + tail; suffix += 1 }
                let columns = table["columns"] as! [[String: Any]]
                var snapshot = SnapshotSheet(name: name, columns: [])
                var rows = 1
                for (c, column) in columns.enumerated() {
                    let values = column["values"] as! [Any]
                    rows = max(rows, values.count + 1)
                    var saved = SnapshotColumn(col: c)
                    saved.rows = [0]; saved.kinds = [2]; saved.nums = [.nan]
                    saved.texts[0] = column["title"] as? String ?? "Column \(c + 1)"
                    for (row, value) in values.enumerated() {
                        guard !(value is NSNull) else { continue }
                        let ordinal = saved.rows.count
                        saved.rows.append(UInt32(row + 1))
                        if let number = value as? NSNumber {
                            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                                saved.kinds.append(5); saved.nums.append(.nan); saved.texts[ordinal] = number.boolValue ? "TRUE" : "FALSE"
                            } else { saved.kinds.append(1); saved.nums.append(number.doubleValue) }
                        } else {
                            // ISO-looking strings remain strings. The notebook
                            // schema does not distinguish them from date text.
                            saved.kinds.append(2); saved.nums.append(.nan); saved.texts[ordinal] = value as? String ?? ""
                        }
                    }
                    snapshot.columns.append(saved)
                }
                let file = SnapshotStore.shared.directory.appendingPathComponent("notebook-" + UUID().uuidString + ".sdcol")
                try Snapshot.encode([snapshot]).write(to: file, options: .atomic); files.append(file)
                sheets.append(["name": name, "hidden": false, "headerRow": true, "rows": rows, "csvRows": rows,
                               "columns": columns.count, "cells": [], "snapshot": file.path])
            }
            return (["name": title + " · Data.xlsx", "formulaCount": 0, "sheets": sheets], files)
        } catch { for file in files { try? FileManager.default.removeItem(at: file) }; throw error }
    }
}

/// A bounded, single-completion JavaScript call for unregistered staging views.
@MainActor private final class NotebookImportJavaScript {
    private var continuation: CheckedContinuation<Any?, Error>?
    private var timer: DispatchWorkItem?
    private var keepAlive: NotebookImportJavaScript?
    static func call(_ web: WKWebView, script: String, arguments: [String: Any]) async throws -> Any? {
        let call = NotebookImportJavaScript()
        return try await withCheckedThrowingContinuation { call.start(web, script: script, arguments: arguments, continuation: $0) }
    }
    private func start(_ web: WKWebView, script: String, arguments: [String: Any], continuation: CheckedContinuation<Any?, Error>) {
        self.continuation = continuation; keepAlive = self
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(ReportNotebook.Failure(message: "The recovered notebook view stopped responding. Try opening it again."))) }
        timer = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value): self?.finish(.success(value))
            case .failure(let error): self?.finish(.failure(error))
            }
        }
    }
    private func finish(_ result: Result<Any?, Error>) {
        guard let continuation else { return }; self.continuation = nil
        timer?.cancel(); timer = nil; keepAlive = nil
        continuation.resume(with: result)
    }
}
