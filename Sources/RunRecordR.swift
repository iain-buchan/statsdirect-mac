import Cocoa
import WebKit

/// A recipe of the shared manifest (Content/R/analysis-recipes.json): the R file that reproduces an analysis and what it says of itself.
struct RRecipe {
    var file: String
    var detail: String
}

// The record of a run is the engine's (RunRecord, shared with Windows): the report keeps its JSON text with each result, and the
// R script is written from it on demand by the engine's RScriptWriter (the statsdirect_r_script entry). This file supplies what the
// engine cannot know: the record's friendly title for the entry, the manifest of recipes for results whose recipe flag the engine
// did not give (reports reopened from a file), the validation of records read back from files, and the values of the worksheet
// columns a record points to when it does not hold them: from the grid when the workbook is open, else from the file read through
// the engine, else the reason they could not be read.
enum RunRecordR {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static let maxColumn = 16384, maxRow = 1_048_576
    /// The most cells one frame, and a record's frames together, may point to: a record read from a file could otherwise ask the open
    /// grid or the engine's reader for whole worksheets many times over (500 frames of 500 columns over every row) on one click.
    static let maxFrameCells = 2_000_000, maxRecordCells = 5_000_000
    /// The record's `title`, the operation's friendly name, which titles the entry as on Windows.
    static func title(of record: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any], let title = object["title"] as? String, !title.isEmpty else { return nil }
        return title
    }
    /// The manifest of recipes in the program's R folder, operation name to recipe.
    static func manifest(resources: URL) -> [String: RRecipe] {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent("R/analysis-recipes.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var result: [String: RRecipe] = [:]
        // Shared entries may also carry nested parentFiles routing. The engine
        // resolves that routing from the saved record when writing the script.
        for (operation, entry) in object { if let file = entry["file"] as? String { result[operation] = RRecipe(file: file, detail: entry["detail"] as? String ?? "") } }
        return result
    }
    /// A whole number, as the record's version, columns and rows are (a JSON boolean is not one).
    static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e15 else { return nil }
        return n.intValue
    }

    // MARK: The frames a record points to

    /// A column the record points to: its 1-based worksheet column and rows, the title row counted in when hasTitle (as Windows records it).
    struct Pointer {
        var title: String
        var column: Int
        var rows: ClosedRange<Int>
        var hasTitle: Bool
        /// The first row of data.
        var firstRow: Int { hasTitle ? rows.lowerBound + 1 : rows.lowerBound }
        var count: Int { max(0, rows.upperBound - firstRow + 1) }
    }
    /// A frame read from a worksheet whose values the record does not hold, so they are read again by its pointers.
    struct Frame {
        var name: String
        var file: String
        var path: String
        var sheet: String
        var columns: [Pointer]
        /// A column beyond the sheet's width read as blank cells rather than refused: for the band read either side of a column's
        /// recorded place when the column is looked for along the sheet.
        var blankBeyond = false
    }
    /// A frame to read, or why it cannot be, by input name.
    struct Request {
        var name: String
        var frame: Frame?
        var unavailable: String?
    }
    /// The frame inputs whose values must be read (kind "frame" and not among the record's `data`, under the input's own name or,
    /// for a frame asked once per pass of a loop, the key its `held` names), in prompt order; a name asked in several passes gives
    /// several requests of that name, in order, and the engine takes the frames supplied in that order. A pointer the
    /// record does not describe within the worksheet's bounds, or a frame pointing at more cells than can be read (its distinct
    /// columns over the rows it spans, alone or with the frames before it), makes its frame unavailable with the reason, so nothing
    /// is read by it; the script still opens, its Data line saying why.
    static func requests(in record: [String: Any]) -> [Request] {
        let held = record["data"] as? [String: Any] ?? [:]
        var requests: [Request] = []
        var cells = 0
        for input in record["inputs"] as? [[String: Any]] ?? [] {
            guard input["kind"] as? String == "frame", let name = input["name"] as? String, held[input["held"] as? String ?? name] == nil else { continue }
            let file = input["file"] as? String ?? ""
            let path = (input["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? file
            var columns: [Pointer] = []
            var reason: String?
            for column in input["columns"] as? [[String: Any]] ?? [] {
                let title = column["title"] as? String ?? ""
                guard let index = integer(column["column"]), (1...maxColumn).contains(index), let rows = column["rows"] as? [Any], rows.count == 2,
                      let first = integer(rows[0]), let last = integer(rows[1]), first >= 1, first <= last, last <= maxRow else {
                    reason = "the record does not say where \(title.isEmpty ? "a column" : title) is"; break
                }
                columns.append(Pointer(title: title, column: index, rows: first...last, hasTitle: column["hasTitle"] as? Bool ?? false))
            }
            if reason == nil, columns.isEmpty { reason = "the record names no columns" }
            if reason == nil {
                let span = (columns.map(\.rows.upperBound).max() ?? 1) - (columns.map(\.firstRow).min() ?? 1) + 1
                let asked = Set(columns.map(\.column)).count * max(span, 0)
                cells += asked
                if asked > maxFrameCells || cells > maxRecordCells { reason = "the record points at more cells than can be read" }
            }
            let frame = reason == nil ? Frame(name: name, file: file, path: path, sheet: input["sheet"] as? String ?? "", columns: columns) : nil
            requests.append(Request(name: name, frame: frame, unavailable: reason))
        }
        return requests
    }

    // MARK: Reading the open grid

    /// A cell's text as the grid gives it (a number as the grid shows it).
    static func text(_ cell: Any) -> String {
        if let s = cell as? String { return s }
        if let n = cell as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return Snapshot.jsNumber(n.doubleValue) }
        return ""
    }
    /// The texts and kinds of a frame's columns from the grid showing its workbook, by sheet name (the only key the record holds),
    /// through the grid's own column reader (window.statsDirectGrid.columnValues), so the cells come back as the form read them.
    @MainActor static func read(_ frame: Frame, fromGrid document: Document) async throws -> [[String: Any]] {
        func call(_ script: String, _ arguments: [String: Any]) async throws -> [String: Any] {
            try await withCheckedThrowingContinuation { continuation in
                document.web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                    switch result {
                    case .failure(let error): continuation.resume(throwing: Failure(message: ((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription))
                    case .success(let value): continuation.resume(returning: value as? [String: Any] ?? [:])
                    }
                }
            }
        }
        let info = try await call("return window.statsDirectGrid.tutorInfo()", [:])
        guard let sheets = info["sheets"] as? [[String: Any]], let sheet = sheets.first(where: { $0["name"] as? String == frame.sheet }), let index = sheet["index"] as? Int else {
            throw Failure(message: "the worksheet \(frame.sheet) is no longer in \(document.workbookName)")
        }
        let distinct = Array(Set(frame.columns.map { $0.column - 1 })).sorted()
        let last = frame.columns.map(\.rows.upperBound).max() ?? 1
        let first = min(frame.columns.map(\.firstRow).min() ?? 1, last)
        let result = try await call("return window.statsDirectGrid.columnValues(request)", ["request": ["sheet": index, "sheetName": frame.sheet, "columns": distinct, "first": first, "last": last, "blankBeyond": frame.blankBeyond]])
        guard let read = result["columns"] as? [[String: Any]], read.count == distinct.count else { throw Failure(message: "the worksheet did not return the selected columns") }
        if (result["errors"] as? Int ?? 0) > 0 { throw Failure(message: "the selection contains Excel errors") }
        if (result["uncached"] as? Int ?? 0) > 0 { throw Failure(message: "the selection holds formula cells whose results are not saved") }
        return frame.columns.map { pointer in
            let column = read[distinct.firstIndex(of: pointer.column - 1) ?? 0]
            let values = column["values"] as? [Any] ?? [], kinds = column["kinds"] as? [Any] ?? []
            let start = pointer.firstRow - first
            let span = start..<start + pointer.count
            return ["title": pointer.title, "values": span.map { k in k < values.count ? text(values[k]) : "" }, "kinds": span.map { k in k < kinds.count ? (kinds[k] as? String ?? "blank") : "blank" }]
        }
    }

    // MARK: Records read back from files

    /// A record read from a file, kept as the JSON text it was saved with (the engine reads it exactly as it was written, its
    /// properties in their order) when it is one Windows or this program could have written: an object of version 1 naming an
    /// operation, its frame inputs pointing within the worksheet's bounds, its run time (and its source's modification time) an ISO
    /// 8601 timestamp and at most the HTML import envelope (30 MB). Structural text stays bounded to 4,096 characters;
    /// complete cell-value arrays may hold longer text. A control character in a title or name is no bar:
    /// the engine's writer makes each one a space in the script's comment lines and escapes it in its string literals (U+0000, which
    /// R cannot hold in a string, becomes a space there too).
    static func validated(_ raw: String) -> String? {
        guard raw.utf8.count <= 30_000_000, let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
        guard integer(object["version"]) == 1, let operation = object["operation"] as? String, isOperationName(operation) else { return nil }
        if let inputs = object["inputs"], !(inputs is NSNull) {
            let limit = object["notebookImport"] is [String: Any] ? 20_000 : 500
            guard let list = inputs as? [Any], list.count <= limit else { return nil }
            for item in list {
                guard let input = item as? [String: Any] else { return nil }
                guard input["kind"] as? String == "frame" else { continue }
                let held = completeHeldFrame(input, record: object)
                if let columns = input["columns"], !(columns is NSNull) {
                    guard let list = columns as? [Any], list.count <= (held ? maxColumn : 500) else { return nil }
                    for item in list {
                        guard let column = item as? [String: Any] else { return nil }
                        if let c = column["column"], !(c is NSNull) { guard let n = integer(c), (1...maxColumn).contains(n) else { return nil } }
                        if let r = column["rows"], !(r is NSNull) {
                            guard let rows = r as? [Any], rows.count == 2, let a = integer(rows[0]), let b = integer(rows[1]), a >= 1, a <= maxRow,
                                  (a <= b && b <= maxRow) || (held && b < 0) else { return nil }
                        }
                        if let h = column["hash"], !(h is NSNull) {
                            guard let hash = h as? String, hash.count == 16, hash.unicodeScalars.allSatisfy({ ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x66) }) else { return nil }
                        }
                    }
                }
            }
        }
        guard textsWithinBounds(object, depth: 0) else { return nil }
        guard let run = object["run"] as? String, isTimestamp(run) else { return nil }
        if let source = object["source"] as? [String: Any], let modified = source["modified"], !(modified is NSNull) {
            guard let text = modified as? String, isTimestamp(text) else { return nil }
        }
        return raw
    }
    /// A reason this program gives for a frame it could not read, with any control character made a space, as the writer makes
    /// those of the record's own texts in its comment lines (a workbook's name on disk may hold anything but a slash).
    static func plain(_ reason: String) -> String {
        String(String.UnicodeScalarView(reason.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : $0 }))
    }
    /// An ISO 8601 timestamp as the record's `run` and `source.modified` are written (C# "o": 2026-10-10T22:30:15.1234567+01:00; the
    /// fraction and the offset may be absent), which the writer puts in the script's head as a date, never as the text itself.
    static func isTimestamp(_ s: String) -> Bool {
        s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})?$", options: .regularExpression) != nil
    }
    static func isOperationName(_ s: String) -> Bool {
        s.count <= 100 && s.unicodeScalars.allSatisfy { ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) || $0.value == 0x5F }
    }
    private static func completeHeldFrame(_ input: [String: Any], record: [String: Any]) -> Bool {
        guard let name = input["held"] as? String ?? input["name"] as? String,
              let data = record["data"] as? [String: Any], let held = data[name] as? [String: Any],
              let columns = input["columns"] as? [[String: Any]], !columns.isEmpty, held.count == columns.count else { return false }
        var used = Set<String>()
        for column in columns {
            let title = column["title"] as? String ?? ""
            var key = title, suffix = 2
            while !used.insert(key).inserted { key = title + "_\(suffix)"; suffix += 1 }
            guard held[key] is [Any] else { return false }
        }
        return true
    }
    private static func textsWithinBounds(_ value: Any, depth: Int, cellValues: Bool = false) -> Bool {
        guard depth <= 32 else { return false }
        if let s = value as? String { return cellValues || s.count <= 4096 }
        if let items = value as? [Any] { return items.allSatisfy { textsWithinBounds($0, depth: depth + 1, cellValues: cellValues) } }
        if let pairs = value as? [String: Any] { return pairs.allSatisfy {
            $0.key.count <= 4096 && textsWithinBounds($0.value, depth: depth + 1,
                cellValues: cellValues || ($0.key == "data" && $0.value is [String: Any]) || ($0.key == "values" && $0.value is [Any]))
        } }
        return true
    }

    /// A result of a saved report's metadata block (`statsdirect-report-data`, written by this program or by Windows).
    struct SavedEntry {
        var id: String
        var title: String
        var operation: String
        var helpPath: String?
        var html: String
        var record: String?
    }
    /// The results a saved report's block holds, with their records as the raw JSON text (validated), and how many records could
    /// not be read; nil when the block is not a version 1 block of at most 1,000 entries.
    static func savedEntries(block: String) -> (entries: [SavedEntry], unreadableRecords: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any], integer(object["version"]) == 1,
              let list = object["entries"] as? [Any], list.count <= 1000 else { return nil }
        let raw = recordTexts(inBlock: block) ?? []
        var entries: [SavedEntry] = []
        var unreadable = 0
        for (i, item) in list.enumerated() {
            guard let item = item as? [String: Any] else { return nil }
            let id = (item["id"] as? String).flatMap { $0.count <= 100 && !$0.isEmpty ? $0 : nil } ?? UUID().uuidString
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(500)) } ?? "Report"
            let operation = (item["operation"] as? String).flatMap { isOperationName($0) ? $0 : nil } ?? ""
            let helpPath = (item["helpPath"] as? String).flatMap { $0.hasPrefix("Help/") && !$0.contains("..") && $0.count <= 500 ? $0 : nil }
            var record: String?
            if let given = item["record"], !(given is NSNull) {
                if i < raw.count, let text = raw[i], let valid = validated(text) { record = valid } else { unreadable += 1 }
            }
            entries.append(SavedEntry(id: id, title: title, operation: operation, helpPath: helpPath, html: item["html"] as? String ?? "", record: record))
        }
        return (entries, unreadable)
    }
    /// The raw text of each entry's `record` in a block, `entries[i].record`, found by walking the block's structure without
    /// rebuilding it (JSONSerialization would reorder the record's properties); nil for an entry without an object there.
    static func recordTexts(inBlock block: String) -> [String?]? {
        let bytes = Array(block.utf8)
        var p = 0
        let entriesKey = Array("\"entries\"".utf8), recordKey = Array("\"record\"".utf8)
        func skipWhitespace() { while p < bytes.count, bytes[p] == 0x20 || bytes[p] == 0x09 || bytes[p] == 0x0A || bytes[p] == 0x0D { p += 1 } }
        func skipString() -> Bool {
            guard p < bytes.count, bytes[p] == 0x22 else { return false }
            p += 1
            while p < bytes.count {
                if bytes[p] == 0x5C { p += 2; continue }
                if bytes[p] == 0x22 { p += 1; return true }
                p += 1
            }
            return false
        }
        /// Walks an object's members, handing each key's bytes and the position of its value to `member`, which consumes the value.
        func object(_ member: ([UInt8]) -> Bool) -> Bool {
            skipWhitespace()
            guard p < bytes.count, bytes[p] == 0x7B else { return false }
            p += 1; skipWhitespace()
            if p < bytes.count, bytes[p] == 0x7D { p += 1; return true }
            while true {
                skipWhitespace()
                let keyStart = p
                guard skipString() else { return false }
                let key = Array(bytes[keyStart..<p])
                skipWhitespace()
                guard p < bytes.count, bytes[p] == 0x3A else { return false }
                p += 1
                guard member(key) else { return false }
                skipWhitespace()
                guard p < bytes.count else { return false }
                if bytes[p] == 0x2C { p += 1; continue }
                if bytes[p] == 0x7D { p += 1; return true }
                return false
            }
        }
        func array(_ element: () -> Bool) -> Bool {
            skipWhitespace()
            guard p < bytes.count, bytes[p] == 0x5B else { return false }
            p += 1; skipWhitespace()
            if p < bytes.count, bytes[p] == 0x5D { p += 1; return true }
            while true {
                guard element() else { return false }
                skipWhitespace()
                guard p < bytes.count else { return false }
                if bytes[p] == 0x2C { p += 1; continue }
                if bytes[p] == 0x5D { p += 1; return true }
                return false
            }
        }
        func skipValue() -> Bool {
            skipWhitespace()
            guard p < bytes.count else { return false }
            switch bytes[p] {
            case 0x22: return skipString()
            case 0x7B: return object { _ in skipValue() }
            case 0x5B: return array { skipValue() }
            default:
                let start = p
                while p < bytes.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[p]) { p += 1 }
                return p > start
            }
        }
        var texts: [String?] = []
        let ok = object { key in
            guard key == entriesKey else { return skipValue() }
            return array {
                var text: String?
                skipWhitespace()
                guard p < bytes.count, bytes[p] == 0x7B else { return skipValue() }
                let ok = object { key in
                    guard key == recordKey else { return skipValue() }
                    skipWhitespace()
                    let start = p
                    guard skipValue() else { return false }
                    if bytes[start] == 0x7B { text = String(decoding: bytes[start..<p], as: UTF8.self) }
                    return true
                }
                texts.append(text)
                return ok
            }
        }
        return ok ? texts : nil
    }
}

/// Reads the columns a record points to from a workbook file through the engine (statsdirect_workbook "open": one typed columnar
/// snapshot per sheet, decoded with Snapshot), for a workbook that is not open in the program. The engine's private copy and the
/// snapshot files are removed by `close`.
final class EngineWorkbookReader {
    typealias Invoke = ([String: Any]) async throws -> [String: Any]
    /// The snapshot's cell kinds by code, as the grid names them.
    static let kinds = ["blank", "number", "text", "datetime", "timespan", "boolean", "error"]
    let path: String
    let snapshotDirectory: URL
    private let invoke: Invoke
    private var id: String?
    private var sheets: [(name: String, snapshot: String?)] = []
    private var decoded: [String: [SnapshotSheet]] = [:]
    var file: String { URL(fileURLWithPath: path).lastPathComponent }

    init(path: String, snapshotDirectory: URL, invoke: @escaping Invoke) {
        self.path = path; self.snapshotDirectory = snapshotDirectory; self.invoke = invoke
    }
    func open() async throws {
        do {
            let result = try await invoke(["action": "open", "path": path, "snapshot": snapshotDirectory.path])
            id = result["id"] as? String
            sheets = (result["sheets"] as? [[String: Any]] ?? []).map { ($0["name"] as? String ?? "", $0["snapshot"] as? String) }
        } catch {
            if (error as NSError).userInfo["workbookErrorCode"] as? String == "workbookPassword" { throw RunRecordR.Failure(message: "\(file) needs its password to open") }
            throw error
        }
    }
    /// The texts and kinds of the frame's columns, row by row within each pointer's rows: a number as the grid shows it, a blank
    /// cell as nothing, any other kind as its text. A formula cell without a saved result (the file was saved without recalculating,
    /// as this program's own streaming save leaves formulas) is refused as the grid refuses to analyse one (`checkColumnData`), rather
    /// than read as a blank that would hash differently and have the script say the column changed.
    func read(_ frame: RunRecordR.Frame) async throws -> [[String: Any]] {
        guard let sheet = sheets.first(where: { $0.name == frame.sheet }) else { throw RunRecordR.Failure(message: "the worksheet \(frame.sheet) is no longer in \(file)") }
        guard let snapshot = sheet.snapshot else { throw RunRecordR.Failure(message: "the worksheet \(frame.sheet) of \(file) has no cells") }
        let decodedSheets: [SnapshotSheet]
        if let cached = decoded[snapshot] { decodedSheets = cached }
        else {
            let file = URL(fileURLWithPath: snapshot)
            decodedSheets = try await Task.detached { try Snapshot.decode(Data(contentsOf: file)) }.value
            decoded[snapshot] = decodedSheets
        }
        guard let data = decodedSheets.first else { throw RunRecordR.Failure(message: "the worksheet \(frame.sheet) of \(file) could not be decoded") }
        return try frame.columns.map { pointer in
            var texts: [String] = [], kinds: [String] = []
            texts.reserveCapacity(pointer.count); kinds.reserveCapacity(pointer.count)
            if let cells = data.columns.first(where: { $0.col == pointer.column - 1 }) {
                var ordinal: [UInt32: Int] = [:]
                for (i, row) in cells.rows.enumerated() { ordinal[row] = i }
                for row in pointer.firstRow..<pointer.firstRow + pointer.count {
                    guard let i = ordinal[UInt32(row - 1)] else { texts.append(""); kinds.append("blank"); continue }
                    let kind = Int(cells.kinds[i])
                    if kind == 0, cells.formulas[i] != nil { throw RunRecordR.Failure(message: "the workbook holds formula cells whose results are not saved") }
                    kinds.append(kind < Self.kinds.count ? Self.kinds[kind] : "text")
                    if kind == 1, cells.nums[i].isFinite { texts.append(Snapshot.jsNumber(cells.nums[i])) }
                    else { texts.append(kind == 0 ? "" : cells.texts[i] ?? "") }
                }
            } else {
                texts = Array(repeating: "", count: pointer.count); kinds = Array(repeating: "blank", count: pointer.count)
            }
            return ["title": pointer.title, "values": texts, "kinds": kinds]
        }
    }
    /// Closes the engine's copy and removes the snapshot files it wrote; returns a note for any file that was not removed.
    func close() async -> [String] {
        var notes: [String] = []
        if let id { _ = try? await invoke(["action": "close", "id": id]) }
        let store = snapshotDirectory.standardizedFileURL.path
        for sheet in sheets {
            guard let snapshot = sheet.snapshot else { continue }
            let url = URL(fileURLWithPath: snapshot).standardizedFileURL
            if url.path.hasPrefix(store + "/"), url.pathExtension == "sdcol" { try? FileManager.default.removeItem(at: url) }
            else { notes.append("A worksheet snapshot was left at " + url.path) }
        }
        sheets = []; id = nil; decoded = [:]
        return notes
    }
}
