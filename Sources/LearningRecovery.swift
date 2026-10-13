import Cocoa
import WebKit

extension Viewer {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let doc = document(for:webView), doc.kind == "learn" else { return }
        doc.learningRendererReady = false; doc.learningNeedsRecovery = true
        // The host retains portfolio state and the latest reply event. A reply can
        // continue while this page is unavailable; no replacement request is sent.
        webView.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectLearn")
        let label = NSTextField(wrappingLabelWithString:"The Learning window stopped. Reopen it to continue with your saved conversation.")
        let reopen = NSButton(title:"Reopen Learning",target:self,action:#selector(openLearning))
        let panel = NSStackView(views:[label,reopen]); panel.orientation = .vertical; panel.spacing = 12
        doc.item.view = panel
        status.stringValue = "Learning stopped. Choose Reopen Learning to continue."
    }

    func recoverLearningRenderer(_ doc: Document) {
        guard doc.kind == "learn", doc.learningNeedsRecovery, documents.contains(where:{$0 === doc}) else { return }
        let previous = doc.web
        previous.stopLoading(); previous.navigationDelegate = nil; previous.uiDelegate = nil
        previous.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectLearn")
        (previous as? ReportWebView)?.document = nil
        let web = Document.makeWebView()
        web.document = doc; doc.web = web; doc.item.view = web
        web.navigationDelegate = self; web.uiDelegate = self
        web.configuration.userContentController.add(self,name:"statsDirectLearn")
        doc.learningRendererReady = false; doc.learningNeedsRecovery = false
        let url = root.appendingPathComponent("Learn/index.html")
        doc.initialURL = url
        web.loadFileURL(url,allowingReadAccessTo:doc.access)
    }

    // Also retain received text if the learner closes the failed tab instead of
    // using its Reopen button. It is explicitly marked incomplete when appropriate.
    func retainLearningReplyOnClose(_ doc: Document) {
        guard var state = doc.learningState, let event = doc.learningReplyEvent,
              let value = event["value"] as? [String:Any], let id = value["id"] as? String else { return }
        let complete = event["action"] as? String == "reply"
        let text = complete ? value["text"] as? String ?? "" : event["partial"] as? String ?? ""
        guard !text.isEmpty else { return }
        var rows = state["conversation"] as? [[String:Any]] ?? []
        guard !rows.contains(where:{$0["id"] as? String == id}) else { return }
        var entry: [String:Any] = ["id":id,"at":ISO8601DateFormatter().string(from:Date()),"role":"assistant",
            "text":text + (complete ? "" : "\n\n[Reply stopped before completion.]"),"source":"StatsDirect AI tutor","lessonId":state["lesson"] as? String ?? ""]
        for key in ["model","responseID","promptVersion","courseSources","workspaceSources","diagnostics"] { if let item = value[key] { entry[key] = item } }
        rows.append(entry); state["conversation"] = rows
        do { try persistLearningState(doc,state) }
        catch { status.stringValue = "The received reply is kept in memory but could not be saved." }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}
