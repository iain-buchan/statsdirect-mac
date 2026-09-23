import Cocoa
import WebKit

extension Viewer {
    func reportRAction(_ plan: RScriptPlan?) -> String {
        guard let plan else { return "<p class='note'>R script generation is unavailable for this report.</p>" }
        let label = plan.hasRecipe ? "Continue in R" : "Open data and settings in R"
        return """
        <div class="report-actions"><button type="button" onclick="window.webkit.messageHandlers.statsDirectReport.postMessage({action:'continueInR'})">\(label)</button>
        <span>Opens and runs an editable script in a new R tab.</span>
        <details><summary>R script coverage</summary><p>\(htmlEscape(plan.detail))</p></details></div>
        """
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
