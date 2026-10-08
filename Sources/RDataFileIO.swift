import Foundation
import Darwin

// R data files (.rds, .RData) through base R (Content/R/data-files.R). Tables cross between
// R and the grid as typed columnar snapshots on the grid side and, on R's side, as an exchange
// folder of one file per column: percent-escaped text lines, raw flag bytes and
// little-endian doubles, which R reads and writes in bulk. Nothing is serialised per cell.
enum RDataFileIO {
    static let kinds: [String: UInt8] = ["blank": 0, "number": 1, "text": 2, "datetime": 3, "timespan": 4, "boolean": 5, "error": 6]
    // Reads an R data file into a workbook description whose sheets name snapshot files in
    // `snapshots` (one per table) instead of listing cells.
    static func read(_ url: URL, script: URL, snapshots: URL) throws -> [String: Any] {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        try run(script, arguments: ["read", url.path, folder.path], folder: folder)
        guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any],
              let tables = manifest["tables"] as? [[String: Any]] else { throw error("R returned an invalid table.") }
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let id = UUID().uuidString
        var sheets: [[String: Any]] = []
        var written: [URL] = []
        do {
            for (t, table) in tables.enumerated() {
                guard let name = table["name"] as? String, let rows = table["rows"] as? Int, let columns = table["columns"] as? [[String: Any]] else { throw error("R returned an invalid table.") }
                var sheet = SnapshotSheet(name: name, columns: [])
                for (c, column) in columns.enumerated() {
                    let type = column["type"] as? String ?? "character"
                    let base = folder.appendingPathComponent("col-\(t)-\(c)")
                    let kinds = try bytes(base.appendingPathExtension("kinds"), count: rows)
                    let nums = (type == "double" || type == "integer") ? try doubles(base.appendingPathExtension("nums"), count: rows) : nil
                    let text = try lines(base.appendingPathExtension("txt"), count: rows)
                    let missing = (type == "character" || type == "factor") ? try bytes(base.appendingPathExtension("missing"), count: rows) : nil
                    let rawPath = base.appendingPathExtension("raw")
                    let raw = FileManager.default.fileExists(atPath: rawPath.path) ? try doubles(rawPath, count: rows) : nil
                    var record = SnapshotColumn(col: c)
                    record.rows.reserveCapacity(rows + 1); record.kinds.reserveCapacity(rows + 1); record.nums.reserveCapacity(rows + 1)
                    record.rows.append(0); record.kinds.append(2); record.nums.append(.nan); record.texts[0] = column["name"] as? String ?? "Column \(c + 1)"
                    for i in 0..<rows {
                        let kind = kinds[i]
                        let ordinal = record.rows.count
                        record.rows.append(UInt32(i + 1)); record.kinds.append(kind)
                        if kind == 1, let nums { record.nums.append(nums[i]) } else { record.nums.append(.nan); if kind != 0 && !text[i].isEmpty { record.texts[ordinal] = text[i] } }
                        var extra: [String] = []
                        if let missing, missing[i] != 0 { extra.append("\"rMissing\":true") }
                        if let raw, !raw[i].isNaN { extra.append("\"rRaw\":\"\(String(format: "%.17g", raw[i]))\"") }
                        if !extra.isEmpty { record.extras[ordinal] = "{" + extra.joined(separator: ",") + "}" }
                    }
                    sheet.columns.append(record)
                }
                let file = snapshots.appendingPathComponent("\(id)-\(t).sdcol")
                try Snapshot.encode([sheet]).write(to: file); written.append(file)
                var rowNames: [String] = []
                if table["rowNames"] as? Bool == true { rowNames = try lines(folder.appendingPathComponent("rows-\(t).txt"), count: rows) }
                sheets.append(["name": name, "hidden": false, "headerRow": true, "rows": rows + 1, "csvRows": rows + 1, "columns": max(1, columns.count), "cells": [], "snapshot": file.path,
                               "rColumns": columns.map { ["type": $0["type"] ?? "character", "levels": $0["levels"] ?? [], "naLevel": $0["naLevel"] ?? false, "ordered": $0["ordered"] ?? false, "tzone": $0["tzone"] ?? ""] },
                               "rRowNames": rowNames, "rRowNamesType": table["rowNamesType"] ?? "character", "rObjectName": table["object"] ?? name, "rObjectType": table["shape"] ?? "data.frame"])
            }
        } catch { for file in written { try? FileManager.default.removeItem(at: file) }; throw error }
        return ["name": manifest["name"] ?? url.lastPathComponent, "formulaCount": 0, "sheets": sheets, "warnings": manifest["warnings"] ?? []]
    }

    // Writes the grid's snapshot (one sheet per table; extras carry the original R `rMissing`
    // and `rRaw` markers) with the table manifest the grid built (name, shape, row names and
    // column name, type, levels, ordered, tzone) to an .rds or .RData file.
    static func write(snapshot: URL, tables: [[String: Any]], to url: URL, format: String, script: URL) throws {
        guard !tables.isEmpty else { throw error("There are no tables to save.") }
        let sheets = try Snapshot.decode(try Data(contentsOf: snapshot))
        guard sheets.count == tables.count else { throw error("The R tables do not match the worksheet snapshot.") }
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = [["table", "object", "shape", "rows", "column", "type", "ordered", "tzone", "naLevel", "rowNamesType"]]
        var objectNames = Set<String>()
        for (t, table) in tables.enumerated() {
            let name = table["name"] as? String ?? "Data"
            guard objectNames.insert(name).inserted else { throw error("Give each worksheet a different name before saving all tables to RData.") }
            guard let columns = table["columns"] as? [[String: Any]], !columns.isEmpty, let rows = table["rows"] as? Int else { throw error("Every R table needs at least one column.") }
            let records = Dictionary(uniqueKeysWithValues: sheets[t].columns.map { ($0.col, $0) })
            // Column names travel as escaped lines (a CSV field would turn a carriage return into a line feed).
            try writeLines(columns.enumerated().map { $1["name"] as? String ?? "Column \($0 + 1)" }, to: folder.appendingPathComponent("names-\(t).txt"), where: "column names of \(name)")
            for (c, column) in columns.enumerated() {
                let type = column["type"] as? String ?? "character"
                manifest.append([String(t), name, table["shape"] as? String ?? "data.frame", String(rows), String(c), type, column["ordered"] as? Bool == true ? "true" : "false", column["tzone"] as? String ?? "UTC", column["naLevel"] as? Bool == true ? "true" : "false", table["rowNamesType"] as? String ?? "character"])
                let record = records[c] ?? SnapshotColumn(col: c)
                var text = [String](repeating: "", count: rows), raw = [String](repeating: "", count: rows)
                var missing = [UInt8](repeating: 0, count: rows), nums = [Double](repeating: .nan, count: rows)
                for (i, row) in record.rows.enumerated() {
                    let r = Int(row); guard r < rows else { throw error("The worksheet snapshot has a row beyond the table.") }
                    if record.kinds[i] == 1 && !record.nums[i].isNaN { nums[r] = record.nums[i]; text[r] = Snapshot.jsNumber(record.nums[i]) }
                    else { text[r] = record.texts[i] ?? "" }
                    if let extra = record.extras[i], let object = try? JSONSerialization.jsonObject(with: Data(extra.utf8)) as? [String: Any] {
                        if object["rMissing"] as? Bool == true { missing[r] = 1 }
                        if let value = object["rRaw"] as? String { raw[r] = value }
                    }
                }
                if type != "character" && type != "factor" { for r in 0..<rows where text[r].isEmpty { missing[r] = 1 } }
                let base = folder.appendingPathComponent("col-\(t)-\(c)")
                let place = "\(name) / \(column["name"] as? String ?? "column \(c + 1)")"
                try writeLines(text, to: base.appendingPathExtension("txt"), where: place)
                try writeLines(raw, to: base.appendingPathExtension("raw"), where: place)
                try Data(missing).write(to: base.appendingPathExtension("missing"))
                try writeDoubles(nums, to: base.appendingPathExtension("nums"))
                try writeLines(column["levels"] as? [String] ?? [], to: folder.appendingPathComponent("levels-\(t)-\(c).txt"), where: "levels of \(place)")
            }
            try writeLines(table["rowNames"] as? [String] ?? [], to: folder.appendingPathComponent("rows-\(t).txt"), where: "row names of \(name)")
        }
        try csv(manifest, to: folder.appendingPathComponent("manifest.csv"))
        let output = url.deletingLastPathComponent().appendingPathComponent(".statsdirect-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: output) }
        try run(script, arguments: ["write", folder.path, output.path, format], folder: folder)
        // The temporary file is beside the destination, so replacement is atomic.
        guard rename(output.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    // Text lines: one per value, with %, newline and carriage return percent-encoded and a
    // leading byte-order mark written as %EF%BB%BF (R's readLines would drop it from the first
    // line of a file). Escaping and unescaping work on bytes, so combining marks or prepend
    // characters next to an escape never change the result. R cannot hold a NUL character.
    static func escape(_ text: String) throws -> [UInt8] {
        let utf8 = Array(text.utf8)
        guard utf8.contains(where: { $0 == 0x25 || $0 == 0x0A || $0 == 0x0D || $0 == 0 }) || utf8.starts(with: [0xEF, 0xBB, 0xBF]) else { return utf8 }
        var out: [UInt8] = []; out.reserveCapacity(utf8.count + 8)
        var i = 0
        if utf8.starts(with: [0xEF, 0xBB, 0xBF]) { out.append(contentsOf: Array("%EF%BB%BF".utf8)); i = 3 }
        while i < utf8.count {
            switch utf8[i] {
            case 0x25: out.append(contentsOf: Array("%25".utf8))
            case 0x0A: out.append(contentsOf: Array("%0A".utf8))
            case 0x0D: out.append(contentsOf: Array("%0D".utf8))
            case 0: throw error("contains a NUL character, which R cannot store")
            default: out.append(utf8[i])
            }
            i += 1
        }
        return out
    }
    static func unescape(_ bytes: Data.SubSequence) -> String {
        guard bytes.contains(0x25) else { return String(decoding: bytes, as: UTF8.self) }
        let raw = Array(bytes); var out: [UInt8] = []; out.reserveCapacity(raw.count)
        var i = 0
        func hex(_ a: UInt8, _ b: UInt8) -> UInt8? {
            func digit(_ c: UInt8) -> UInt8? { switch c { case 0x30...0x39: return c - 0x30; case 0x41...0x46: return c - 0x41 + 10; case 0x61...0x66: return c - 0x61 + 10; default: return nil } }
            guard let h = digit(a), let l = digit(b) else { return nil }; return h << 4 | l
        }
        while i < raw.count {
            if raw[i] == 0x25, i + 2 < raw.count, let value = hex(raw[i + 1], raw[i + 2]), value == 0x25 || value == 0x0A || value == 0x0D || value == 0xEF || value == 0xBB || value == 0xBF {
                out.append(value); i += 3
            } else { out.append(raw[i]); i += 1 }
        }
        return String(decoding: out, as: UTF8.self)
    }
    static func writeLines(_ values: [String], to url: URL, where place: String = "a cell") throws {
        var data = Data(); data.reserveCapacity(values.count * 8)
        for (row, value) in values.enumerated() {
            do { data.append(contentsOf: try escape(value)) } catch { throw self.error("Row \(row + 1) of \(place) \(error.localizedDescription).") }
            data.append(0x0A)
        }
        try data.write(to: url)
    }
    static func lines(_ url: URL, count: Int) throws -> [String] {
        let data = try Data(contentsOf: url)
        var result: [String] = []; result.reserveCapacity(count)
        var start = data.startIndex
        while let end = data[start...].firstIndex(of: 0x0A) {
            result.append(unescape(data[start..<end])); start = data.index(after: end)
        }
        if start < data.endIndex { result.append(unescape(data[start...])) }
        guard result.count == count else { throw error("R returned \(result.count) values where \(count) were expected.") }
        return result
    }
    static func bytes(_ url: URL, count: Int) throws -> [UInt8] {
        let data = try Data(contentsOf: url)
        guard data.count == count else { throw error("R returned \(data.count) flags where \(count) were expected.") }
        return [UInt8](data)
    }
    static func doubles(_ url: URL, count: Int) throws -> [Double] {
        let data = try Data(contentsOf: url)
        guard data.count == count * 8 else { throw error("R returned \(data.count / 8) numbers where \(count) were expected.") }
        return data.withUnsafeBytes { raw in (0..<count).map { Double(bitPattern: raw.loadUnaligned(fromByteOffset: 8 * $0, as: UInt64.self).littleEndian) } }
    }
    static func writeDoubles(_ values: [Double], to url: URL) throws {
        var data = Data(count: values.count * 8)
        data.withUnsafeMutableBytes { raw in for (i, v) in values.enumerated() { raw.storeBytes(of: v.bitPattern.littleEndian, toByteOffset: 8 * i, as: UInt64.self) } }
        try data.write(to: url)
    }
    static func csv(_ rows: [[String]], to url: URL) throws {
        let text = rows.map { row in row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    private static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-R-data-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private static func run(_ script: URL, arguments: [String], folder: URL) throws {
        guard let executable = RRuntime.executable() else { throw error("R is not available. Choose R → Install R to open and save R data files.") }
        let log = folder.appendingPathComponent("R-output.txt")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["--vanilla", script.path] + arguments
        task.standardOutput = handle; task.standardError = handle; task.currentDirectoryURL = folder
        try task.run()
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: timeout)
        task.waitUntilExit(); timeout.cancel()
        guard task.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw error(details.isEmpty ? "R data-file conversion stopped or exceeded ten minutes." : String(details.prefix(4000)))
        }
    }
    private static func error(_ message: String) -> NSError { NSError(domain: "StatsDirect.RData", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
