import Cocoa

struct LegacyReportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct LegacyPicture {
    let marker: String
    let format: String
    let data: Data
    let width: Double
    let height: Double
    var payload: [String: Any] { ["marker": marker, "format": format, "data": data.base64EncodedString(), "width": width, "height": height] }
}

/// Parses RTF groups before AppKit reads the document. Metafiles are decoded separately;
/// hidden fields and embedded objects must not become visible text or active attachments.
struct LegacyReport {
    let html: String
    let pictures: [LegacyPicture]
    var tableRows: [[Int]] = []

    @MainActor static func read(_ data: Data) throws -> LegacyReport {
        var reader = RTFReader(data)
        let clean = try reader.read()
        let attributed = try NSAttributedString(data: clean, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let html = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue])
        return LegacyReport(html: String(decoding: html, as: UTF8.self), pictures: reader.pictures, tableRows: reader.tableRows)
    }
}

private struct RTFReader {
    let bytes: [UInt8]
    var index = 0
    var pictures: [LegacyPicture] = []
    var tableRows: [[Int]] = []
    var cellEdges: [Int] = []
    let prefix = "SDPICT" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    init(_ data: Data) { bytes = Array(data) }
    struct Control { let word: String; let number: Int?; let range: Range<Int>; let binary: Range<Int>? }
    func letter(_ c: UInt8) -> Bool { (65...90).contains(c) || (97...122).contains(c) }
    func digit(_ c: UInt8) -> Bool { (48...57).contains(c) }
    func whitespace(_ c: UInt8) -> Bool { [9, 10, 13, 32].contains(c) }
    mutating func control() throws -> Control {
        let start = index; index += 1
        guard index < bytes.count else { throw LegacyReportError("The RTF report ends inside a control sequence.") }
        if !letter(bytes[index]) {
            let symbol = bytes[index]; index += 1
            if symbol == 39 {
                guard index + 2 <= bytes.count, bytes[index..<index+2].allSatisfy({ hex($0) != nil }) else { throw LegacyReportError("The RTF report contains an invalid character escape.") }
                index += 2
            }
            return Control(word: String(UnicodeScalar(symbol)), number: nil, range: start..<index, binary: nil)
        }
        let nameStart = index
        while index < bytes.count && letter(bytes[index]) { index += 1 }
        let word = String(decoding: bytes[nameStart..<index], as: UTF8.self)
        let valueStart = index
        if index < bytes.count && bytes[index] == 45 { index += 1 }
        while index < bytes.count && digit(bytes[index]) { index += 1 }
        let number = valueStart == index ? nil : Int(String(decoding: bytes[valueStart..<index], as: UTF8.self))
        if index < bytes.count && bytes[index] == 32 { index += 1 }
        var binary: Range<Int>?
        if word == "bin" {
            guard let count = number, count >= 0, count <= bytes.count - index else { throw LegacyReportError("The RTF report contains truncated binary data.") }
            binary = index..<index+count; index += count
        }
        return Control(word: word, number: number, range: start..<index, binary: binary)
    }
    func hex(_ c: UInt8) -> UInt8? {
        if (48...57).contains(c) { return c - 48 }
        if (65...70).contains(c) { return c - 55 }
        if (97...102).contains(c) { return c - 87 }
        return nil
    }
    mutating func destination() throws -> String {
        let saved = index; defer { index = saved }
        index += 1
        while index < bytes.count && whitespace(bytes[index]) { index += 1 }
        guard index < bytes.count && bytes[index] == 92 else { return "" }
        var token = try control()
        if token.word == "*", index < bytes.count && bytes[index] == 92 { token = try control() }
        return token.word
    }
    mutating func skipGroup(_ depth: Int) throws {
        guard depth < 128, bytes[index] == 123 else { throw LegacyReportError("The RTF report has too many nested groups.") }
        index += 1
        while index < bytes.count {
            if bytes[index] == 125 { index += 1; return }
            if bytes[index] == 123 { try skipGroup(depth + 1) }
            else if bytes[index] == 92 { _ = try control() }
            else { index += 1 }
        }
        throw LegacyReportError("The RTF report is incomplete (an unclosed group).")
    }
    mutating func picture(_ depth: Int) throws -> [UInt8] {
        guard pictures.count < 200 else { throw LegacyReportError("This RTF report contains more than 200 pictures. Split it into smaller reports in the Windows application.") }
        index += 1
        var format = "unsupported", image: [UInt8] = [], high: UInt8?, width = 0.0, height = 0.0, malformed = false
        while index < bytes.count && bytes[index] != 125 {
            if bytes[index] == 123 { try skipGroup(depth + 1) }
            else if bytes[index] == 92 {
                let token = try control()
                switch token.word {
                case "emfblip": format = "emf"
                case "wmetafile": format = "wmf"
                case "pngblip": format = "png"
                case "jpegblip": format = "jpeg"
                case "picwgoal": width = Double(token.number ?? 0) / 15
                case "pichgoal": height = Double(token.number ?? 0) / 15
                case "bin": if let range = token.binary { image.append(contentsOf: bytes[range]) }
                default: break
                }
            } else {
                let c = bytes[index]; index += 1
                if let value = hex(c) {
                    if let first = high { image.append(first * 16 + value); high = nil } else { high = value }
                } else if !whitespace(c) { malformed = true }
            }
        }
        guard index < bytes.count else { throw LegacyReportError("The RTF report ends inside a picture.") }
        index += 1
        if high != nil || malformed { format = "unsupported" }
        let marker = prefix + "N" + String(pictures.count) + "END"
        pictures.append(LegacyPicture(marker: marker, format: format, data: Data(image), width: min(4096, max(0, width)), height: min(4096, max(0, height))))
        return Array(marker.utf8)
    }
    mutating func group(_ depth: Int, hidden inherited: Bool = false) throws -> [UInt8] {
        guard depth < 128 else { throw LegacyReportError("The RTF report has too many nested groups.") }
        let dest = try destination()
        if dest == "pict" { if inherited { try skipGroup(depth); return [] }; return try picture(depth) }
        if ["object", "objdata", "fldinst", "NeXTGraphic", "NeXTAttachment", "filetbl"].contains(dest) {
            try skipGroup(depth)
            return dest == "object" && !inherited ? Array("[Embedded object omitted]".utf8) : []
        }
        let wrapper = dest == "shppict" || dest == "nonshppict"
        index += 1
        var result: [UInt8] = [123], hidden = inherited, previousShape = false
        while index < bytes.count {
            let c = bytes[index]
            if c == 125 { index += 1; result.append(125); return result }
            if c == 123 {
                let child = try destination()
                if child == "nonshppict" && previousShape { try skipGroup(depth + 1) }
                else { result.append(contentsOf: try group(depth + 1, hidden: hidden)) }
                previousShape = child == "shppict"
            } else if c == 92 {
                let token = try control()
                // AppKit drops the physical cell boundaries, including spanning
                // headers. Keep the final definition for each row (Word can repeat
                // trowd before row) so the HTML importer can restore the column grid.
                if !hidden {
                    if token.word == "trowd" { cellEdges = [] }
                    else if token.word == "cellx", let edge = token.number { cellEdges.append(edge) }
                    else if token.word == "row" { tableRows.append(cellEdges); cellEdges = [] }
                }
                if token.word == "v" { hidden = token.number != 0 }
                else if token.word == "plain" { hidden = false; result.append(contentsOf: bytes[token.range]) }
                else if !(wrapper && ["*", "shppict", "nonshppict"].contains(token.word)) && !hidden { result.append(contentsOf: bytes[token.range]) }
            } else { index += 1; if !hidden { result.append(c) }; if !whitespace(c) { previousShape = false } }
        }
        throw LegacyReportError("The RTF report is incomplete (an unclosed group).")
    }
    mutating func read() throws -> Data {
        guard bytes.count <= 30_000_000 else { throw LegacyReportError("This RTF report is larger than 30 MB. Split it into smaller reports in the Windows application.") }
        while index < bytes.count && whitespace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == 123, try destination() == "rtf" else { throw LegacyReportError("This file is not an RTF report.") }
        let result = try group(0)
        guard bytes[index...].allSatisfy({ whitespace($0) || $0 == 0 }) else { throw LegacyReportError("The RTF report contains unexpected data after its final group.") }
        return Data(result)
    }
}
