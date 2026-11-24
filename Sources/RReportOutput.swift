import Cocoa

enum RReportOutputPart {
    case text(String)
    case svg(Data)
    case png(Data)
}

extension Viewer {
    /// Transfer a snapshot of R output into the report that was current when
    /// Add was pressed. Run the same offline sanitizer and chart ID isolation
    /// as imported reports before installing the result in the report editor.
    func addROutputToReport(_ parts: [RReportOutputPart], from source: Document,
                            to destination: Document?, isCurrent: () -> Bool) async {
        guard isCurrent(), documents.contains(where: { $0 === source }) else { return }
        let title = "R output · " + source.title
        var html = "<h2>" + htmlEscape(title) + "</h2>"
        do {
            for part in parts {
                switch part {
                case .text(let text):
                    html += "<pre style='white-space:pre-wrap'>" + htmlEscape(text) + "</pre>"
                case .svg(let data):
                    html += "<figure>" + (try ReportImageClipboard.svgMarkup(data)) + "</figure>"
                case .png(let data):
                    html += "<figure><img alt='R chart' src='data:image/png;base64,"
                        + data.base64EncodedString() + "'></figure>"
                }
                guard html.utf8.count <= 30_000_000 else {
                    throw LegacyReportError("The R output exceeds the 30 MB report limit. Select less output.")
                }
            }
            let converted = try await ReportImporter.convert(html: html, resources: root)
            guard isCurrent(), documents.contains(where: { $0 === source }) else { return }
            if let destination, !documents.contains(where: { $0 === destination && $0.reportEntries != nil }) {
                throw LegacyReportError("The destination report is closed. Choose a report and try again.")
            }
            guard let body = converted["html"] as? String, !body.isEmpty else {
                throw LegacyReportError("The R output could not be prepared for the report.")
            }
            let entry = ReportEntry(id: UUID().uuidString, title: title, operation: "", body: body, record: nil)
            appendReport(entry, to: destination ?? makeReport())
        } catch {
            guard isCurrent(), documents.contains(where: { $0 === source }) else { return }
            status.stringValue = error.localizedDescription
        }
    }
}
