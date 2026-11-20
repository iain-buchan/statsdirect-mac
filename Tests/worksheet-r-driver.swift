import Foundation

@main
struct WorksheetRDriver {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ConversationRScript.Failure(message: "Usage: worksheet-r-driver /path/to/Rscript")
        }
        let rscript = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("statsdirect-worksheet-r-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func run(_ source: String, checks: String, label: String) throws {
            let script = folder.appendingPathComponent("check.R")
            try (source + "\n" + checks).write(to: script, atomically: true, encoding: .utf8)
            let process = Process(), output = Pipe()
            process.executableURL = rscript
            process.arguments = ["--vanilla", script.path]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let text = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ConversationRScript.Failure(message: "\(label) failed in R:\n" + String(decoding: text, as: UTF8.self))
            }
            print("PASS \(label)")
        }

        func expectFailure(_ data: [String: Any], containing text: String) throws {
            do {
                _ = try WorksheetRScript.build(data)
            } catch let failure as ConversationRScript.Failure {
                guard failure.message.contains(text) else { throw failure }
                return
            }
            throw ConversationRScript.Failure(message: "Expected failure containing \(text)")
        }

        let selected: [String: Any] = [
            "workbook": "Synthetic\n# unsafe comment", "sheet": "Values", "range": "A–E",
            "rowCount": 4,
            "columns": [
                ["title": "Column A", "values": ["  Label \tname  ", "001", "NaN", "  spaced \n\"quoted\"\\path"],
                 "kinds": ["text", "text", "text", "text"]],
                ["title": "Column B", "values": ["Count", "1.25", "*", ""],
                 "kinds": ["text", "number", "text", "blank"]],
                ["title": "Column C", "values": ["", "true", "", "false"],
                 "kinds": ["blank", "boolean", "blank", "boolean"]],
                ["title": "Column D", "values": ["Text stars", "*", "", "NA"],
                 "kinds": ["text", "text", "blank", "text"]],
                ["title": "Column E", "values": ["Empty", "", "", ""],
                 "kinds": ["text", "blank", "blank", "blank"]],
            ],
        ]
        let originals = """
        stopifnot(is.data.frame(data), nrow(data) == 3L, ncol(data) == 5L,
          identical(names(data), c("  Label \\tname  ", "Count", "Column C", "Text stars", "Empty")),
          identical(data[[1]], c("001", "NaN", "  spaced \\n\\"quoted\\"\\\\path")),
          identical(data[[2]], c(1.25, NA_real_, NA_real_)),
          identical(data[[3]], c(TRUE, NA, FALSE)),
          identical(data[[4]], c("*", NA_character_, "NA")),
          identical(data[[5]], rep(NA, 3)))
        """
        try run(WorksheetRScript.build(selected, headings: true), checks: originals,
                label: "verbatim headings, text escapes, numeric and logical missing values")
        try run(WorksheetRScript.build(selected, headings: true, asList: true), checks: """
        stopifnot(is.list(data), !is.data.frame(data),
          identical(lengths(data), setNames(c(3L, 1L, 2L, 2L, 0L), names(data))),
          identical(names(data), c("  Label \\tname  ", "Count", "Column C", "Text stars", "Empty")),
          identical(data[[1]], c("001", "NaN", "  spaced \\n\\"quoted\\"\\\\path")),
          identical(data[[2]], 1.25), identical(data[[3]], c(TRUE, FALSE)),
          identical(data[[4]], c("*", "NA")), identical(data[[5]], logical(0)))
        """, label: "list columns retain types and independently omit missing positions")
        try run(WorksheetRScript.build(selected, rFriendlyNames: true), checks: """
        stopifnot(is.data.frame(data), nrow(data) == 4L,
          identical(names(data), paste("Column", LETTERS[1:5])),
          identical(data[[1]][1], "  Label \\tname  "),
          identical(data[[2]], c("Count", "1.25", "*", NA_character_)))
        """, label: "default data frame retains its first row and ignores unselected name conversion")
        let formats: [String: Any] = ["rowCount": 6, "columns": [
            ["title": "Numbers", "values": ["-1.25", "+2", ".5", "6e-4", "", "*"],
             "kinds": ["number", "number", "number", "number", "blank", "text"]],
            ["title": "Strings", "values": ["Müller", "日本語", "NA", "NaN", "Inf", "*"],
             "kinds": ["text", "text", "text", "text", "text", "text"]],
        ]]
        try run(WorksheetRScript.build(formats), checks: """
        stopifnot(identical(data[[1]], c(-1.25, 2, .5, 6e-4, NA_real_, NA_real_)),
          identical(data[[2]], c("Müller", "日本語", "NA", "NaN", "Inf", "*")))
        """, label: "decimal and scientific literals, Unicode and missing-value-like strings")

        let headers = [" Blood pressure ", "Blood pressure", "Blood_pressure_1", "Blood_pressure",
                       "for", "1st value", "a-b", "a.b", "", "NA", "  A\t B  "]
        let collisions: [String: Any] = [
            "rowCount": 2,
            "columns": headers.enumerated().map { index, heading in
                ["title": "Column \(index + 1)", "values": [heading, String(index + 1)], "kinds": ["text", "number"]]
            },
        ]
        let expectedNames = """
        c("Blood_pressure", "Blood_pressure_2", "Blood_pressure_1", "Blood_pressure_3",
          "for.", "X1st_value", "a.b", "a.b_1", "Column_9", "NA.", "A_B")
        """
        for asList in [false, true] {
            try run(WorksheetRScript.build(collisions, headings: true, rFriendlyNames: true, asList: asList),
                    checks: "stopifnot(identical(names(data), \(expectedNames)), identical(unname(unlist(data)), as.double(1:11)))",
                    label: "R names handle spaces, reserved words and collisions in \(asList ? "list" : "data frame")")
        }
        let rawNames = try headers.enumerated().map {
            try ConversationRScript.quote($0.element.isEmpty ? "Column \($0.offset + 1)" : $0.element)
        }.joined(separator: ", ")
        try run(WorksheetRScript.build(collisions, headings: true), checks: """
        stopifnot(identical(names(data), c(\(rawNames))), nrow(data) == 1L)
        """, label: "duplicate and nonsyntactic headings stay verbatim by default")

        let headingOnly: [String: Any] = ["rowCount": 1, "columns": [
            ["title": "Column A", "values": ["Heading"], "kinds": ["text"]],
            ["title": "Column B", "values": [""], "kinds": ["blank"]],
        ]]
        try run(WorksheetRScript.build(headingOnly, headings: true), checks: """
        stopifnot(is.data.frame(data), nrow(data) == 0L, identical(names(data), c("Heading", "Column B")))
        """, label: "a heading-only region retains empty data-frame columns")
        try expectFailure(["rowCount": 1, "columns": [
            ["title": "Invalid", "values": ["NaN"], "kinds": ["number"]],
        ]], containing: "invalid numeric")
        try expectFailure(["rowCount": 1, "columns": [
            ["title": "Incomplete", "values": [String](), "kinds": ["text"]],
        ]], containing: "incomplete")
        try expectFailure(["rowCount": 1, "columns": [
            ["title": "Null", "values": ["bad\0text"], "kinds": ["text"]],
        ]], containing: "null character")
        try expectFailure(["rowCount": 1, "columns": [
            ["title": "Oversize", "values": [String(repeating: "x", count: WorksheetRScript.maximumBytes)],
             "kinds": ["text"]],
        ]], containing: "8 MiB")
        print("PASS invalid data and complete script size limits")
    }
}
