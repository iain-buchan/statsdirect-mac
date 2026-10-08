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
        doc.operationSourceID = analysisSourceID
    }
    func handleOperation(_ message: WKScriptMessage) {
        guard message.name == "statsDirectOperation", message.frameInfo.isMainFrame,
              let web = message.webView, let doc = document(for: web), doc.kind == "operation",
              web.url?.standardizedFileURL == root.appendingPathComponent("Grid/operation.html").standardizedFileURL,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            var config = doc.operationName.flatMap { analysisCatalog[$0] } ?? [:]; config["title"] = doc.title
            config["derivedOutput"] = supportsDerivedWorksheet(doc.operationName ?? "")
            doc.operationReady = true
            operationScript(doc, "configure", config)
            refreshOperationSource(doc) { self.startOperation(doc) }
        case "outputMode": doc.includeSourceColumns = body["includeSource"] as? Bool ?? true
        case "refresh": refreshOperationSource(doc)
        case "columns": fetchOperationColumns(doc, body)
        case "keepResult": keepResult(doc, id: body["id"] as? String)
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
            if let input=value as? [String:Any], input["columns"] != nil { doc.operationInputRange=input["range"] as? [String:Any] }
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
        doc.operationInputRange = nil
        let id = UUID().uuidString; doc.analysisJobID = id; doc.analysisCancelled = false; doc.operationStarting = true
        operationScript(doc, "update", ["state": "running", "progress": "Opening input form…"])
        var request: [String: Any] = ["action": "start", "id": id, "operation": operation]
        if let defaults = UserDefaults.standard.dictionary(forKey: "analysisDefaults") { request["preferences"] = defaults }
        operationRequest(request, doc: doc, id: id)
    }
    func operationScript(_ doc: Document, _ method: String, _ object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else { return }
        let bridge = doc.kind == "analysis" ? "statsDirectChiSquare" : "statsDirectOperation"
        doc.web.evaluateJavaScript("window.\(bridge)?.\(method)(\(String(decoding: data, as: UTF8.self)))")
    }
    func operationError(_ doc: Document, _ text: String) { operationScript(doc, "error", text) }
    func refreshOperationSource(_ doc: Document, completion: (() -> Void)? = nil) {
        if let source = doc.initialOperationSource {
            doc.initialOperationSource = nil; doc.operationSourceSnapshot=source; operationScript(doc, "setSource", source); completion?(); return
        }
        guard let source = documents.first(where: { $0.id == (doc.operationSourceID ?? analysisSourceID) }), source.kind == "grid" else { operationScript(doc, "setSource", NSNull()); completion?(); return }
        let script = "window.statsDirectGrid?.analysisSource()"
        source.web.evaluateJavaScript(script) { snapshot, error in
            guard self.documents.contains(where: { $0 === doc }) else { return }
            if let snapshot=snapshot as? [String:Any], error == nil { doc.operationSourceSnapshot=snapshot; self.operationScript(doc, "setSource", snapshot) }
            else { self.operationError(doc, "The worksheet is still loading. Use Refresh worksheet when it is ready.") }
            completion?()
        }
    }
    // A form reads the worksheet columns it needs when a step is submitted (Grid/analysis-source.mjs).
    func fetchOperationColumns(_ doc: Document, _ body: [String: Any]) {
        guard let token = body["token"] else { return }
        guard let source = documents.first(where: { $0.id == (doc.operationSourceID ?? analysisSourceID) }), source.kind == "grid" else {
            operationScript(doc, "columnData", ["token": token, "error": "The worksheet is no longer open. Use Refresh worksheet to choose another."]); return
        }
        var request = body; request["action"] = nil; request["token"] = nil
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return }
        source.web.evaluateJavaScript("window.statsDirectGrid.columnValues(\(String(decoding: data, as: UTF8.self)))") { value, error in
            guard self.documents.contains(where: { $0 === doc }) else { return }
            if let error { self.operationScript(doc, "columnData", ["token": token, "error": self.javaScriptMessage(error)]) }
            else if var result = value as? [String: Any] { result["token"] = token; self.operationScript(doc, "columnData", result) }
            else { self.operationScript(doc, "columnData", ["token": token, "error": "The worksheet is still loading. Use Refresh worksheet when it is ready."]) }
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
                    if output["state"] as? String == "complete", !doc.analysisCancelled {
                        if ["AnalysisOptions","MetaCalculationOptions","MetaPlotOptions"].contains(doc.operationName ?? ""), let defaults = output["analysisOptions"] as? [String: Any] {
                            UserDefaults.standard.set(defaults, forKey: "analysisDefaults")
                            self.status.stringValue = "Analysis defaults saved · Applied to new analyses"
                        } else { self.showOperationReport(doc, output) }
                    }
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
        let resultID = UUID().uuidString
        let frames = output["frames"] as? [[String: Any]] ?? []
        for (index, frame) in frames.enumerated() {
            let title = "\(doc.title) · Data \(index + 1)"
            let plan = doc.includeSourceColumns && supportsDerivedWorksheet(doc.operationName ?? "") ? derivedWorksheet(source:doc.operationSourceSnapshot,range:doc.operationInputRange,frame:frame) : nil
            func open(_ sheet: [String: Any], snapshotID: String?) {
                let dataDoc = self.newDocument(kind: "grid", title: title, url: self.root.appendingPathComponent("Grid/index.html"))
                var sheet = sheet
                if let snapshotID { sheet["snapshot"] = SnapshotStore.shared.url(for: snapshotID); dataDoc.snapshotIDs.append(snapshotID) }
                dataDoc.pendingWorkbook = ["name": title, "sheets": [sheet], "formulaCount": 0]
                dataDoc.workbookName = "\(doc.title).xlsx"; dataDoc.gridDirty = true
            }
            // The source worksheet's columns are copied beside the result through a typed snapshot.
            if let plan, let columns = plan.sourceColumns, let source = documents.first(where: { $0.id == (doc.operationSourceID ?? analysisSourceID) }), source.kind == "grid" {
                source.web.callAsyncJavaScript("return window.statsDirectGrid.snapshotColumns(request)", arguments: ["request": columns], in: nil, in: .page) { result in
                    if case .success(let value) = result, let info = value as? [String: Any], let id = info["id"] as? String { open(plan.sheet, snapshotID: id) }
                    else { open(frame, snapshotID: nil) }
                }
            } else { open(plan?.sheet ?? frame, snapshotID: nil) }
        }
        let html = output["html"] as? String ?? ""
        let methodPath = doc.operationName.flatMap { analysisCatalog[$0]?["help"] as? String }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let inputData = (try? JSONSerialization.data(withJSONObject: output["history"] ?? [], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let rPlan = try? RScriptGenerator.generate(operation: doc.operationName ?? "", title: doc.title, output: output, resources: root)
        let body = """
        <div class="eyebrow">Analysis / StatsDirect</div><h1>\(htmlEscape(doc.title))</h1><p class="muted">\(stamp)</p>
        <section class="engine-report">\(html.isEmpty ? "<p>Completed successfully.\(frames.isEmpty ? "" : " \(frames.count) data table(s) opened in separate documents.")</p>" : html)</section>
        \(reportLinks(rPlan, helpPath: methodPath, resultID: resultID))
        <details><summary>Inputs used for this report</summary><pre>\(htmlEscape(String(decoding: inputData, as: UTF8.self)))</pre></details>
        <p class="muted">Calculated by the StatsDirect \(htmlEscape(engineVersion)) engine · \(htmlEscape(doc.operationName ?? ""))</p>
        """
        let entry = ReportEntry(id: resultID, title: doc.title, operation: doc.operationName ?? "", body: body, rPlan: rPlan)
        if doc.operationName.flatMap({ analysisCatalog[$0]?["instant"] as? Bool }) == true {
            previewResult(entry, in: doc)
        } else { appendReport(entry) }
    }
}
