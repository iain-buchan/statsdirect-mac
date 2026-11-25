import Foundation

/// Method suggestions in an AI Assist reply are written `[[method:ID]]`. The instructions ask for each on a line of
/// its own, but a real reply may put one at the end of a sentence, in a list item or in backticks. So a marker counts
/// wherever it stands outside fenced code, and every one is taken out of the text that is shown. Fenced code is left
/// exactly as it is: the page shows it and the host reads it from the same reply.
enum WorksheetAIMarkers {
    private static let marker = try! NSRegularExpression(
        pattern: #"[ \t]*(?:`\[\[method:([A-Za-z0-9_]+)\]\]`|\[\[method:([A-Za-z0-9_]+)\]\])"#)
    private static let fence = try! NSRegularExpression(
        pattern: #"^[ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*(`{3,}|~{3,})(.*)$"#)
    private static let emptyItem = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d{1,9}[.)])?[ \t]*$"#)

    /// The reply as it is shown, and the method IDs it suggests, in order, repeats included.
    static func read(_ reply: String) -> (text: String, ids: [String]) {
        var ids: [String] = [], shown: [String] = []
        var open: (character: Character, length: Int)?
        for line in reply.components(separatedBy: "\n") {
            let whole = NSRange(line.startIndex..., in: line)
            if let match = fence.firstMatch(in: line, range: whole), let run = Range(match.range(at: 1), in: line),
               let rest = Range(match.range(at: 2), in: line), let character = line[run].first {
                if let current = open {
                    if character == current.character, line[run].count >= current.length,
                       line[rest].trimmingCharacters(in: .whitespaces).isEmpty { open = nil }
                } else if !(character == "`" && line[rest].contains("`")) {
                    open = (character, line[run].count)
                }
                shown.append(line)
                continue
            }
            let matches = open == nil ? marker.matches(in: line, range: whole) : []
            guard !matches.isEmpty else { shown.append(line); continue }
            for match in matches {
                let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                if let range = Range(group, in: line) { ids.append(String(line[range])) }
            }
            let stripped = marker.stringByReplacingMatches(in: line, range: whole, withTemplate: "")
            // A line that held nothing but markers, or a list item of them, is shown as an empty line.
            let empty = emptyItem.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil
            shown.append(empty ? "" : stripped)
        }
        return (shown.joined(separator: "\n"), ids)
    }
}
