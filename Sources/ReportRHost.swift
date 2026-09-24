import Cocoa
import WebKit

extension Viewer {
    func reportLinks(_ plan: RScriptPlan?, helpPath: String?, helpLabel: String = "Method and worked example →") -> String {
        var links = [String]()
        if let helpPath { links.append("<a href=\"\(htmlEscape(helpPath))\">\(htmlEscape(helpLabel))</a>") }
        if let plan {
            let label = plan.hasRecipe ? "Continue in R" : "Open data and settings in R"
            links.append("<a class='report-r-link' href='#' title=\"Opens and runs an editable R script. \(htmlEscape(plan.detail))\" onclick=\"window.webkit.messageHandlers.statsDirectReport.postMessage({action:'continueInR'});return false\">\(label)</a>")
        }
        return "<p class='report-links'>" + links.joined(separator: "<span aria-hidden='true'> · </span>") + "</p>"
    }
    func handleReport(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let web = message.webView, let doc = document(for: web),
              doc.kind == "report", doc.initialURL == nil,
              web.url?.standardizedFileURL.path == root.standardizedFileURL.path,
              let body = message.body as? [String: Any], body["action"] as? String == "continueInR" else { return }
        continueReportInR(doc)
    }
    @objc func continueActiveReportInR() { if let doc = active { continueReportInR(doc) } }
    func continueReportInR(_ report: Document) {
        guard let plan = report.rScriptPlan else { return }
        rNumber += 1
        let doc = newDocument(kind: "r", title: "R · \(report.title) · \(rNumber)")
        let pane = RPane(script: plan.script)
        doc.rPane = pane; doc.item.view = pane.view
        pane.runScript()
        status.stringValue = "R session from " + report.title
    }
}
