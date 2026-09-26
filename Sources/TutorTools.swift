import Foundation

/// The tutor names app-owned datasets, never supplies substitute numbers or executable code.
enum TutorTools {
    static let operations = ["TPaired","UnivariateSummary","Chi2by2","ExactFisher","Wilcoxon","TUnpaired","Spearman","Agreement","Normality","QuickSummary"]
    static func tool(_ name: String, _ description: String, _ properties: [String:Any], required: [String] = []) -> [String:Any] {
        ["type":"function","name":name,"description":description,"inputSchema":["type":"object","properties":properties,"required":required,"additionalProperties":false]]
    }
    static var definitions: [[String:Any]] {
        let string: [String:Any] = ["type":"string"], integer: [String:Any] = ["type":"integer","minimum":0]
        return [
            tool("statsdirect_workspace","List available open StatsDirect documents, worksheet headings and selections. Read this before saying you cannot see data. IDs are valid only for the current question.",[:]),
            tool("statsdirect_read_data","Read actual cells from an open worksheet. Defaults to its selection, otherwise its used data. Row numbers are 1-based worksheet rows; columns and sheetIndex are 0-based. Returns a datasetId for calculations, with exact missing-cell positions. Never claim the bundled lesson values are these data.",["documentId":string,"sheetIndex":integer,"columns":["type":"array","items":integer,"minItems":1,"maxItems":32],"firstRow":["type":"integer","minimum":1],"lastRow":["type":"integer","minimum":1]],required:["documentId"]),
            tool("statsdirect_read_document","Read an open analysis form, report, help page or R script/output. Reads its current contents; does not run R or change it.",["documentId":string],required:["documentId"]),
            tool("statsdirect_method_help","Read bundled StatsDirect method help. Use operation IDs from the supplied catalogue. No file paths or web URLs are accepted.",["operation":string],required:["operation"]),
            tool("statsdirect_run_analysis","Run the unchanged StatsDirect calculation engine on a datasetId from statsdirect_read_data when the learner asks for a calculation or interpretation requiring it. Supported methods are enumerated. Adds the real results and equivalent R link to the active report. Data order defines subtraction/group order. Uses current analysis defaults; never invent or replace values. For other methods use statsdirect_open_analysis.",["datasetId":string,"operation":["type":"string","enum":operations],"agreement":["type":"boolean"],"studyType":["type":"string","enum":["casecontrol","cohort","neither"],"description":"For Chi2by2, state the known study design; do not infer it from counts. Use neither for a generic independence table."]],required:["datasetId","operation"]),
            tool("statsdirect_open_analysis","Open a StatsDirect analysis form with the referenced worksheet as input so the learner can review and run a method not supported by direct tutor calculation. This only opens the form; do not claim it calculated results.",["operation":string,"documentId":string],required:["operation","documentId"])
        ]
    }
    static func frame(_ dataset: [String:Any]) throws -> [String:Any] {
        guard dataset["complete"] as? Bool == true, dataset["hasErrors"] as? Bool != true, dataset["hasStaleFormulas"] as? Bool != true,
              let columns = dataset["columns"] as? [[String:Any]], !columns.isEmpty, columns.count <= 32,
              let count = dataset["rowCount"] as? Int, count > 0, count <= 4000, count * columns.count <= 4000,
              columns.allSatisfy({($0["values"] as? [Any])?.count == count}) else {
            throw ChatGPTTutor.Failure(message:"The data range is incomplete, contains Excel errors or has stale formula results. Correct it in the worksheet before calculating.")
        }
        return ["preserveRows":true,"range":["firstRow":dataset["firstRow"] ?? 1,"lastRow":dataset["lastRow"] ?? count,"columns":columns.map{$0["index"] ?? 0}],"columns":columns.map{["title":$0["title"] ?? "Variable","values":$0["values"] ?? []]},"source":"\(dataset["workbook"] ?? "Worksheet") / \(dataset["sheet"] ?? "") · \(dataset["range"] ?? "")","firstRow":dataset["firstRow"] ?? 1,"lastRow":dataset["lastRow"] ?? count]
    }
    static func answer(_ prompt: [String:Any], frame: [String:Any], agreement: Bool, studyType: String? = nil) throws -> Any {
        if let error = prompt["error"] as? String, !error.isEmpty { throw ChatGPTTutor.Failure(message:error) }
        if prompt["name"] as? String == "study_type" {
            guard let studyType, ["casecontrol","cohort","neither"].contains(studyType) else { throw ChatGPTTutor.Failure(message:"Specify whether this is a case-control, cohort or generic contingency table (neither). The study design cannot be inferred from counts.") }
            return studyType
        }
        switch prompt["kind"] as? String {
        case "grid":
            let columns = frame["columns"] as? [[String:Any]] ?? []
            guard columns.count >= (prompt["minColumns"] as? Int ?? 1), columns.count <= (prompt["maxColumns"] as? Int ?? 32),
                  prompt["fixedRows"] as? Bool != true || columns.allSatisfy({($0["values"] as? [Any])?.count == prompt["rows"] as? Int}) else { throw ChatGPTTutor.Failure(message:"The selected range does not match the required data dimensions. Read a correctly sized range; no cells have been cropped.") }
            return frame
        case "boolean": return prompt["name"] as? String == "doAgreement" ? agreement : prompt["defaultValue"] as? Bool ?? false
        case "options":
            let items = prompt["options"] as? [[String:Any]] ?? []
            return Dictionary(uniqueKeysWithValues:items.compactMap { row -> (String,Any)? in guard let key = row["value"] as? String else { return nil }; return (key,row["selected"] ?? false) })
        case "fields", "settings":
            let items = prompt["fields"] as? [[String:Any]] ?? []
            return Dictionary(uniqueKeysWithValues:items.compactMap { row -> (String,Any)? in guard let key = row["name"] as? String, let value = row["defaultValue"] else { return nil }; return (key,value) })
        default:
            if let value = prompt["defaultValue"], !(value is NSNull) { return value }
            throw ChatGPTTutor.Failure(message:"This analysis needs an additional choice. Open its StatsDirect form to continue.")
        }
    }
    @MainActor static func run(operation: String, dataset: [String:Any], agreement: Bool, studyType: String? = nil, preferences: [String:Any], request: @escaping ([String:Any]) async throws -> [String:Any]) async throws -> [String:Any] {
        guard operations.contains(operation) else { throw ChatGPTTutor.Failure(message:"Use the StatsDirect form for this method.") }
        let frame = try frame(dataset), id = UUID().uuidString
        defer { Task { @MainActor in
            _ = try? await request(["action":"cancel","id":id])
            for _ in 0..<100 {
                let state = try? await request(["action":"poll","id":id])
                if state?["state"] as? String != "running" { break }
                try? await Task.sleep(nanoseconds:50_000_000)
            }
            _ = try? await request(["action":"release","id":id])
        } }
        var start: [String:Any] = ["action":"start","id":id,"operation":operation]
        if !preferences.isEmpty { start["preferences"] = preferences }
        var output = try await request(start)
        let deadline = Date().addingTimeInterval(60); var answers = 0
        while Date() < deadline {
            try Task.checkCancellation()
            switch output["state"] as? String {
            case "complete": return output
            case "failed", "cancelled": throw ChatGPTTutor.Failure(message:output["error"] as? String ?? "The calculation did not complete.")
            case "input":
                answers += 1
                guard answers <= 20, let prompt = output["prompt"] as? [String:Any], let token = output["token"] else { throw ChatGPTTutor.Failure(message:"Open the analysis form to finish these inputs.") }
                let value = try answer(prompt,frame:frame,agreement:agreement,studyType:studyType)
                output = try await request(["action":"answer","id":id,"token":token,"value":value])
            default:
                if let error = output["error"] as? String { throw ChatGPTTutor.Failure(message:error) }
                try await Task.sleep(nanoseconds:50_000_000)
                output = try await request(["action":"poll","id":id])
            }
        }
        throw ChatGPTTutor.Failure(message:"The calculation took too long and was stopped. Use the analysis form to continue.")
    }
}
