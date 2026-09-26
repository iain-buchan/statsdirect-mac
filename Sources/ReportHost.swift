import Cocoa
import WebKit

struct ReportEntry {
    let id: String
    let title: String
    let operation: String
    let body: String
    let rPlan: RScriptPlan?
}

extension Viewer {
    @objc func newReport() { _ = makeReport() }

    func makeReport() -> Document {
        reportNumber += 1
        let doc = newDocument(kind: "report", title: "Report \(reportNumber)")
        doc.reportEntries = []
        activeReportID = doc.id
        renderReport(doc)
        return doc
    }

    func renderReport(_ doc: Document) {
        guard let entries = doc.reportEntries else { return }
        let body = entries.isEmpty
            ? "<h1>\(htmlEscape(doc.title))</h1><p class='muted'>New analysis results will be collected here. Use Add to report to keep results from instant-answer forms.</p>"
            : entries.map { "<article class='report-entry' id='result-\($0.id)'>\($0.body)</article>" }.joined()
        doc.hasSVG = body.contains("<svg")
        doc.web.loadHTMLString(page(doc.title, body), baseURL: root)
    }

    @discardableResult
    func appendReport(_ entry: ReportEntry) -> Document {
        // A repeated Add action must never duplicate an unchanged result.
        if let existing = documents.first(where: { $0.reportEntries?.contains(where: { $0.id == entry.id }) == true }) {
            tabs.selectTabViewItem(existing.item); return existing
        }
        let report = documents.first(where: { $0.id == activeReportID && $0.reportEntries != nil })
            ?? documents.last(where: { $0.reportEntries != nil }) ?? makeReport()
        report.reportEntries?.append(entry)
        report.rScriptPlan = entry.rPlan; report.operationName = entry.operation
        report.scrollToResultID = entry.id
        renderReport(report)
        tabs.selectTabViewItem(report.item)
        activeReportID = report.id
        status.stringValue = "\(entry.title) added to \(report.title)"
        return report
    }

    func previewResult(_ entry: ReportEntry, in doc: Document) {
        doc.pendingResult = entry
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        let preview = page(entry.title, "<style>.report-links{display:none}body{padding:12px 18px}</style>" + entry.body)
        doc.web.evaluateJavaScript("window.\(bridge)?.showResult({id:\(jsString(entry.id)),page:\(jsString(preview))})")
        status.stringValue = "\(entry.title) complete · Add to report to keep these results"
    }

    func keepResult(_ doc: Document, id: String?) {
        guard let entry = doc.pendingResult, entry.id == id else { return }
        let report = appendReport(entry)
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        doc.web.evaluateJavaScript("window.\(bridge)?.resultKept(\(jsString(report.title)))")
    }
}
