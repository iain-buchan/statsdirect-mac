import Cocoa
import WebKit

/// One question's access is limited to documents that were already open when Send was pressed.
@MainActor final class LearningWorkspace {
    unowned let viewer: Viewer
    weak var learner: Document?
    let requestID: String
    let allowed: Set<String>
    let sourceID: String?
    var datasets: [String:(document:String, version:Int, value:[String:Any])] = [:]
    var results: [String:[String:Any]] = [:]
    var sources: [String] = []
    var calculationBusy = false
    init(_ viewer: Viewer, _ learner: Document, _ requestID: String) {
        self.viewer = viewer; self.learner = learner; self.requestID = requestID
        allowed = learner.learningSourceID == "__none__" ? [] : Set(viewer.documents.filter{$0.kind != "learn"}.map(\.id))
        sourceID = learner.learningSourceID.isEmpty ? viewer.learningLastDocumentID : learner.learningSourceID
    }
    func check() throws {
        try Task.checkCancellation()
        guard let learner, viewer.documents.contains(where:{$0 === learner}), learner.learningRequestID == requestID else { throw CancellationError() }
    }
    func document(_ id: String) throws -> Document {
        try check()
        guard allowed.contains(id), let doc = viewer.documents.first(where:{$0.id == id}) else { throw ChatGPTTutor.Failure(message:"That document is no longer available to this question. Use the current workspace list.") }
        return doc
    }
    func remember(_ text: String) { if !sources.contains(text) { sources.append(text) } }
    func overview() async throws -> [String:Any] {
        try check()
        var rows: [[String:Any]] = []
        for doc in viewer.documents where allowed.contains(doc.id) {
            var row: [String:Any] = ["documentId":doc.id,"title":doc.title,"kind":doc.kind,"focused":doc.id == sourceID]
            if let operation = doc.operationName { row["operation"] = operation }
            if doc.kind == "grid" {
                do { row["worksheet"] = try await viewer.learningJavaScript(doc,"window.statsDirectGrid.tutorInfo()") }
                catch { row["status"] = "Worksheet is loading" }
            }
            rows.append(row)
        }
        try check()
        return ["documents":rows,"focusedDocumentId":sourceID ?? "","sharing":allowed.isEmpty ? "Lessons only: no application documents are available." : "Open StatsDirect documents only. Read values using their IDs. Bundled lesson data are separate from open worksheets."]
    }
    func call(_ name: String, _ arguments: [String:Any]) async throws -> [String:Any] {
        try check()
        guard let spec = TutorTools.definitions.first(where:{$0["name"] as? String == name}),
              let schema = spec["inputSchema"] as? [String:Any], let properties = schema["properties"] as? [String:Any],
              Set(arguments.keys).isSubset(of:Set(properties.keys)),
              (schema["required"] as? [String] ?? []).allSatisfy({arguments[$0] != nil}) else { throw ChatGPTTutor.Failure(message:"Invalid StatsDirect tool arguments.") }
        if let learner { viewer.learningScript(learner,"toolActivity",["id":requestID,"text":name == "statsdirect_run_analysis" ? "Calculating with the StatsDirect engine…" : "Reading StatsDirect context…"]) }
        switch name {
        case "statsdirect_workspace": return try await overview()
        case "statsdirect_read_data":
            let doc = try document(arguments["documentId"] as? String ?? "")
            guard doc.kind == "grid" else { throw ChatGPTTutor.Failure(message:"Choose a worksheet document.") }
            let version = doc.gridVersion
            var options = arguments; options.removeValue(forKey:"documentId")
            let json = String(decoding:try JSONSerialization.data(withJSONObject:options),as:UTF8.self)
            var data = try await viewer.learningJavaScript(doc,"window.statsDirectGrid.tutorData(\(json))")
            try check()
            guard doc.gridVersion == version else { throw ChatGPTTutor.Failure(message:"The worksheet changed while reading it. Read the range again.") }
            let id = UUID().uuidString
            data["datasetId"] = id; data["documentId"] = doc.id
            datasets[id] = (doc.id,version,data)
            let source = "\(data["workbook"] ?? doc.title) · \(data["sheet"] ?? "") · \(data["range"] ?? "") · \(data["rowCount"] ?? 0) rows"
            remember(source)
            if let learner { viewer.learningScript(learner,"toolActivity",["id":requestID,"text":"Using: " + source]) }
            return data
        case "statsdirect_read_document":
            let doc = try document(arguments["documentId"] as? String ?? "")
            guard ["report","help","operation","analysis","r"].contains(doc.kind) else { throw ChatGPTTutor.Failure(message:"Use read_data for worksheet values.") }
            remember(doc.title)
            if let pane = doc.rPane {
                return ["title":doc.title,"kind":"r","script":String(pane.editor.string.prefix(12000)),"output":String(pane.console.string.suffix(16000)),"truncated":pane.editor.string.count > 12000 || pane.console.string.count > 16000,"running":pane.isRunning]
            }
            var value = try await viewer.learningJavaScript(doc,"({text:document.body.innerText.slice(0,18000),truncated:document.body.innerText.length>18000,fields:Array.from(document.querySelectorAll('input:not([type=hidden]),select,textarea')).slice(0,80).map(x=>({name:x.name||x.id,value:x.value,checked:x.checked}))})")
            if doc.kind == "operation" { value["inputs"] = try await viewer.learningJavaScript(doc,"window.statsDirectOperation.tutorSnapshot()") }
            if doc.kind == "analysis" { value["inputs"] = try await viewer.learningJavaScript(doc,"window.statsDirectChiSquare.tutorSnapshot()") }
            try check()
            value["title"] = doc.title; value["kind"] = doc.kind; value["operation"] = doc.operationName
            if let report = doc.pendingResult { value["instantResult"] = Self.plain(report.body) }
            return value
        case "statsdirect_method_help":
            guard let operation = arguments["operation"] as? String, let path = viewer.analysisCatalog[operation]?["help"] as? String else { throw ChatGPTTutor.Failure(message:"Choose a method ID from the catalogue.") }
            let file = viewer.root.appendingPathComponent(path).standardizedFileURL
            guard file.path.hasPrefix(viewer.root.appendingPathComponent("Help").path + "/") else { throw ChatGPTTutor.Failure(message:"The bundled method page is unavailable.") }
            let raw = try String(contentsOf:file,encoding:.utf8)
            remember("StatsDirect help · " + operation)
            return ["operation":operation,"text":Self.plain(raw),"boundedExcerpt":true]
        case "statsdirect_run_analysis":
            guard let datasetID = arguments["datasetId"] as? String, let saved = datasets[datasetID],
                  let operation = arguments["operation"] as? String, TutorTools.operations.contains(operation) else { throw ChatGPTTutor.Failure(message:"Read the actual worksheet range first, then supply its datasetId and a supported method.") }
            let doc = try document(saved.document)
            guard doc.gridVersion == saved.version else { throw ChatGPTTutor.Failure(message:"The worksheet has changed. Read the data again before calculating.") }
            let agreement = arguments["agreement"] as? Bool ?? false
            let key = operation + datasetID + String(agreement) + (arguments["studyType"] as? String ?? "")
            if let result = results[key] { return result }
            guard !calculationBusy else { throw ChatGPTTutor.Failure(message:"A calculation is already running for this question. Wait for its result.") }
            calculationBusy = true; defer { calculationBusy = false }
            let output = try await TutorTools.run(operation:operation,dataset:saved.value,agreement:agreement,studyType:arguments["studyType"] as? String,preferences:UserDefaults.standard.dictionary(forKey:"analysisDefaults") ?? [:]) { [viewer] input in
                try await withCheckedThrowingContinuation { continuation in viewer.analysisRequest(input,entry:"statsdirect_operation") { continuation.resume(with:$0) } }
            }
            try check()
            guard doc.gridVersion == saved.version else { throw ChatGPTTutor.Failure(message:"The worksheet changed during calculation. Read and calculate the current data again.") }
            let title = viewer.analysisCatalog[operation]?["title"] as? String ?? operation
            let plan = try? RScriptGenerator.generate(operation:operation,title:title,output:output,resources:viewer.root)
            let id = UUID().uuidString, html = output["html"] as? String ?? ""
            let history = String(decoding:try JSONSerialization.data(withJSONObject:output["history"] ?? [],options:[.prettyPrinted,.sortedKeys]),as:UTF8.self)
            let body = "<h1>\(viewer.htmlEscape(title))</h1><p class='muted'>Calculated from the worksheet by StatsDirect \(viewer.htmlEscape(viewer.engineVersion)) · Learning</p>" + html + viewer.reportLinks(plan,helpPath:viewer.analysisCatalog[operation]?["help"] as? String,resultID:id) + "<details><summary>Inputs used for this report</summary><pre>\(viewer.htmlEscape(history))</pre></details>"
            let previous = viewer.learningLastDocumentID
            let report = viewer.appendReport(ReportEntry(id:id,title:title,operation:operation,body:body,rPlan:plan))
            viewer.learningLastDocumentID = previous
            if let learner { viewer.tabs.selectTabViewItem(learner.item) }
            let result: [String:Any] = ["state":"complete","operation":operation,"engineVersion":viewer.engineVersion,"datasetId":datasetID,"report":report.title,"reportId":report.id,"resultId":id,"text":Self.plain(html),"inputHistory":output["history"] ?? [],"values":output["values"] ?? [:],"hasSVG":html.contains("<svg")]
            results[key] = result; remember("\(title) · StatsDirect \(viewer.engineVersion) · \(report.title)")
            return result
        case "statsdirect_open_analysis":
            let doc = try document(arguments["documentId"] as? String ?? "")
            guard doc.kind == "grid", let operation = arguments["operation"] as? String, operation != "AnalysisOptions", let definition = viewer.analysisCatalog[operation], definition["unavailable"] == nil else { throw ChatGPTTutor.Failure(message:"Choose an available analysis method and worksheet.") }
            viewer.analysisSourceID = doc.id
            let item = NSMenuItem(); item.representedObject = operation
            viewer.openAnalysisOperation(item)
            remember("Opened " + (definition["title"] as? String ?? operation))
            return ["state":"awaiting_user_input","operation":operation,"message":"The analysis form is open with this worksheet as its source. No calculation has been completed by this tool."]
        default: throw ChatGPTTutor.Failure(message:"Unknown StatsDirect tool.")
        }
    }
    static func plain(_ html: String) -> String {
        String(html.replacingOccurrences(of:"(?is)<(script|style|svg)\\b[^>]*>.*?</\\1>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"<[^>]+>",with:" ",options:.regularExpression)
            .replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&lt;",with:"<").replacingOccurrences(of:"&gt;",with:">").replacingOccurrences(of:"&amp;",with:"&")
            .replacingOccurrences(of:"[ \\t]+",with:" ",options:.regularExpression).prefix(18000))
    }
}

extension Viewer {
    func learningJavaScript(_ doc: Document, _ script: String) async throws -> [String:Any] {
        try await withCheckedThrowingContinuation { continuation in
            doc.web.evaluateJavaScript(script) { value,error in
                if let error { continuation.resume(throwing:error) }
                else if let value = value as? [String:Any] { continuation.resume(returning:value) }
                else { continuation.resume(throwing:ChatGPTTutor.Failure(message:"The document is still loading. Return to it and try again.")) }
            }
        }
    }
    func refreshLearningWorkspace(_ doc: Document) {
        guard doc.learningTask == nil else { return }
        doc.learningContextRevision += 1; let revision = doc.learningContextRevision
        let sourceID = doc.learningSourceID.isEmpty ? learningLastDocumentID : doc.learningSourceID
        let source = documents.first(where:{$0.id == sourceID})
        let choices = documents.filter{$0.kind != "learn"}.map{["id":$0.id,"title":$0.title]}
        Task { @MainActor in
            var label = doc.learningSourceID == "__none__" ? "Lessons only · open documents are not shared" : source.map{"Using: " + $0.title} ?? "No document selected · open documents are available to the tutor"
            if let source, source.kind == "grid", doc.learningSourceID != "__none__" {
                do {
                    let data = try await learningJavaScript(source,"window.statsDirectGrid.tutorData()")
                    label = "Using: \(data["workbook"] ?? source.title) · \(data["sheet"] ?? "") · \(data["range"] ?? "") · \(data["rowCount"] ?? 0) rows"
                } catch { label += " · tutor can find columns by name, or use your selection" }
            }
            guard doc.learningContextRevision == revision, doc.learningTask == nil else { return }
            learningScript(doc,"workspace",["choice":doc.learningSourceID,"choices":choices,"label":label])
        }
    }
}
