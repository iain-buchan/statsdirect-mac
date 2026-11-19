import Cocoa
import WebKit

extension Viewer {
    func openWorksheetSelectionInR(_ doc: Document) {
        guard doc.kind == "grid", !doc.web.isLoading else { return }
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.worksheetRSelection()", arguments: [:], in: nil, in: .page) { [weak self, weak doc] result in
            guard let self, let doc, self.active === doc, self.documents.contains(where: { $0 === doc }) else { return }
            do {
                let value = try result.get()
                guard let data = value as? [String: Any] else {
                    throw ConversationRScript.Failure(message: "The worksheet selection could not be read.")
                }
                let script = try WorksheetRScript.build(data)
                let title = data["sheet"] as? String ?? doc.title
                self.makeRScript(script: script, title: title)
                self.status.stringValue = "Worksheet selection opened in R Script. Choose Run to create data in R."
            } catch {
                let message = self.javaScriptMessage(error)
                self.gridStatus(doc, message)
                self.status.stringValue = message
            }
        }
    }
}
