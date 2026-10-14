import Foundation

/// Builds a local, reviewable replay. No evaluation or access to current documents.
enum ConversationRScript {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Block { let code: String; let endLine: Int }
    static func blocks(_ markdown: String) -> [Block] {
        let lines = markdown.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").components(separatedBy:"\n")
        let opening = try! NSRegularExpression(pattern:"^ {0,3}(`{3,}|~{3,})[ \\t]*([\\w+#.-]*)[ \\t]*$")
        var result: [Block] = [], i = 0
        while i < lines.count {
            let line = lines[i] as NSString
            guard let match = opening.firstMatch(in:lines[i],range:NSRange(location:0,length:line.length)) else { i += 1; continue }
            let fence = line.substring(with:match.range(at:1)), language = line.substring(with:match.range(at:2)).lowercased()
            let closing = try! NSRegularExpression(pattern:"^ {0,3}" + NSRegularExpression.escapedPattern(for:String(fence.first!)) + "{\(fence.count),}[ \\t]*$")
            var code: [String] = []; i += 1
            while i < lines.count && closing.firstMatch(in:lines[i],range:NSRange(location:0,length:(lines[i] as NSString).length)) == nil { code.append(lines[i]); i += 1 }
            // Never offer an unfinished streamed block as complete code.
            if i < lines.count && ["r","rscript"].contains(language) { result.append(Block(code:code.joined(separator:"\n"),endLine:i)) }
            i += 1
        }
        return result
    }
    static func build(_ messages: [[String:String]], messageIndex: Int, blockIndex: Int = -1) throws -> String {
        guard messages.indices.contains(messageIndex), ["user","assistant"].contains(messages[messageIndex]["role"] ?? "") else {
            throw Failure(message:"Wait for the reply to finish before opening its R code.")
        }
        let selected = blocks(messages[messageIndex]["text"] ?? "")
        guard !selected.isEmpty, blockIndex >= -1, blockIndex < selected.count else { throw Failure(message:"This message contains no completed R code block.") }
        var result = "# AI suggestion — review before running. Nothing has been run automatically.\n# Source snapshots and earlier R blocks are included in conversation order.\n# Review earlier examples too: running this script runs all included code.\n"
        var previousSource = ""
        func append(_ label: String,_ code: String) throws {
            guard !code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
            guard result.utf8.count + code.utf8.count <= 2_000_000 else { throw Failure(message:"The conversation is too large for one R script. Start a new conversation with the relevant source.") }
            result += "\n# " + label + "\n" + code + "\n"
        }
        for i in 0...messageIndex {
            let message = messages[i], source = message["rSource"] ?? ""
            if !source.isEmpty && source != previousSource { try append("Source script snapshot shared for this question",source); previousSource = source }
            try append("Worksheet values read for this reply (fixed snapshot)",message["rData"] ?? "")
            guard ["user","assistant"].contains(message["role"] ?? "") else { continue }
            let code = blocks(message["text"] ?? "")
            for b in 0..<(i == messageIndex && blockIndex >= 0 ? blockIndex + 1 : code.count) {
                try append((i == messageIndex ? "Selected message" : "Earlier conversation") + " — R block \(b + 1)",code[b].code)
            }
        }
        return result
    }
    static func quote(_ text: String) throws -> String {
        guard !text.contains("\0") else { throw Failure(message:"The worksheet contains a null character that R strings cannot represent.") }
        var result = "\""
        for c in text.unicodeScalars {
            switch c.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 9: result += "\\t"
            case 0..<32, 127: result += String(format:"\\u%04x",c.value)
            default: result.unicodeScalars.append(c)
            }
        }
        return result + "\""
    }
    static func literal(_ value: Any) throws -> String {
        if value is NSNull { return "NA" }
        let text = value as? String ?? String(describing:value)
        // Only decimal numeric syntax is executable; worksheet text is always quoted.
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if clean.range(of:"^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$",options:.regularExpression) != nil,
           let number = Double(clean), number.isFinite { return clean }
        return try quote(text)
    }
    static func dataset(_ data: [String:Any]) throws -> String {
        guard let id = data["datasetId"] as? String, let columns = data["columns"] as? [[String:Any]], !columns.isEmpty else { throw Failure(message:"The worksheet snapshot is unavailable.") }
        var values: [String] = [], names: [String] = []
        for column in columns {
            guard let index = column["index"] as? Int, let cells = column["values"] as? [Any] else { throw Failure(message:"The worksheet snapshot is incomplete.") }
            values.append("  c(" + (try cells.map(literal)).joined(separator:", ") + ")")
            names.append(try quote("column_\(index)"))
        }
        return "if (!exists(\".statsdirect_data\", inherits = FALSE)) .statsdirect_data <- list()\n.statsdirect_data[[" + (try quote(id)) + "]] <- setNames(list(\n" + values.joined(separator:",\n") + "\n), c(" + names.joined(separator:", ") + "))\n"
    }
}
