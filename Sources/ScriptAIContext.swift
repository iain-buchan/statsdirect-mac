import Cocoa

/// Read-only, per-question access. No document names or contents enter the
/// provider request until the pane has checked the user's sharing confirmation.
@MainActor final class ScriptAIContext {
    unowned let viewer: Viewer
    let script: Document?
    let workbook: Document?
    private let version: Int?
    private let scriptSnapshot: [String:Any]?
    let rSource: String
    private(set) var rData = ""
    private let active: () -> Bool
    init(viewer: Viewer, script: Document?, workbook: Document?, active: @escaping () -> Bool) {
        self.rSource=script?.rPane?.editor.string ?? ""
        self.viewer=viewer; self.script=script; self.workbook=workbook; self.version=workbook?.gridVersion; self.active=active
        if let script, let pane=script.rPane {
            scriptSnapshot=["documentId":script.id,"title":script.title,"kind":"r","script":String(pane.editor.string.prefix(12000)),"output":String(pane.console.string.suffix(8000)),"truncated":pane.editor.string.count>12000 || pane.console.string.count>8000,"running":pane.isRunning,"snapshot":true]
        } else { scriptSnapshot=nil }
    }
    var tools: [[String:Any]] {
        TutorTools.definitions.filter { row in
            switch row["name"] as? String {
            case "statsdirect_workspace", "statsdirect_method_help": return true
            case "statsdirect_read_data": return workbook != nil
            case "statsdirect_read_document": return script != nil
            default: return false
            }
        }.map { row in
            var tool=row
            switch tool["name"] as? String {
            case "statsdirect_workspace": tool["description"]="List only documents approved for this question, with worksheet headings and selections. No unapproved documents are exposed."
            case "statsdirect_read_document": tool["description"]="Read the approved, fixed script/output snapshot. Returns explicit bounds and truncation. Does not run R or alter the script."
            case "statsdirect_read_data": tool["description"]="Read cells from the approved workbook. Defaults to its selected or used range. Rows are 1-based worksheet numbers; columns and sheetIndex are 0-based. Values preserve missing cells and their original text. At most 32 columns and 4,000 cells per read; never silently sampled. No engine execution is available."
            default: break
            }
            return tool
        }
    }
    func check() throws {
        try TutorPolicy.check(); try Task.checkCancellation()
        guard active() else { throw CancellationError() }
        for doc in [script,workbook].compactMap({$0}) {
            guard viewer.documents.contains(where:{$0 === doc}) else { throw ChatGPTTutor.Failure(message:"A shared document was closed. Send again to choose the current context.") }
        }
        if let workbook, workbook.gridVersion != version { throw ChatGPTTutor.Failure(message:"The workbook changed after confirmation. Check it and confirm sharing again for a new question.") }
    }
    func overview() async throws -> [String:Any] {
        try check(); var documents: [[String:Any]]=[]
        if let script { documents.append(["documentId":script.id,"title":script.title,"kind":"r","operation":script.operationName ?? ""]) }
        if let workbook {
            let info=try await viewer.learningJavaScript(workbook,"window.statsDirectGrid.tutorInfo()")
            try check()
            documents.append(["documentId":workbook.id,"title":workbook.title,"kind":"grid","worksheet":info])
        }
        return ["documents":documents,"sharing":documents.isEmpty ? "Question and conversation only; no application documents are shared." : "Only the listed documents are shared for this question. Script/output are fixed snapshots; workbook reads are bounded and reject content changes."]
    }
    func context() async throws -> String {
        var payload=try await overview()
        if let scriptSnapshot { payload["currentScript"]=scriptSnapshot }
        var json=String(decoding:try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),as:UTF8.self)
        if json.count>28000 {
            // Keep the initial reference valid and bounded. Detailed worksheet
            // headings and the script remain available through scoped tools.
            payload["documents"]=[script,workbook].compactMap{$0}.map{["documentId":$0.id,"kind":$0.kind,"title":String($0.title.prefix(200))]}
            payload["currentScript"]=nil;payload["readDetailsWithTools"]=true
            json=String(decoding:try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),as:UTF8.self)
        }
        return json
    }
    func call(_ name: String, _ arguments: [String:Any]) async throws -> [String:Any] {
        try check()
        guard let spec=tools.first(where:{$0["name"] as? String==name}),
              let schema=spec["inputSchema"] as? [String:Any], let properties=schema["properties"] as? [String:Any],
              Set(arguments.keys).isSubset(of:Set(properties.keys)),
              (schema["required"] as? [String] ?? []).allSatisfy({arguments[$0] != nil}) else { throw ChatGPTTutor.Failure(message:"This question does not allow that AI action.") }
        switch name {
        case "statsdirect_workspace": return try await overview()
        case "statsdirect_read_document":
            guard let script, arguments["documentId"] as? String==script.id, let scriptSnapshot else { throw ChatGPTTutor.Failure(message:"That script was not approved for this question.") }
            return scriptSnapshot
        case "statsdirect_read_data":
            guard let workbook, arguments["documentId"] as? String==workbook.id else { throw ChatGPTTutor.Failure(message:"That workbook was not approved for this question.") }
            var options=arguments; options.removeValue(forKey:"documentId")
            let json=String(decoding:try JSONSerialization.data(withJSONObject:options),as:UTF8.self)
            var result=try await viewer.learningJavaScript(workbook,"window.statsDirectGrid.tutorData(\(json))")
            try check()
            result["datasetId"]=UUID().uuidString
            let code=try ConversationRScript.dataset(result)
            result["rCode"]=code; rData += code + "\n"
            return result
        case "statsdirect_method_help":
            guard let operation=arguments["operation"] as? String, let path=viewer.analysisCatalog[operation]?["help"] as? String else { throw ChatGPTTutor.Failure(message:"Choose a documented StatsDirect method.") }
            let file=viewer.root.appendingPathComponent(path).standardizedFileURL
            guard file.path.hasPrefix(viewer.root.appendingPathComponent("Help").path+"/") else { throw ChatGPTTutor.Failure(message:"The method help is unavailable.") }
            return ["operation":operation,"text":LearningWorkspace.plain(try String(contentsOf:file,encoding:.utf8)),"boundedExcerpt":true]
        default: throw ChatGPTTutor.Failure(message:"Unknown AI action.")
        }
    }
}
