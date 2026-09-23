import Cocoa
import WebKit

extension Viewer {
    func populateOperationMenu(_ menu: NSMenu) {
        do {
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("analysis-menu.json"))) as! [String: Any]
            analysisCatalog = catalog["operations"] as? [String: [String: Any]] ?? [:]
            func append(_ nodes: [[String: Any]], to parent: NSMenu) {
                for node in nodes {
                    if node["separator"] as? Bool == true { parent.addItem(.separator()); continue }
                    let title = node["label"] as? String ?? "Analysis"
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    if let children = node["children"] as? [[String: Any]] {
                        let child = NSMenu(title: title); item.submenu = child; append(children, to: child)
                    } else if let operation = node["operation"] as? String {
                        item.toolTip = analysisCatalog[operation]?["unavailable"] as? String
                        item.target = self; item.action = #selector(openAnalysisOperation(_:)); item.representedObject = operation
                        if operation == "TPaired" { item.keyEquivalent = "t" }
                        if operation == "ExactChiRbyCScreen" { item.keyEquivalent = "4" }
                    }
                    parent.addItem(item)
                }
            }
            let tree = (catalog["menus"] as? [[String: Any]])?.first { $0["label"] as? String == menu.title }
            append(tree?["children"] as? [[String: Any]] ?? [], to: menu)
        } catch { showError("The \(menu.title) menu could not be loaded: " + error.localizedDescription) }
    }
    @objc func openAnalysisOperation(_ sender: NSMenuItem) {
        guard let operation = sender.representedObject as? String, let definition = analysisCatalog[operation] else { return }
        if operation == "ExactChiRbyCScreen" { showChiSquare(); return }
        let title = nextAnalysisTitle(definition["title"] as? String ?? sender.title)
        let doc = newDocument(kind: "operation", title: title, url: root.appendingPathComponent("Grid/operation.html"))
        doc.operationName = operation
    }
    func handleOperation(_ message: WKScriptMessage) {
        guard message.name == "statsDirectOperation", message.frameInfo.isMainFrame,
              let web = message.webView, let doc = document(for: web), doc.kind == "operation",
              web.url?.standardizedFileURL == root.appendingPathComponent("Grid/operation.html").standardizedFileURL,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            var config = doc.operationName.flatMap { analysisCatalog[$0] } ?? [:]; config["title"] = doc.title
            doc.operationReady = true
            operationScript(doc, "configure", config)
            refreshOperationSource(doc) { self.startOperation(doc) }
        case "refresh": refreshOperationSource(doc)
        case "help":
            if let operation = doc.operationName, let path = analysisCatalog[operation]?["help"] as? String {
                openHelp(root.appendingPathComponent(path), title: doc.title)
            } else { helpLibrary() }
        case "paste":
            if let text = NSPasteboard.general.string(forType: .string) { web.evaluateJavaScript("window.statsDirectOperation?.pasteText?.(\(jsString(text)))") }
        case "start":
            startOperation(doc)
        case "answer":
            guard let id = doc.analysisJobID, let token = body["token"], let value = body["value"] else { return }
            operationRequest(["action": "answer", "id": id, "token": token, "value": value], doc: doc, id: id)
        case "cancel":
            guard let id = doc.analysisJobID else { return }
            doc.analysisCancelled = true
            operationRequest(["action": "cancel", "id": id], doc: doc, id: id)
        default: break
        }
    }
    func startOperation(_ doc: Document) {
        guard let operation = doc.operationName, analysisCatalog[operation]?["unavailable"] == nil else { return }
        guard doc.analysisJobID == nil else { return }
        let id = UUID().uuidString; doc.analysisJobID = id; doc.analysisCancelled = false; doc.operationStarting = true
        operationScript(doc, "update", ["state": "running", "progress": "Opening input form…"])
        operationRequest(["action": "start", "id": id, "operation": operation], doc: doc, id: id)
    }
    func operationScript(_ doc: Document, _ method: String, _ object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else { return }
        doc.web.evaluateJavaScript("window.statsDirectOperation?.\(method)(\(String(decoding: data, as: UTF8.self)))")
    }
    func operationError(_ doc: Document, _ text: String) { operationScript(doc, "error", text) }
    func refreshOperationSource(_ doc: Document, completion: (() -> Void)? = nil) {
        guard let source = documents.first(where: { $0.id == analysisSourceID }), source.kind == "grid" else { operationScript(doc, "setSource", NSNull()); completion?(); return }
        let script = "window.statsDirectGrid?.analysisSource()"
        source.web.evaluateJavaScript(script) { snapshot, error in
            guard self.documents.contains(where: { $0 === doc }) else { return }
            if let snapshot, error == nil { self.operationScript(doc, "setSource", snapshot) }
            else { self.operationError(doc, "The worksheet is still loading. Use Refresh worksheet when it is ready.") }
            completion?()
        }
    }
    func operationRequest(_ request: [String: Any], doc: Document, id: String) {
        // Ignore old polls after answering or cancelling a prompt.
        doc.operationRevision += 1; let revision = doc.operationRevision
        analysisRequest(request, entry: "statsdirect_operation") { result in
            guard doc.analysisJobID == id, doc.operationRevision == revision else { return }
            let starting = request["action"] as? String == "start"
            if starting { doc.operationStarting = false }
            switch result {
            case .failure(let error):
                self.operationError(doc, error.localizedDescription)
                if starting { doc.analysisJobID = nil; if doc.operationClosing { self.remove(doc) } }
            case .success(let output):
                if starting && doc.operationClosing { self.operationRequest(["action": "cancel", "id": id], doc: doc, id: id); return }
                self.operationScript(doc, "update", output)
                switch output["state"] as? String {
                case "complete", "cancelled", "failed":
                    doc.analysisJobID = nil
                    self.analysisRequest(["action": "release", "id": id], entry: "statsdirect_operation") { _ in }
                    if doc.operationClosing { self.remove(doc); return }
                    if output["state"] as? String == "complete", !doc.analysisCancelled { self.showOperationReport(doc, output) }
                    else { self.status.stringValue = doc.title + (doc.analysisCancelled ? " cancelled" : " did not complete") }
                case "input": self.status.stringValue = doc.title + " · Waiting for input"
                default:
                    self.status.stringValue = output["progress"] as? String ?? "Running analysis…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        guard doc.analysisJobID == id, doc.operationRevision == revision else { return }
                        self.operationRequest(["action": "poll", "id": id], doc: doc, id: id)
                    }
                }
            }
        }
    }
    func showOperationReport(_ doc: Document, _ output: [String: Any]) {
        reportNumber += 1
        let frames = output["frames"] as? [[String: Any]] ?? []
        for (index, frame) in frames.enumerated() {
            let dataDoc = newDocument(kind: "grid", title: "\(doc.title) · Data \(index + 1)", url: root.appendingPathComponent("Grid/index.html"))
            dataDoc.pendingWorkbook = ["name": dataDoc.title, "sheets": [frame], "formulaCount": 0]
            dataDoc.workbookName = "\(doc.title).xlsx"; dataDoc.gridDirty = true
        }
        let html = output["html"] as? String ?? ""
        let methodPath = doc.operationName.flatMap { analysisCatalog[$0]?["help"] as? String }
        let help = methodPath.map { "<p><a href='\(htmlEscape($0))'>Method and worked example →</a></p>" } ?? ""
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let inputData = (try? JSONSerialization.data(withJSONObject: output["history"] ?? [], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let body = """
        <div class="eyebrow">Analysis / StatsDirect</div><h1>\(htmlEscape(doc.title))</h1><p class="muted">Report \(reportNumber) · \(stamp)</p>
        <section class="engine-report">\(html.isEmpty ? "<p>Completed successfully.\(frames.isEmpty ? "" : " \(frames.count) data table(s) opened in separate documents.")</p>" : html)</section>\(help)
        <details><summary>Inputs used for this report</summary><pre>\(htmlEscape(String(decoding: inputData, as: UTF8.self)))</pre></details>
        <p class="muted">Calculated by the StatsDirect 5.0.5 engine · \(htmlEscape(doc.operationName ?? ""))</p>
        """
        newDocument(kind: "report", title: "Report \(reportNumber) · \(doc.title)", html: page(doc.title, body))
        status.stringValue = doc.title + " completed · Report \(reportNumber)"
    }
}
