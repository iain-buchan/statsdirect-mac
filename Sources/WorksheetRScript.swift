import Foundation

enum WorksheetRScript {
    // The R input frame includes a 36-character command UUID and a newline.
    static let maximumBytes = 8 * 1024 * 1024 - 37
    static let sizeMessage = "The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export."

    static func build(_ data: [String: Any]) throws -> String {
        guard let columns = data["columns"] as? [[String: Any]], !columns.isEmpty,
              let rowCount = data["rowCount"] as? Int, rowCount > 0 else {
            throw ConversationRScript.Failure(message: "The worksheet selection could not be read.")
        }
        let source = [data["workbook"], data["sheet"], data["range"]].compactMap { $0 as? String }.joined(separator: " / ")
        // Keep source metadata on one comment line even if a workbook was named
        // with line breaks. Every actual data string uses the shared R quoting.
        let comment = source.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        var script = "# Worksheet selection: \(comment)\n# Review the data, then choose Run to create data in R.\n"
        script += "# Blank cells are NA. In numeric columns, * is also NA.\n"
        script += "data <- as.data.frame(setNames(list(\n"
        var names: [String] = []
        for (index, column) in columns.enumerated() {
            guard let title = column["title"] as? String,
                  let values = column["values"] as? [String], values.count == rowCount,
                  let kinds = column["kinds"] as? [String], kinds.count == rowCount else {
                throw ConversationRScript.Failure(message: "The worksheet selection is incomplete.")
            }
            let numeric = zip(values, kinds).contains { !$0.0.isEmpty && $0.1 == "number" }
                && zip(values, kinds).allSatisfy { $0.0.isEmpty || $0.0 == "*" || $0.1 == "number" }
            var parts: [String] = []
            var columnBytes = 0
            let scriptBytes = script.utf8.count
            for (text, kind) in zip(values, kinds) {
                let literal: String
                if text.isEmpty || numeric && text == "*" { literal = numeric ? "NA_real_" : "NA" }
                else if kind == "number" {
                    guard let number = Double(text), number.isFinite else {
                        throw ConversationRScript.Failure(message: "The selection contains an invalid numeric value.")
                    }
                    literal = try ConversationRScript.literal(text)
                } else if kind == "boolean", ["true", "false"].contains(text.lowercased()) {
                    literal = text.lowercased() == "true" ? "TRUE" : "FALSE"
                } else { literal = try ConversationRScript.quote(text) }
                columnBytes += literal.utf8.count + 2
                guard scriptBytes + columnBytes <= maximumBytes else {
                    throw ConversationRScript.Failure(message: sizeMessage)
                }
                parts.append(literal)
            }
            script += "  c(" + parts.joined(separator: ", ") + ")" + (index + 1 < columns.count ? ",\n" : "\n")
            names.append(try ConversationRScript.quote(title))
        }
        script += "), c(" + names.joined(separator: ", ") + ")), check.names = FALSE, optional = TRUE, stringsAsFactors = FALSE)\n\n"
        script += "head(data)\n"
        guard script.utf8.count <= maximumBytes else { throw ConversationRScript.Failure(message: sizeMessage) }
        return script
    }
}
