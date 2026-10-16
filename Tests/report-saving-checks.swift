import Cocoa
import PDFKit

extension ReportExportTests {
    @MainActor static func reportSaving(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let report = v.makeReport()
        report.reportEntries = [ReportEntry(id: "saving", title: "Saving checks", operation: "", body: "<p>Editable original</p>", record: nil)]
        report.reportRevision = 1
        v.renderReport(report); try await settled(report)
        let remembered = UserDefaults.standard.object(forKey: "reportSaveFormat")
        defer { UserDefaults.standard.set(remembered, forKey: "reportSaveFormat") }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<600 { if condition() { return }; try await Task.sleep(nanoseconds: 25_000_000) }
            precondition(false, "Report save did not finish")
        }
        func write(_ format: ReportFormat, _ name: String) async throws -> URL {
            let url = output.appendingPathComponent(name + "." + format.rawValue)
            var finished = false
            v.writeReport(report, to: url, format: format) { finished = true }
            try await wait { finished && !report.fileBusy }
            precondition(FileManager.default.fileExists(atPath: url.path), "Save must create its file")
            return url
        }
        func picker(_ explicit: ReportFormat?, expected: ReportFormat) async throws {
            v.saveReportAs(report, format: explicit)
            try await wait { v.window.attachedSheet is NSSavePanel }
            let panel = v.window.attachedSheet as! NSSavePanel
            let popup = (panel.accessoryView as? NSStackView)?.views.compactMap { $0 as? NSPopUpButton }.first
            precondition(popup?.titleOfSelectedItem == expected.label && panel.nameFieldStringValue.hasSuffix("." + expected.rawValue), "Save As must offer \(expected.label)")
            panel.cancel(nil)
            try await wait { v.window.attachedSheet == nil }
        }
        for old in ["pdf", "docx"] {
            UserDefaults.standard.set(old, forKey: "reportSaveFormat")
            try await picker(nil, expected: .html)
        }
        try await picker(.pdf, expected: .pdf)
        try await picker(.docx, expected: .docx)
        precondition(report.reportDirty && report.reportFileURL == nil, "Cancelling Save As must preserve the new unsaved report")
        for format in [ReportFormat.pdf, .docx] {
            _ = try await write(format, "new-report-copy")
            precondition(report.reportDirty && report.reportSavedRevision == 0 && report.reportFileURL == nil, "Exporting a new report must not mark its editable contents saved")
        }
        let html = try await write(.html, "editable-report")
        let original = try Data(contentsOf: html)
        precondition(!report.reportDirty && report.reportFileURL == html, "HTML Save establishes the report file and saved revision")
        v.updateReportText(report, id: "saving", html: "<p>New editable finding</p>", refresh: true)
        try await settled(report)
        for format in [ReportFormat.pdf, .docx] {
            let copy = try await write(format, "edited-report-copy")
            precondition(report.reportDirty && report.reportFileURL == html && report.reportSavedRevision == 1, "Export must preserve pending edits and the HTML destination")
            precondition(try Data(contentsOf: html) == original, "Export must not overwrite the HTML file")
            if format == .pdf { precondition(PDFDocument(url: copy)?.string?.contains("New editable finding") == true, "PDF copy includes current edits") }
            v.closeDocument(report)
            try await wait { v.window.attachedSheet != nil }
            precondition(v.documents.contains { $0 === report }, "Closing an exported report must still ask about unsaved HTML edits")
            v.window.endSheet(v.window.attachedSheet!, returnCode: .alertThirdButtonReturn)
            try await wait { v.window.attachedSheet == nil }
        }
        var saved = false
        v.saveReport(report) { saved = true }
        try await wait { saved && !report.fileBusy }
        precondition(!report.reportDirty && report.reportFileURL == html && v.window.attachedSheet == nil, "Save writes to the existing HTML destination without another panel")
        precondition(try String(contentsOf: html, encoding: .utf8).contains("New editable finding"), "HTML Save retains the edits")
        let savedRevision = report.reportSavedRevision
        _ = try await write(.docx, "clean-report-copy")
        precondition(!report.reportDirty && report.reportSavedRevision == savedRevision, "Export does not make a clean report dirty")
        for format in ReportFormat.allCases {
            let before = report.reportSavedRevision
            var finished = false
            v.writeReport(report, to: output.appendingPathComponent("during-save." + format.rawValue), format: format) { finished = true }
            v.updateReportText(report, id: "saving", html: "<p>Edit made during \(format.rawValue) export</p>", refresh: true)
            try await wait { finished && !report.fileBusy }
            precondition(report.reportDirty, "Edits made during \(format.rawValue) export must remain unsaved")
            if format != .html { precondition(report.reportSavedRevision == before, "An export copy cannot advance the saved HTML revision") }
        }
        print("PASS: native Save As defaults, explicit exports, cancellation, new/existing HTML dirty state, close prompts and direct Save"); fflush(stdout)
    }
}
