import Foundation

/// Builds a local, reviewable replay. No evaluation or access to current documents.
enum ConversationRScript {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    /// What a host says when a clicked block is not in its own reading of the saved reply (HOST-CONTRACT.md, Code blocks).
    static let unmatchedNotice = "StatsDirect could not match that code block to the saved reply. Select the code in the conversation and copy it instead."
    /// A completed fenced block of a reply: whether its language is R, the code as the page shows it (leading tabs
    /// as spaces), which is what a click sends, and the code as the reply has it, which is what is opened or copied.
    struct CodeBlock: Equatable { let r: Bool; let shown: String; let text: String }
    struct Block { let code: String }
    /// The completed R blocks of a reply, as they are opened or copied.
    static func blocks(_ markdown: String) -> [Block] { readBlocks(markdown).filter(\.r).map { Block(code:$0.text) } }

    // The reader below mirrors the shared reference, Learning/code-blocks.mjs in the Learning package, line for line;
    // Learning/code-block-examples.json holds the replies that the page, the reference and this reader are tested against.
    // It works on UTF-16 units, as the reference does.
    private typealias Units = [UInt16]
    private static let space: UInt16 = 32, tab: UInt16 = 9, backtick: UInt16 = 96, tilde: UInt16 = 126
    /// marked expands a line's leading tabs before it reads the line: leading spaces, then a run of tabs, four spaces each.
    private static func expandTabs(_ line: Units) -> Units {
        var spaces = 0; while spaces < line.count && line[spaces] == space { spaces += 1 }
        var end = spaces; while end < line.count && line[end] == tab { end += 1 }
        guard end > spaces else { return line }
        return Units(repeating:space,count:spaces + 4 * (end - spaces)) + line[end...]
    }
    /// Removes up to `limit` block-quote markers (spaces, ">", one optional space or tab) from the start of a line.
    private static func unquote(_ line: Units, limit: Int = .max) -> (line: Units, depth: Int) {
        var start = 0, depth = 0
        while depth < limit {
            var i = start; while i < line.count && line[i] == space { i += 1 }
            guard i < line.count && line[i] == 62 else { break }
            i += 1; if i < line.count && (line[i] == space || line[i] == tab) { i += 1 }
            start = i; depth += 1
        }
        return (Units(line[start...]), depth)
    }
    private struct Opener { let indent: Int; let fence: Units; let language: String }
    /// An opening fence: any spaces, then three or more backticks with no backtick in the rest of the line, or three or
    /// more tildes with anything after. It may also sit on a list marker's own line ("- ```r", "1. ```r"); the marker and
    /// the one to four spaces after it then count as indent. The language is the first word of the label.
    private static func opener(_ line: Units) -> Opener? {
        var i = 0; while i < line.count && line[i] == space { i += 1 }
        var marker = i
        if marker < line.count && [45, 42, 43].contains(line[marker]) { marker += 1 }          // - * +
        else {
            var digits = 0; while marker < line.count && digits < 9 && line[marker] >= 48 && line[marker] <= 57 { marker += 1; digits += 1 }
            if digits > 0 && marker < line.count && (line[marker] == 46 || line[marker] == 41) { marker += 1 } else { marker = i }   // . )
        }
        if marker > i {
            var after = marker; while after < line.count && line[after] == space { after += 1 }
            let gap = after - marker
            if gap >= 1 && gap <= 4 && after < line.count && (line[after] == backtick || line[after] == tilde) { i = after }
        }
        guard i < line.count, line[i] == backtick || line[i] == tilde else { return nil }
        let mark = line[i]; var end = i; while end < line.count && line[end] == mark { end += 1 }
        guard end - i >= 3 else { return nil }
        let label = line[end...]
        // The label runs to the end of the line, whatever it holds; a backtick fence's label may not hold a backtick.
        guard !(mark == backtick && label.contains(backtick)) else { return nil }
        // trim() and split(/[ \t]+/, 1) as JavaScript has them.
        let blank: (UInt16) -> Bool = { [9, 10, 11, 12, 13, 32, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains($0) || (0x2000...0x200A).contains($0) }
        var first = label.startIndex, last = label.endIndex
        while first < last && blank(label[first]) { first += 1 }
        while last > first && blank(label[last - 1]) { last -= 1 }
        var word = first; while word < last && label[word] != space && label[word] != tab { word += 1 }
        return Opener(indent:i,fence:Units(line[i..<end]),language:String(decoding:label[first..<word],as:UTF16.self).lowercased())
    }
    /// A closing fence, as marked reads it: spaces (at most three more than the opener's indent), the opener's own
    /// fence, any further backticks or tildes, then only spaces.
    private static func closes(_ line: Units,_ open: Opener) -> Bool {
        var spaces = 0; while spaces < line.count && line[spaces] == space { spaces += 1 }
        guard spaces <= open.indent + 3, line[spaces...].starts(with:open.fence) else { return false }
        var i = spaces + open.fence.count
        while i < line.count && (line[i] == backtick || line[i] == tilde) { i += 1 }
        while i < line.count && line[i] == space { i += 1 }
        return i == line.count
    }
    /// The completed fenced blocks of a reply, in order. A block with no closing fence is not returned:
    /// an unfinished streamed block is never offered as complete code.
    static func readBlocks(_ markdown: String) -> [CodeBlock] {
        let original = markdown.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").components(separatedBy:"\n").map { Units($0.utf16) }
        let lines = original.map(expandTabs)
        var blocks: [CodeBlock] = [], i = 0
        while i < lines.count {
            let quoted = unquote(lines[i])
            guard let open = opener(quoted.line) else { i += 1; continue }
            var shown: [Units] = [], text: [Units] = [], closed = false
            i += 1
            while i < lines.count {
                // A line inside the block loses as many quote markers as its opener had, then the opener's indent,
                // but only when it begins with at least that many spaces; a line indented less is left as it is.
                let rest = unquote(lines[i],limit:quoted.depth).line
                if closes(rest,open) { closed = true; break }
                let indented = rest.count >= open.indent && !rest[..<open.indent].contains { $0 != space }
                let code = indented ? Units(rest[open.indent...]) : rest
                let removed = lines[i].count - code.count
                shown.append(code)
                // The reply's own characters when the removed prefix is literally there; otherwise the shown line.
                text.append(original[i].starts(with:lines[i][..<removed]) ? Units(original[i][removed...]) : code)
                i += 1
            }
            let join: ([Units]) -> String = { $0.map { String(decoding:$0,as:UTF16.self) }.joined(separator:"\n") }
            if closed { blocks.append(CodeBlock(r:open.language == "r" || open.language == "rscript",shown:join(shown),text:join(text))) }
            i += 1
        }
        return blocks
    }
    /// Which block a click means. `position` is the block's place among the page's buttons (among R blocks when
    /// `rOnly`, among all blocks otherwise) and `shown` is the code text the page sent with the click. Returns the
    /// index in that same list, or -1. The block at the position wins when its shown text is the page's text;
    /// otherwise the first block with that text; otherwise there is no match, and no other block is used.
    static func findBlock(_ blocks: [CodeBlock], position: Int, shown: String, rOnly: Bool = true) -> Int {
        let list = rOnly ? blocks.filter(\.r) : blocks
        // Unit for unit, as the reference compares them; Swift's own == would also accept canonically equivalent text.
        let wanted = Array(shown.utf16)
        if list.indices.contains(position) && list[position].shown.utf16.elementsEqual(wanted) { return position }
        return list.firstIndex { $0.shown.utf16.elementsEqual(wanted) } ?? -1
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
    /// Text as an R string literal (worksheet R rules, 3.10). R strings cannot hold NUL, so it is refused, scalar by scalar.
    /// Control characters, and the bidi controls U+202A to U+202E and U+2066 to U+2069, which R refuses raw in a string
    /// ("bidi formatting not allowed"), are written as \u escapes; R reads every escape back as the same character.
    static func quote(_ text: String) throws -> String {
        var result = "\""
        for c in text.unicodeScalars {
            switch c.value {
            case 0: throw Failure(message:"The worksheet contains a null character that R strings cannot represent.")
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 9: result += "\\t"
            case 1..<32, 127...159, 0x202A...0x202E, 0x2066...0x2069: result += String(format:"\\u%04x",c.value)
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
