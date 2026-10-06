import Cocoa
import WebKit

struct ReportEntry {
    let id: String
    let title: String
    let operation: String
    let body: String
    let rPlan: RScriptPlan?
    var annotation = ""
    var hiddenCharts: Set<Int> = []
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
        doc.rScriptPlan = entries.last?.rPlan
        doc.operationName = entries.last?.operation
        let body = entries.isEmpty
            ? "<h1>\(htmlEscape(doc.title))</h1><p class='muted'>New analysis results will be collected here. Use Add to report to keep results from instant-answer forms.</p>"
            : entries.map { reportEntryHTML($0) }.joined()
        doc.hasSVG = body.contains("<svg")
        doc.web.loadHTMLString(page(doc.title, "<div class='report-controls'><button onclick=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'undoReport'})\" \(doc.reportUndo.isEmpty ? "disabled" : "")>Undo report removal</button></div>" + body), baseURL: root)
    }

    func reportEntryHTML(_ entry: ReportEntry) -> String {
        var body=entry.body
        if let pattern=try? NSRegularExpression(pattern:"(?is)<svg\\b[^>]*>.*?</svg>") {
            let matches=pattern.matches(in:body,range:NSRange(body.startIndex...,in:body))
            for (index,match) in matches.enumerated().reversed() {
                guard let range=Range(match.range,in:body) else { continue }
                let replacement=entry.hiddenCharts.contains(index) ? "" : "<div class='report-chart'><div class='report-controls'><button onclick=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'hideChart',resultID:'\(entry.id)',index:\(index)})\">Remove plot</button></div>" + String(body[range]) + "</div>"
                body.replaceSubrange(range,with:replacement)
            }
        }
        return "<article class='report-entry' id='result-\(entry.id)'>" + body + "<div class='report-controls'><label>Report notes</label><button onclick=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'removeResult',resultID:'\(entry.id)'})\">Remove result</button></div><div class='report-annotation' contenteditable='plaintext-only' role='textbox' aria-label=\"Notes for \(htmlEscape(entry.title))\" data-placeholder='Add your interpretation or notes…' oninput=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'annotate',resultID:'\(entry.id)',text:this.innerText})\">\(htmlEscape(entry.annotation))</div></article>"
    }
    func editReport(_ doc: Document, _ body: [String:Any]) {
        guard let action=body["action"] as? String else { return }
        if action == "undoReport" {
            if let previous=doc.reportUndo.popLast() { doc.reportEntries=previous;renderReport(doc) };return
        }
        guard let id=body["resultID"] as? String,let index=doc.reportEntries?.firstIndex(where:{$0.id==id}) else { return }
        if action == "annotate" {
            if let text=body["text"] as? String,text.utf8.count<=100_000 {
                doc.reportEntries?[index].annotation=text
                for undo in doc.reportUndo.indices {
                    if let item=doc.reportUndo[undo].firstIndex(where:{$0.id==id}) { doc.reportUndo[undo][item].annotation=text }
                }
            };return
        }
        guard action == "removeResult" || action == "hideChart" else { return }
        if action == "hideChart" { guard let chart=body["index"] as? Int,chart>=0,chart<1000 else {return} }
        doc.reportUndo.append(doc.reportEntries!);if doc.reportUndo.count>20 {doc.reportUndo.removeFirst()}
        if action == "removeResult" {doc.reportEntries?.remove(at:index)}
        else {doc.reportEntries?[index].hiddenCharts.insert(body["index"] as! Int)}
        renderReport(doc)
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
        // Restoring a removal must retain analyses added since that removal.
        for undo in report.reportUndo.indices { report.reportUndo[undo].append(entry) }
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
