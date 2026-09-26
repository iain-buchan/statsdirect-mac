import Foundation
import Darwin

enum RDataFileIO {
    static func read(_ url: URL, script: URL) throws -> [String: Any] {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("workbook.json")
        try run(script, arguments: ["read", url.path, output.path], folder: folder)
        guard let workbook = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any] else { throw error("R returned an invalid table.") }
        return workbook
    }
    static func write(_ tables: [[String: Any]], to url: URL, format: String, script: URL) throws {
        guard !tables.isEmpty else { throw error("There are no tables to save.") }
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = [["table", "object", "shape", "column", "name", "type", "ordered", "tzone"]]
        var objectNames = Set<String>()
        for (t, table) in tables.enumerated() {
            let name = table["name"] as? String ?? "Data"
            guard objectNames.insert(name).inserted else { throw error("Give each worksheet a different name before saving all tables to RData.") }
            guard let columns = table["columns"] as? [[String: Any]], !columns.isEmpty else { throw error("Every R table needs at least one column.") }
            for (c, column) in columns.enumerated() {
                manifest.append([String(t), name, table["shape"] as? String ?? "data.frame", String(c), column["name"] as? String ?? "Column \(c+1)", column["type"] as? String ?? "character", column["ordered"] as? Bool == true ? "true" : "false", column["tzone"] as? String ?? "UTC"])
                let values = column["values"] as? [[String: Any]] ?? []
                try csv([["text", "missing", "raw"]] + values.map { [$0["text"] as? String ?? "", $0["missing"] as? Bool == true ? "true" : "false", $0["raw"] as? String ?? ""] }, to: folder.appendingPathComponent("column-\(t)-\(c).csv"))
                try csv([["level"]] + (column["levels"] as? [String] ?? []).map { [$0] }, to: folder.appendingPathComponent("levels-\(t)-\(c).csv"))
            }
            try csv([["name"]] + (table["rowNames"] as? [String] ?? []).map { [$0] }, to: folder.appendingPathComponent("rows-\(t).csv"))
        }
        try csv(manifest, to: folder.appendingPathComponent("manifest.csv"))
        let output = url.deletingLastPathComponent().appendingPathComponent(".statsdirect-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: output) }
        try run(script, arguments: ["write", folder.path, output.path, format], folder: folder)
        // The temporary file is beside the destination, so replacement is atomic.
        guard rename(output.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
        task.waitUntilExit(); timeout.cancel()
        guard task.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw error(details.isEmpty ? "R data-file conversion stopped or exceeded two minutes." : String(details.prefix(4000)))
        }
    }
    private static func error(_ message: String) -> NSError { NSError(domain: "StatsDirect.RData", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
