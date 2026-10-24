import Cocoa
import WebKit
import UniformTypeIdentifiers

extension Viewer {
    /// Notebook export is a copy for statistical review. It never changes the
    /// report's own HTML destination, dirty flag or edit history.
    @objc func exportReportNotebook() {
        guard let doc = active, doc.kind == "report", !doc.fileBusy else { return }
        guard !doc.web.isLoading else {
            showError("Wait for the report to finish loading, then export the notebook.")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Jupyter Notebook"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType(filenameExtension: "ipynb", conformingTo: .json)!]
        panel.isExtensionHidden = false
        let stem = doc.reportFileURL?.deletingPathExtension().lastPathComponent ?? doc.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = stem + ".ipynb"
        if let folder = doc.reportFileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, !doc.fileBusy else { return }
            doc.fileBusy = true
            self.status.stringValue = "Preparing Jupyter notebook…"
            Task { @MainActor in
                defer { doc.fileBusy = false }
                do {
                    try await self.writeReportNotebook(doc, to: url)
                    self.status.stringValue = "Exported " + url.lastPathComponent
                } catch {
                    self.showError("The notebook could not be exported: " + error.localizedDescription)
                }
            }
        }
    }

    /// Everything that can fail (report capture, complete input recovery,
    /// validation and serialization) finishes before replacing a destination.
    func writeReportNotebook(_ doc: Document, to url: URL) async throws {
        let revision = doc.reportRevision
        let entries = doc.reportEntries ?? []
        let title = doc.title
        let data = try await notebookExportData(doc)
        try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
        try data.write(to: url, options: .atomic)
    }

    func notebookExportData(_ doc: Document) async throws -> Data {
        guard doc.kind == "report", !doc.web.isLoading else {
            throw ReportNotebook.Failure(message: "Wait for the report to finish loading, then export the notebook.")
        }
        let revision = doc.reportRevision
        let entries = doc.reportEntries ?? []
        let title = doc.title
        let ids = entries.map(\.id)
        try notebookInputPreflight(entries)
        let captured = try await notebookSnapshot(doc, title: title)
        try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
        guard captured["idsBefore"] as? [String] == ids,
              captured["idsAfter"] as? [String] == ids,
              let html = captured["html"] as? String,
              let rendered = captured["entries"] as? [[String: Any]], rendered.count == entries.count else {
            throw ReportNotebook.Failure(message: "The report changed while preparing the notebook. Wait for editing to finish, then export again.")
        }
        var results: [[String: Any]] = []
        var supplied: [[String: Any]] = []
        // A record's local request order is kept separately from the global
        // frame ids returned by the bridge's relocation pass.
        var groups: [(record: String, frames: [[String: Any]], global: [Int])] = []
        let reader = RecordFrameReader(viewer: self, cacheReads: true, maxReadCells: 2 * RunRecordR.maxRecordCells)
        do {
            for (entry, page) in zip(entries, rendered) {
                guard let body = page["html"] as? String,
                      let cells = page["cells"] as? [[String: Any]] else {
                    throw ReportNotebook.Failure(message: "The report returned an incomplete notebook snapshot. Try exporting again.")
                }
                var result: [String: Any] = ["id": entry.id, "title": entry.title, "operation": entry.operation, "html": body, "cells": cells]
                if let record = entry.record {
                    guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any] else {
                        throw ReportNotebook.Failure(message: "The record for \(entry.title) is unreadable. Rerun the analysis, then export again.")
                    }
                    // Keep the record as exact JSON text across the Swift bridge;
                    // C# parses it without a floating-point Foundation round trip.
                    result["record"] = record
                    let held = object["data"] as? [String: Any] ?? [:]
                    var pointers: [[String: Any]] = []
                    if let given = object["inputs"], !(given is NSNull) {
                        guard let inputs = given as? [[String: Any]] else {
                            throw ReportNotebook.Failure(message: "The inputs for \(entry.title) are unreadable. Rerun the analysis, then export again.")
                        }
                        for input in inputs where input["kind"] as? String == "frame" {
                            guard let name = input["name"] as? String, !name.isEmpty else {
                                throw ReportNotebook.Failure(message: "An input for \(entry.title) has no name. Rerun the analysis, then export again.")
                            }
                            let key = input["held"] as? String ?? name
                            if let kept = held[key] {
                                guard kept is [String: Any] else {
                                    throw ReportNotebook.Failure(message: "Saved data for \(entry.title) are incomplete. Reopen the original workbook and rerun the analysis before exporting.")
                                }
                            } else { pointers.append(input) }
                        }
                    }
                    let frames = try await reader.frames(of: record)
                    try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
                    guard frames.count == pointers.count else {
                        throw ReportNotebook.Failure(message: "The data for \(entry.title) could not be matched to their record. Reopen the original workbook and rerun the analysis before exporting.")
                    }
                    var global: [Int] = []
                    for (pointer, frame) in zip(pointers, frames) {
                        let index = supplied.count
                        var indexed = frame; indexed["index"] = index
                        supplied.append(["pointer": pointer, "frame": indexed]); global.append(index)
                    }
                    groups.append((record, frames, global))
                }
                results.append(result)
                try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
            }
            let snapshot: [String: Any] = ["version": 1, "reportHtml": html, "entries": results, "revision": revision, "engineVersion": engineVersion]
            @MainActor func request() async throws -> [String: Any] {
                let body: [String: Any] = ["notebook": snapshot, "title": title, "frames": supplied,
                                           "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"]
                return try await withCheckedThrowingContinuation { continuation in
                    analysisRequest(body, entry: "statsdirect_r_script") { continuation.resume(with: $0) }
                }
            }
            var response = try await request()
            try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
            if let relocate = response["relocate"] as? [[String: Any]], !relocate.isEmpty {
                let requested = Set(relocate.compactMap { RunRecordR.integer($0["frame"]) })
                guard requested.count > 0, requested.allSatisfy({ supplied.indices.contains($0) }),
                      relocate.allSatisfy({ RunRecordR.integer($0["frame"]) != nil }) else {
                    throw ReportNotebook.Failure(message: "The original data could not be located. Reopen the original workbook and rerun the analysis before exporting.")
                }
                for group in groups {
                    var localRequests: [[String: Any]] = []
                    for item in relocate {
                        guard let global = RunRecordR.integer(item["frame"]), let local = group.global.firstIndex(of: global) else { continue }
                        var translated = item; translated["frame"] = local; localRequests.append(translated)
                    }
                    guard !localRequests.isEmpty else { continue }
                    let frames = try await reader.candidates(for: localRequests, in: group.frames, of: group.record)
                    try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
                    guard frames.count == group.global.count else {
                        throw ReportNotebook.Failure(message: "The original data could not be located. Reopen the original workbook and rerun the analysis before exporting.")
                    }
                    for (local, global) in group.global.enumerated() {
                        var indexed = frames[local]; indexed["index"] = global
                        supplied[global]["frame"] = indexed
                    }
                }
                response = try await request()
                try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
            }
            if let relocate = response["relocate"] as? [[String: Any]], !relocate.isEmpty {
                throw ReportNotebook.Failure(message: "The original data could not be located. Reopen the original workbook and rerun the analysis before exporting.")
            }
            guard let notebook = response["notebook"] as? String, !notebook.isEmpty else {
                throw ReportNotebook.Failure(message: "The analysis host returned no notebook. Try exporting again.")
            }
            await reader.close()
            try notebookUnchanged(doc, revision: revision, title: title, entries: entries)
            return Data(notebook.utf8)
        } catch {
            await reader.close()
            throw error
        }
    }

    /// Bound the whole report before the renderer rasterizes charts or any
    /// workbook is read. Each record's existing limits are still enforced;
    /// combining many individually valid records cannot bypass the total.
    private func notebookInputPreflight(_ entries: [ReportEntry]) throws {
        var cells = 0
        for entry in entries {
            guard let record = entry.record else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any] else {
                throw ReportNotebook.Failure(message: "The record for \(entry.title) is unreadable. Rerun the analysis, then export again.")
            }
            for request in RunRecordR.requests(in: object) {
                guard let frame = request.frame else {
                    let reason = RunRecordR.plain(request.unavailable ?? "the record does not say where its columns are")
                    throw ReportNotebook.Failure(message: "The data for \(entry.title) cannot be exported: \(reason). Reopen the original workbook and rerun the analysis, or export fewer analyses.")
                }
                let first = frame.columns.map(\.firstRow).min() ?? 1
                let last = frame.columns.map(\.rows.upperBound).max() ?? 0
                let asked = Set(frame.columns.map(\.column)).count * max(0, last - first + 1)
                guard asked <= RunRecordR.maxRecordCells - cells else {
                    throw ReportNotebook.Failure(message: "This report requires more than five million worksheet cells for notebook export. Export fewer analyses in one notebook.")
                }
                cells += asked
            }
        }
    }

    /// The renderer runs in an isolated world, as the ordinary report exporter
    /// does. Imported markup cannot replace it. IDs surround the same async
    /// capture that supplies styled text, tables and chart attachments.
    private func notebookSnapshot(_ doc: Document, title: String) async throws -> [String: Any] {
        let script = try String(contentsOf: root.appendingPathComponent("Report/export.js"), encoding: .utf8)
        let options: [String: Any] = ["title": title, "helpRoot": root.appendingPathComponent("Help", isDirectory: true).absoluteString]
        let capture = """
        const notebookIDs = () => {
          const root = document.getElementById('report-results') || document.getElementById('results');
          return root ? [...root.children].filter(e => e.matches('.report-entry[data-result-id]')).map(e => e.getAttribute('data-result-id')) : [];
        };
        const idsBefore = notebookIDs();
        const captured = await StatsDirectReportExport.notebook(options);
        return {...captured, idsBefore, idsAfter: notebookIDs()};
        """
        return try await withCheckedThrowingContinuation { continuation in
            doc.web.callAsyncJavaScript(script + "\n" + capture, arguments: ["options": options], in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value):
                    guard let value = value as? [String: Any] else {
                        continuation.resume(throwing: ReportNotebook.Failure(message: "The report returned no notebook content."))
                        return
                    }
                    continuation.resume(returning: value)
                case .failure(let error):
                    let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    continuation.resume(throwing: ReportNotebook.Failure(message: detail))
                }
            }
        }
    }

    private func notebookUnchanged(_ doc: Document, revision: Int, title: String, entries: [ReportEntry]) throws {
        let current = doc.reportEntries ?? []
        guard documents.contains(where: { $0 === doc }), !doc.web.isLoading,
              doc.reportRevision == revision, doc.title == title, current.count == entries.count,
              zip(current, entries).allSatisfy({ a, b in
                  a.id == b.id && a.title == b.title && a.operation == b.operation && a.record == b.record &&
                  a.body == b.body && a.editedBody == b.editedBody && a.annotation == b.annotation && a.helpPath == b.helpPath
              }) else {
            throw ReportNotebook.Failure(message: "The report changed or was closed while preparing the notebook. Try exporting again.")
        }
    }
}
