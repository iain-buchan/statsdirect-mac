import Foundation

// File decoding and atomic UTF-8 output; CSV records are parsed by the grid.
enum CSVFileIO {
    static let maximumBytes = 50 * 1024 * 1024
    static func read(_ url: URL) throws -> String {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw error("CSV files can be up to 50 MB in this prototype.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw error("CSV files can be up to 50 MB in this prototype.") }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) { text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        else if data.starts(with: [0xFE, 0xFF]) { text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        else { text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) }
        guard let text, !text.contains("\0") else { throw error("This file is not a supported text CSV. Use UTF-8, UTF-16 with a byte-order mark, or Windows-1252.") }
        return text
    }
    static func write(_ text: String, to url: URL) throws {
        // Excel uses the BOM to recognise UTF-8 names and non-English labels.
        try (Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)).write(to: url, options: .atomic)
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "StatsDirect.CSV", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
