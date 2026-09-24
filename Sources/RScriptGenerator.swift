import Foundation
import CoreFoundation

/// Generates a standalone base-R script from a completed run, never from a live worksheet.
struct RScriptPlan {
    let script: String
    let hasRecipe: Bool
    let detail: String
}

enum RScriptGenerator {
    static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 9: result += "\\t"
            case 0...31, 127: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
    static func namedList(_ entries: [(String, String)]) -> String {
        // setNames permits empty and duplicate labels without treating names as R code.
        "setNames(list(" + entries.map { $0.1 }.joined(separator: ",\n  ") + "), c(" + entries.map { string($0.0) }.joined(separator: ", ") + "))"
    }
    static func literal(_ value: Any) -> String {
        if value is NSNull { return "NULL" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "TRUE" : "FALSE" }
            let n = number.doubleValue
            return n.isFinite ? number.stringValue : n.isNaN ? "NaN" : n > 0 ? "Inf" : "-Inf"
        }
        if let text = value as? String { return string(text) }
        if let array = value as? [Any] { return "list(" + array.map(literal).joined(separator: ", ") + ")" }
        if let object = value as? [String: Any] {
            if object.isEmpty { return "list()" }
            return namedList(object.keys.sorted().map { ($0, literal(object[$0]!)) })
        }
        return "NULL"
    }
    static func vector(_ values: [Any], numeric: Bool) -> String {
        let entries = values.map { value -> String in
            if value is NSNull { return numeric ? "NA_real_" : "NA_character_" }
            let text = (value as? String ?? String(describing: value)).trimmingCharacters(in: .whitespacesAndNewlines)
            if numeric {
                if text.isEmpty || text == "*" { return "NA_real_" }
                if let n = Double(text), n.isFinite { return String(n) }
                // Category columns remain text; no silent numeric coercion.
            }
            return string(value as? String ?? text)
        }
        if entries.isEmpty { return numeric ? "numeric(0)" : "character(0)" }
        return "c(" + entries.joined(separator: ", ") + ")"
    }
    static func generate(operation: String, title: String, output: [String: Any], resources: URL) throws -> RScriptPlan {
        let manifestURL = resources.appendingPathComponent("R/analysis-recipes.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: [String: String]] ?? [:]
        let recipe = manifest[operation]
        let history = output["history"] as? [[String: Any]] ?? []
        var scriptHistory = [[String: Any]]()
        var parameters = [String: Any](), frames = [(String, [String: Any], String)]()
        for (i, step) in history.enumerated() {
            var historyStep = step
            let name = step["name"] as? String ?? step["title"] as? String ?? "input_\(i + 1)"
            let value = step["value"] ?? NSNull()
            if let frame = value as? [String: Any], frame["columns"] != nil {
                // Retain every acquisition, even repeated prompts sharing a parameter name.
                var key = name; var n = 2
                while frames.contains(where: { $0.0 == key }) { key = name + "_\(n)"; n += 1 }
                frames.append((key, frame, step["mode"] as? String ?? "NumericReplaceMissing"))
                // Keep the spreadsheet provenance, but write the data only once.
                // The report still retains its complete original input history.
                var reference = frame
                reference.removeValue(forKey: "columns")
                reference["data_frame"] = key
                historyStep["value"] = reference
            } else if step["kind"] as? String == "confidence", let n = Double(String(describing: value)) {
                parameters[name] = n / 100
            } else { parameters[name] = value }
            scriptHistory.append(historyStep)
        }
        if let input = output["input"] as? [String: Any] { parameters = input }
        let detail = recipe?["detail"] ?? "Data and settings only: an equivalent R implementation of this method is not yet available."
        var code = """
        # StatsDirect — continue this completed analysis in R
        # The snapshot below belongs to this report; subsequent worksheet edits do not change it.
        # \(detail)
        # No packages are installed. This script can also be saved and run outside StatsDirect.
        operation <- \(string(operation))
        analysis_title <- \(string(title))
        parameters <- \(literal(parameters))
        original_results <- \(literal(output["values"] ?? [:]))
        # Data inputs in this history refer to the exact selected columns in data_frames.
        input_history <- \(literal(scriptHistory))
        data_frames <- list()

        """
        for (key, frame, mode) in frames {
            let columns = frame["columns"] as? [[String: Any]] ?? []
            code += "\n# Input: " + string(key) + "\n"
            let entries = columns.enumerated().map { i, column -> (String, String) in
                let title = column["title"] as? String ?? "Column \(i + 1)"
                let values = column["values"] as? [Any] ?? []
                let textMode = mode.hasPrefix("Text") || mode.hasPrefix("Category") || mode == "GroupIdentifiers" || mode == "DateReplaceMissing"
                let allNumeric = values.allSatisfy { value in
                    if value is NSNull { return true }
                    let t = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty || t == "*" || Double(t)?.isFinite == true
                }
                return (title, vector(values, numeric: !textMode && allNumeric))
            }
            code += "data_frames[[" + string(key) + "]] <- " + namedList(entries) + "\n"
        }
        code += "\n# Output tables produced by StatsDirect, retained for further analysis.\nresult_tables <- list()\n"
        for (index, frame) in (output["frames"] as? [[String: Any]] ?? []).enumerated() {
            let rows = max(0, (frame["rows"] as? Int ?? 1) - 1)
            let count = frame["columns"] as? Int ?? 0
            let cells = frame["cells"] as? [[String: Any]] ?? []
            var cellIndex = [String: [String: Any]]()
            for cell in cells { if let c = cell["col"] as? Int, let r = cell["row"] as? Int { cellIndex["\(c),\(r)"] = cell } }
            let columns = (0..<count).map { c -> (String, String) in
                let title = cellIndex["\(c),0"]?["text"] as? String ?? "Column \(c + 1)"
                let values = (0..<rows).map { r -> Any in cellIndex["\(c),\(r + 1)"]?["text"] ?? NSNull() }
                let numeric = (0..<rows).allSatisfy { r in cellIndex["\(c),\(r + 1)"] == nil || cellIndex["\(c),\(r + 1)"]?["kind"] as? String == "number" }
                return (title, vector(values, numeric: numeric))
            }
            code += "result_tables[[\(index + 1)]] <- as.data.frame(" + namedList(columns) + ", check.names = FALSE)\n"
        }
        let helpers = try String(contentsOf: resources.appendingPathComponent("R/recipes/helpers.R"), encoding: .utf8)
        code += "\n" + helpers + "\n# Analysis — edit or extend the following code.\n"
        if let file = recipe?["file"] {
            guard !file.contains("/"), file.hasSuffix(".R") else { throw CocoaError(.fileReadCorruptFile) }
            code += try String(contentsOf: resources.appendingPathComponent("R/recipes/" + file), encoding: .utf8)
        } else {
            code += "cat(\(string(detail + "\n")))\nstr(data_frames)\nstr(result_tables)\nprint(parameters)\n# original_results contains the StatsDirect results for reference.\n# Add your R analysis here.\n"
        }
        return RScriptPlan(script: code + "\n", hasRecipe: recipe != nil, detail: detail)
    }
}
