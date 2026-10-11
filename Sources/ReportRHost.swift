import Cocoa
import WebKit

extension Viewer {
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
        guard let entry = doc.reportEntries?.first(where: { $0.id == resultID }) else { return }
        if action == "continueInR", let plan = entry.rPlan { openReportInR(plan, title: entry.title, operation: entry.operation) }
        if action == "methodHelp", let path = entry.helpPath ?? (analysisCatalog[entry.operation]?["help"] as? String) { openHelp(root.appendingPathComponent(path), title: entry.title) }
    }
    func continueResultInR(_ doc: Document, id: String) {
        performReportAction(doc, action: "continueInR", resultID: id)
    }
    func openReportInR(_ plan: RScriptPlan, title: String, operation: String? = nil) {
        let doc = makeRScript(script: plan.script, title: title, saved: true)
        doc.operationName = operation
        doc.rPane?.runScript()
        status.stringValue = "R script from " + title
    }
}
