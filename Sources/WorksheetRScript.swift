import Foundation

/// Writes the R script for a worksheet import (the shared worksheet R rules, sections 3 to 5) from the object the grid's
/// `worksheetRImport(scope, options)` returns. The grid has decided every name, column type and value; this writes them
/// as R code with base functions only, so that a user's start-up file cannot change the result, and writes a value
/// unquoted only once it is known to be a number, TRUE or FALSE. The one other function, str(), is named with its
/// package, utils::str, as Windows writes it, because utils may not be attached yet while a start-up file runs.
enum WorksheetRScript {
    // The R input frame includes a 36-character command UUID and a newline.
    static let maximumBytes = 8 * 1024 * 1024 - 37
    static let sizeMessage = "The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export."

    static func build(_ data: [String: Any], rFriendlyNames: Bool = false, asList: Bool = false) throws -> String {
        let unreadable = ConversationRScript.Failure(message: "The worksheet selection could not be read.")
        guard let sheet = data["sheet"] as? String, let range = data["rangeAll"] as? String,
              let rowCount = integer(data["rowCount"]), rowCount > 0,
              let columns = data["columns"] as? [[String: Any]], !columns.isEmpty,
              integer(data["columnCount"]) == columns.count,
              let names = data["names"] as? [String], names.count == columns.count,
              let dates = data["dates"] as? Bool else { throw unreadable }
        // Rule 5.5 (amendment 1): each control character in the sheet name is written as a space, U+0000 to U+001F and
        // U+007F to U+009F, so CR LF gives two spaces. A line break would end the comment, R cannot read a NUL, and on
        // Windows R stops reading a script at a raw Ctrl-Z (U+001A). The range text is only column letters, row numbers,
        // colons and commas; it goes through the same function all the same.
        func comment(_ text: String) -> String {
            var line = String.UnicodeScalarView()
            for scalar in text.unicodeScalars { line.append(scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) ? " " : scalar) }
            return String(line)
        }
        var script = "# Data copied from the worksheet “\(comment(sheet))”, \(comment(range)).\n"
            + "# Blank cells, missing-value markers and spreadsheet errors are NA.\n"
        if asList { script += "# Missing values are removed separately from each vector.\n" }
        if dates || columns.contains(where: { $0["type"] as? String == "Date" }) {
            script += "# Dates without a time of day are R Date values; other dates and times are text.\n"
        }
        script += "worksheet_data <- structure(list(\n"
        let quotedNames = try names.map(ConversationRScript.quote)
        let nameBytes = quotedNames.reduce(0) { $0 + $1.utf8.count + 2 }
        var bytes = script.utf8.count + nameBytes, dataRows = -1
        for (index, column) in columns.enumerated() {
            guard let type = column["type"] as? String, ["double", "logical", "character", "Date"].contains(type),
                  let values = column["values"] as? [Any] else { throw unreadable }
            let incomplete = ConversationRScript.Failure(message: "The worksheet selection is incomplete.")
            if asList {
                // A list holds only each column's non-missing values (rule 5.3), as the grid sends them: at most one for
                // each row, and each one is written as it comes.
                guard values.count <= rowCount else { throw incomplete }
            } else {
                // One value per data row: the rows sent, less the heading row when the first row names the columns.
                guard dataRows < 0 || values.count == dataRows, values.count == rowCount || values.count == rowCount - 1 else { throw incomplete }
                dataRows = values.count
            }
            var parts: [String] = [], present = false
            for value in values {
                let literal: String
                if value is NSNull, !asList {   // a missing value in a data frame; a list has none
                    literal = "NA"
                } else if let text = value as? String {
                    literal = try self.literal(text, type: type)
                    present = true
                } else { throw unreadable }
                bytes += literal.utf8.count + 2
                guard bytes <= maximumBytes else { throw ConversationRScript.Failure(message: sizeMessage) }
                parts.append(literal)
            }
            let vector = "c(" + parts.joined(separator: ", ") + ")"
            // A column with no value is logical: NA, R's own default, and logical(0) in a list (rule 3.6).
            script += "  " + (parts.isEmpty ? "logical(0)" : present && type == "Date" ? "structure(\(vector), class = \"Date\")" : vector)
            script += index + 1 < columns.count ? ",\n" : "\n"
            bytes = script.utf8.count + nameBytes
        }
        script += "), names = c(" + quotedNames.joined(separator: ", ") + ")"
        if asList { script += ")\n" }
        else {
            // Automatic row names, as data.frame() makes them (rule 5.2).
            script += ", row.names = " + (dataRows > 0 ? "c(NA_integer_, -\(dataRows)L)" : "integer(0)") + ", class = \"data.frame\")\n"
        }
        if rFriendlyNames {
            script += "names(worksheet_data) <- make.unique(make.names(gsub(\"[[:space:]]+\", \"_\", trimws(names(worksheet_data)))), sep = \"_\")\n"
        }
        script += "utils::str(worksheet_data)\n"
        guard script.utf8.count <= maximumBytes else { throw ConversationRScript.Failure(message: sizeMessage) }
        return script
    }

    /// Whether the grid's columns hold the values the prompt's choice asks for, as WorksheetRHost checks them before it
    /// writes the script: one value for each data row in every column of a data frame (the rows sent, less the first when
    /// it names the columns), and in a list only each column's non-missing values, at most that many.
    static func holdsDataRows(_ columns: [[String: Any]], dataRows: Int, asList: Bool) -> Bool {
        columns.allSatisfy { column in
            guard let count = (column["values"] as? [Any])?.count else { return false }
            return asList ? count <= dataRows : count == dataRows
        }
    }

    /// A value as R code: text quoted, and a number, TRUE or FALSE as the grid wrote it, once it is known to be one.
    private static func literal(_ text: String, type: String) throws -> String {
        switch type {
        case "character": return try ConversationRScript.quote(text)
        case "logical":
            guard text == "TRUE" || text == "FALSE" else { throw ConversationRScript.Failure(message: "The worksheet selection could not be read.") }
            return text
        default:   // A double, or a Date's day count since 1970-01-01.
            guard isNumber(text) || type == "double" && (text == "Inf" || text == "-Inf") else {
                throw ConversationRScript.Failure(message: "The selection contains an invalid numeric value.")
            }
            return text
        }
    }

    /// Whether text is a finite number in the one form rule 3.8 allows, which every R reads exactly: the shortest decimal
    /// with at most 15 digits once leading zeros are dropped, no exponent and at most four digits after the point;
    /// otherwise R's hexadecimal form 0x1.<13 hex digits>p<exponent>, or 0x0.<13 hex digits>p-1022 for a subnormal.
    /// Either may have a minus sign.
    static func isNumber(_ text: String) -> Bool {
        var bytes = Array(text.utf8)
        if bytes.first == UInt8(ascii: "-") { bytes.removeFirst() }
        let isDigit = { (byte: UInt8) in (48...57).contains(byte) }
        if bytes.starts(with: Array("0x".utf8)) {
            let isHex = { (byte: UInt8) in isDigit(byte) || (97...102).contains(byte) }
            guard (20...23).contains(bytes.count), bytes[2] == UInt8(ascii: "1") || bytes[2] == UInt8(ascii: "0"),
                  bytes[3] == UInt8(ascii: "."), bytes[4..<17].allSatisfy(isHex), bytes[17] == UInt8(ascii: "p"),
                  bytes[18] == UInt8(ascii: "+") || bytes[18] == UInt8(ascii: "-"), bytes[19...].allSatisfy(isDigit),
                  let exponent = Int(String(decoding: bytes[18...], as: UTF8.self)) else { return false }
            if bytes[2] == UInt8(ascii: "1") { return (-1022...1023).contains(exponent) }
            return exponent == -1022 && bytes[4..<17].contains { $0 != UInt8(ascii: "0") }
        }
        let point = bytes.firstIndex(of: UInt8(ascii: ".")) ?? bytes.count
        let whole = bytes[..<point], fraction = point < bytes.count ? bytes[(point + 1)...] : []
        guard !whole.isEmpty, whole.allSatisfy(isDigit), fraction.allSatisfy(isDigit),
              point == bytes.count || (1...4).contains(fraction.count) else { return false }
        return (whole + fraction).drop { $0 == UInt8(ascii: "0") }.count <= 15
    }

    /// A whole number from the grid's object; a Boolean, which also arrives as an NSNumber, is not one.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }
}
