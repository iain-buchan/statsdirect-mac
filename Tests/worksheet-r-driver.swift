import Foundation

/// Worksheet R import scripts in real R (the shared worksheet R rules, sections 3 to 5). Each script is built from a
/// hand-written grid object (the contract's I2) and run by itself: it must print the str() of its object and nothing else.
/// One more R process then checks that each script makes only `worksheet_data`, identical() to an object built in R with
/// structure().
@main
struct WorksheetRDriver {
    struct Case { let label: String; let script: URL; let output: URL; let expected: String; let extra: String }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ConversationRScript.Failure(message: "Usage: worksheet-r-driver /path/to/Rscript")
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        let rscript = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("statsdirect-worksheet-r-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var cases: [Case] = [], passed = 0

        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw ConversationRScript.Failure(message: "FAIL \(label)") }
            passed += 1
            print("PASS \(label)")
        }
        func q(_ text: String) throws -> String { try ConversationRScript.quote(text) }
        /// Runs Rscript in a UTF-8 locale, as StatsDirect starts its own R session.
        func runR(_ arguments: [String]) throws -> (status: Int32, output: String, errors: String) {
            let process = Process(), id = UUID().uuidString
            let output = folder.appendingPathComponent("stdout-\(id)"), errors = folder.appendingPathComponent("stderr-\(id)")
            for url in [output, errors] { FileManager.default.createFile(atPath: url.path, contents: nil) }
            process.executableURL = rscript
            process.arguments = ["--vanilla"] + arguments
            process.environment = ProcessInfo.processInfo.environment.merging(["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]) { $1 }
            process.standardOutput = try FileHandle(forWritingTo: output)
            process.standardError = try FileHandle(forWritingTo: errors)
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: try Data(contentsOf: output), as: UTF8.self),
                    String(decoding: try Data(contentsOf: errors), as: UTF8.self))
        }
        // As StatsDirect's own R session runs a script (RConsoleWorker.cpp, evaluate): the whole text is parsed at once,
        // then each expression is evaluated in the global environment and printed when visible.
        let session = "for (e in parse(commandArgs(TRUE)[1L], encoding = \"UTF-8\", keep.source = FALSE)) "
            + "{ r <- withVisible(eval(e, globalenv())); if (r$visible) print(r$value) }"
        /// Builds the script and runs it alone. `expected` is an R expression for the object, and `extra` a further R
        /// condition on it, as x; both are checked at the end. Returns the script.
        @discardableResult func expect(_ label: String, _ data: [String: Any], rFriendlyNames: Bool = false, asList: Bool = false,
                                       _ expected: String, extra: String = "TRUE") throws -> String {
            let source = try WorksheetRScript.build(data, rFriendlyNames: rFriendlyNames, asList: asList)
            let script = folder.appendingPathComponent("case-\(cases.count + 1).R")
            let output = folder.appendingPathComponent("case-\(cases.count + 1).txt")
            try source.write(to: script, atomically: true, encoding: .utf8)
            let run = try runR(["-e", session, script.path])
            guard run.status == 0, run.errors.isEmpty, !run.output.isEmpty else {
                throw ConversationRScript.Failure(message: "FAIL \(label): R exited with status \(run.status)\n\(run.errors)\(run.output)")
            }
            // R's own console loop, line by line, as a console such as RStudio's runs it. It parses an unfinished
            // expression again for each line it reads, so a large script takes minutes this way; small ones only.
            if source.utf8.count < 1_000_000 {
                let console = try runR([script.path])
                guard console.status == 0, console.errors.isEmpty, console.output == run.output else {
                    throw ConversationRScript.Failure(message: "FAIL \(label): R's console loop printed something else\n\(console.errors)\(console.output)")
                }
            }
            try Data(run.output.utf8).write(to: output)
            cases.append(Case(label: label, script: script, output: output, expected: expected, extra: extra))
            return source
        }
        func expectFailure(_ label: String, _ data: [String: Any], _ text: String) throws {
            do { _ = try WorksheetRScript.build(data) }
            catch let failure as ConversationRScript.Failure {
                try check(failure.message.contains(text), label + " is refused (" + failure.message + ")")
                return
            }
            throw ConversationRScript.Failure(message: "FAIL \(label): expected a refusal containing \(text)")
        }
        /// An R expression that makes this text from its code points, so that no expected value relies on R reading it.
        func codePoints(_ text: String) -> String {
            "intToUtf8(c(" + text.unicodeScalars.map { "\($0.value)L" }.joined(separator: ", ") + "))"
        }

        // The prompt's two shapes, written out in full.
        let small = grid([("Age", "double", ["12", nil, "0x1.8000000000000p+0"]), ("Group", "character", ["a", nil, "b"])],
                         rowCount: 4, range: "A1:B4")
        let frameText = try expect("a data frame is written exactly as the rules show it", small, """
            structure(list(c(12, NA, 1.5), c("a", NA, "b")), names = c("Age", "Group"),
              row.names = c(NA_integer_, -3L), class = "data.frame")
            """, extra: #"identical(x, data.frame(Age = c(12, NA, 1.5), Group = c("a", NA, "b")))"#)
        try check(frameText == """
            # Data copied from the worksheet “Sheet1”, A1:B4.
            # Blank cells, missing-value markers and spreadsheet errors are NA.
            worksheet_data <- structure(list(
              c(12, NA, 0x1.8000000000000p+0),
              c("a", NA, "b")
            ), names = c("Age", "Group"), row.names = c(NA_integer_, -3L), class = "data.frame")
            str(worksheet_data)

            """, "the data frame script has the shared comments, base functions only and str(worksheet_data)")
        let dated = grid([("Age group", "double", ["12", nil, "0x1.8000000000000p+0"]), ("Visit date", "Date", ["20778", nil, "-25567"])],
                         rowCount: 4, range: "A1:B4", dates: true)
        let listText = try expect("a list with dates and R-friendly names is written exactly as the rules show it", dated,
                                  rFriendlyNames: true, asList: true, """
            structure(list(c(12, 1.5), structure(c(20778, -25567), class = "Date")), names = c("Age_group", "Visit_date"))
            """, extra: #"identical(x, list(Age_group = c(12, 1.5), Visit_date = as.Date(c("2026-11-21", "1900-01-01"))))"#)
        try check(listText == """
            # Data copied from the worksheet “Sheet1”, A1:B4.
            # Blank cells, missing-value markers and spreadsheet errors are NA.
            # Missing values are removed separately from each vector.
            # Dates without a time of day are R Date values; other dates and times are text.
            worksheet_data <- structure(list(
              c(12, 0x1.8000000000000p+0),
              structure(c(20778, -25567), class = "Date")
            ), names = c("Age group", "Visit date"))
            names(worksheet_data) <- make.unique(make.names(gsub("[[:space:]]+", "_", trimws(names(worksheet_data)))), sep = "_")
            str(worksheet_data)

            """, "the list script adds the list and date comments and the R-friendly names line")
        let datesOnly = try WorksheetRScript.build(grid([("Time", "character", ["14:30:00"])], dates: true))
        try check(datesOnly.contains("# Dates without a time of day") && !frameText.contains("# Dates without a time of day"),
                  "the date comment follows the grid's dates flag, also for times of day written as text")

        // Every column type, with missing values, as a data frame and as a list.
        let types = grid([("A", "double", ["12", nil, "Inf", "-Inf"]), ("B", "logical", ["TRUE", nil, "FALSE", "TRUE"]),
                          ("C", "character", ["a", nil, "", "NA"]), ("D", "Date", ["20778", nil, "0", "-25567"]),
                          ("E", "logical", [nil, nil, nil, nil]), ("F", "double", [nil, nil, nil, nil]),
                          ("G", "Date", [nil, nil, nil, nil]), ("H", "double", [nil, "5", nil, nil])])
        try expect("every column type keeps its type and NA in a data frame", types, """
            structure(list(c(12, NA, Inf, -Inf), c(TRUE, NA, FALSE, TRUE), c("a", NA, "", "NA"),
              structure(c(20778, NA, 0, -25567), class = "Date"), c(NA, NA, NA, NA), c(NA, NA, NA, NA), c(NA, NA, NA, NA),
              c(NA, 5, NA, NA)), names = c("A", "B", "C", "D", "E", "F", "G", "H"),
              row.names = c(NA_integer_, -4L), class = "data.frame")
            """, extra: #"""
            identical(x, data.frame(A = c(12, NA, Inf, -Inf), B = c(TRUE, NA, FALSE, TRUE), C = c("a", NA, "", "NA"),
              D = as.Date(c("2026-11-21", NA, "1970-01-01", "1900-01-01")), E = NA, F = NA, G = NA, H = c(NA, 5, NA, NA))) &&
              is.double(x$A) && is.double(x$H) && is.logical(x$F) && is.character(x$C) && identical(x$C[4], "NA")
            """#)
        try expect("a list leaves missing values out, and an all-missing column is logical(0)", types, asList: true, """
            structure(list(c(12, Inf, -Inf), c(TRUE, FALSE, TRUE), c("a", "", "NA"), structure(c(20778, 0, -25567), class = "Date"),
              logical(0), logical(0), logical(0), 5), names = c("A", "B", "C", "D", "E", "F", "G", "H"))
            """, extra: #"""
            !is.data.frame(x) && identical(lengths(x), c(A = 3L, B = 3L, C = 3L, D = 3L, E = 0L, F = 0L, G = 0L, H = 1L)) &&
              identical(x$D, as.Date(c("2026-11-21", "1970-01-01", "1900-01-01")))
            """#)

        // Numbers arrive identical() to the worksheet's doubles: the rules' examples and a large random sample.
        // Typed values that a double cannot hold exactly are read as typed, to their nearest double.
        let examples: [Double] = [0.30000000000000004, 1.0 / 3.0, 5.499065962e-14, Double("84814136847853600000")!, 1e22, 1e23,
                                  Double("9007199254740993")!, 1.7976931348623157e308, 2.2250738585072014e-308, 5e-324, -0.0,
                                  0.883020325331, 12, 13.5, 0.1, 98.6, -0.25, -5e-324, -(2.2250738585072014e-308 - 5e-324)]
        let pinned: [(Double, String)] = [(12, "12"), (13.5, "13.5"), (0.1, "0.1"), (98.6, "98.6"), (-0.25, "-0.25"), (-0.0, "0"),
                                          (100000, "100000"), (0.0001, "0.0001"), (123456789012345, "123456789012345"),
                                          (1234567890.1234, "1234567890.1234"), (0.00001, "0x1.4f8b588e368f1p-17"),
                                          (0.30000000000000004, "0x1.3333333333334p-2"), (1e22, "0x1.0f0cf064dd592p+73"),
                                          (5e-324, "0x0.0000000000001p-1022"), (2.2250738585072014e-308, "0x1.0000000000000p-1022"),
                                          (1.7976931348623157e308, "0x1.fffffffffffffp+1023")]
        let unpinned = pinned.filter { rNumber($0.0) != $0.1 }.map { "\($0.0) gave \(rNumber($0.0))" }
        try check(unpinned.isEmpty, "the test's number writer gives the contract's forms" + (unpinned.isEmpty ? "" : ": " + unpinned.joined(separator: "; ")))
        var random = SplitMix64(seed: 20261121), sample = examples
        while sample.count < 20_000 + examples.count {
            let x = Double(bitPattern: random.next())
            if x.isFinite { sample.append(x) }
        }
        for _ in 0..<20_000 {
            let digits = Int(random.next() % 15) + 1, places = Int(random.next() % 5)
            let whole = Double(random.next() % UInt64(pow(10, Double(digits))))
            sample.append((random.next() % 2 == 0 ? 1 : -1) * whole / pow(10, Double(places)))
        }
        let literals = sample.map(rNumber)
        let refused = literals.filter { !WorksheetRScript.isNumber($0) }
        try check(refused.isEmpty, "the script accepts every number in the grid's form (\(literals.count) values)" + (refused.isEmpty ? "" : ": " + refused.prefix(5).joined(separator: ", ")))
        let patterns = sample.map { "\"" + String(format: "%016llx", $0.bitPattern) + "\"" }
        let started = Date()
        try expect("\(sample.count) numbers, \(literals.filter { $0.hasPrefix("0x") || $0.hasPrefix("-0x") }.count) of them in hexadecimal, are exact",
                   grid([("A", "double", literals.map(Optional.some) + [nil])]), """
            structure(list(c(bits(c(\(patterns.joined(separator: ", ")))), NA)), names = "A",
              row.names = c(NA_integer_, -\(sample.count + 1)L), class = "data.frame")
            """)
        print("INFO the \(sample.count)-number script was built and run in R in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")

        // Names are kept exactly, including names data.frame() itself would change or refuse.
        let awkward = ["row.names", "row.names", "check.rows", "check.names", "fix.empty.names", "stringsAsFactors", "..adfl.x",
                       "..adfl.row.names", "NA", String(repeating: "n", count: 10_001), "B", "B", "  A\t B  ", "x\"y\\z"]
        let awkwardData = grid(awkward.enumerated().map { ($0.element, "double", [String($0.offset + 1)]) }, rowCount: 2)
        let awkwardNames = try awkward.map { $0.count > 10_000 ? "strrep(\"n\", 10001L)" : try q($0) }.joined(separator: ", ")
        try expect("repeated, data.frame() argument, ..adfl., NA and 10,001-byte names are kept exactly", awkwardData, """
            structure(list(\((1...awkward.count).map(String.init).joined(separator: ", "))), names = c(\(awkwardNames)),
              row.names = c(NA_integer_, -1L), class = "data.frame")
            """, extra: #"identical(names(x)[9], "NA") && !anyNA(names(x)) && nchar(names(x)[10], "bytes") == 10001L && identical(x[[2]], 2)"#)
        let friendly = [" Blood pressure ", "Blood pressure", "Blood_pressure_1", "Blood_pressure", "for", "1st value", "a-b", "a.b",
                        "B", "B", "NA", "  A\t B  ", "row.names", "row.names", "..adfl.x", "TRUE"]
        let friendlyData = grid(friendly.enumerated().map { ($0.element, "double", [String($0.offset + 1)]) }, rowCount: 2)
        let friendlyNames = #"""
            c("Blood_pressure", "Blood_pressure_2", "Blood_pressure_1", "Blood_pressure_3", "for.", "X1st_value", "a.b", "a.b_1",
              "B", "B_1", "NA.", "A_B", "row.names", "row.names_1", "..adfl.x", "TRUE.")
            """#
        let values = (1...friendly.count).map(String.init).joined(separator: ", ")
        try expect("R-friendly names in a data frame", friendlyData, rFriendlyNames: true, """
            structure(list(\(values)), names = \(friendlyNames), row.names = c(NA_integer_, -1L), class = "data.frame")
            """)
        try expect("R-friendly names in a list", friendlyData, rFriendlyNames: true, asList: true, """
            structure(list(\(values)), names = \(friendlyNames))
            """)

        // Text arrives exactly; bidi controls and control characters are escaped, so R accepts the script.
        let bidi = "a\u{2068}b\u{2069}\u{202E}c"
        let texts = [bidi, "x\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}y",
                     "\u{1}\u{1A}\u{1F}\u{7F}\u{80}\u{85}\u{9F}\u{A0}", "quote \" backslash \\ return \r newline \n tab \t end",
                     "emoji 👩‍👩‍👧 CJK 日本語 combining e\u{301} Größe", "\u{2028}\u{2029}\u{200B}\u{200E}\u{200F}\u{61C}\u{FEFF}\u{FFFD}\u{10FFFF}",
                     "  spaced  ", "*", "TRUE"]
        let textScript = try expect("a bidi heading and text with controls, quotes and Unicode arrive exactly",
                                    grid([(bidi, "character", texts.map(Optional.some)), ("plain", "double", texts.indices.map { String($0) })]), """
            structure(list(c(\(texts.map(codePoints).joined(separator: ", "))), c(\(texts.indices.map { String($0) }.joined(separator: ", ")))),
              names = c(\(codePoints(bidi)), "plain"), row.names = c(NA_integer_, -\(texts.count)L), class = "data.frame")
            """)
        let raw = textScript.unicodeScalars.filter { (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
            || $0.value < 32 && $0.value != 10 || (127...159).contains($0.value) }
        try check(raw.isEmpty, "the script holds no raw bidi or control character")
        let surrogate = NSString(characters: [0x61, 0xD800, 0x62], length: 3) as String
        try check(surrogate.unicodeScalars.map(\.value) == [0x61, 0xFFFD, 0x62], "a lone surrogate from the grid reaches Swift as U+FFFD")
        try expect("a lone surrogate arrives in R as U+FFFD", grid([("A", "character", [surrogate])]), """
            structure(list(intToUtf8(c(97L, 65533L, 98L))), names = "A", row.names = c(NA_integer_, -1L), class = "data.frame")
            """)

        // The sheet name stays in its comment: line breaks become spaces, and bidi controls may stay there.
        let sheet = "Line one\r\nworksheet_data <- 'hacked'\rnext\nend\u{0}\u{202E}x"
        let commented = try expect("a sheet name with CR, LF, NUL and a bidi control stays in its comment",
                                   grid([("A", "double", ["1", "2"])], sheet: sheet, range: "A1:A2\nC1"), """
            structure(list(c(1, 2)), names = "A", row.names = c(NA_integer_, -2L), class = "data.frame")
            """)
        try check(commented.components(separatedBy: "\n").first == "# Data copied from the worksheet “Line one  worksheet_data <- 'hacked' next end \u{202E}x”, A1:A2 C1."
                  && commented.components(separatedBy: "\n").count == 7 && !commented.unicodeScalars.contains("\r"),
                  "each CR, LF or NUL in the sheet name or range is written as a space, on the first comment line")

        // A heading row with no data below it: a data frame of no rows.
        let headingOnly = grid([("Heading", "character", []), ("B", "double", [])], rowCount: 1)
        try expect("a heading row alone gives a data frame of no rows", headingOnly, """
            structure(list(logical(0), logical(0)), names = c("Heading", "B"), row.names = integer(0), class = "data.frame")
            """, extra: #"identical(x, data.frame(Heading = logical(0), B = logical(0))) && nrow(x) == 0L"#)

        // The largest script allowed, and one byte more.
        func padded(_ count: Int) -> [String: Any] { grid([("A", "character", [String(repeating: "x", count: count)])]) }
        let fill = WorksheetRScript.maximumBytes - (try WorksheetRScript.build(padded(0))).utf8.count
        let largest = try WorksheetRScript.build(padded(fill))
        try check(largest.utf8.count == WorksheetRScript.maximumBytes, "a script of exactly the size limit is written")
        try expect("the largest script allowed runs in R", padded(fill), """
            structure(list(strrep("x", \(fill)L)), names = "A", row.names = c(NA_integer_, -1L), class = "data.frame")
            """)
        try expectFailure("a script one byte over the size limit", padded(fill + 1), "8 MiB")

        // Only numbers, TRUE and FALSE are written unquoted, and only in the grid's own forms.
        let accepted = ["0", "-0", "12", "-0.25", "0.0001", "123456789012345", "1234567890.1234", "0x1.8000000000000p+0",
                        "-0x1.fffffffffffffp+1023", "0x1.0000000000000p-1022", "0x0.0000000000001p-1022", "-0x0.fffffffffffffp-1022"]
        try check(accepted.allSatisfy(WorksheetRScript.isNumber), "the number check accepts the shortest decimal and R's hexadecimal forms")
        let rejected = ["", "-", "+1", ".5", "5.", "1.23456", "1234567890123456", "1e5", "1E5", "Inf", "NaN", "NA", "0x1p-1074",
                        "0x1.8p+0", "0x1.800000000000p+0", "0x1.80000000000000p+0", "0X1.8000000000000p+0", "0x1.8000000000000P+0",
                        "0x1.8000000000000p0", "0x1.8000000000000p+1024", "0x1.8000000000000p-1023", "0x2.8000000000000p+0",
                        "0x0.0000000000000p-1022", "0x0.0000000000001p-1021", "0x1.ABCDEF0000000p+0", "0x1.8000000000000p+00000",
                        " 1", "1 ", "1,5", "\u{661}", "1_000", "--1", "12)", "1; q()", "0x1.8000000000000p+0)"]
        let wronglyAccepted = rejected.filter(WorksheetRScript.isNumber)
        try check(wronglyAccepted.isEmpty, "the number check refuses every other text (\(rejected.count) cases)" + (wronglyAccepted.isEmpty ? "" : ": " + wronglyAccepted.joined(separator: ", ")))
        try expectFailure("a NUL in a value", grid([("A", "character", ["bad\u{0}text"])]), "null character")
        try expectFailure("a NUL in a name", grid([("bad\u{0}name", "double", ["1"])]), "null character")
        try expectFailure("a NUL before a combining mark", grid([("A", "character", ["x\u{0}\u{301}"])]), "null character")
        for (type, text) in [("double", "1e5"), ("double", "0x1p-1074"), ("double", "1; system('echo hacked')"), ("double", "TRUE"),
                             ("double", "NaN"), ("Date", "Inf"), ("Date", "")] {
            try expectFailure("the \(type) value \(text.debugDescription)", grid([("A", type, [text])]), "invalid numeric value")
        }
        for text in ["true", "T", "1", "NA"] {
            try expectFailure("the logical value \(text)", grid([("A", "logical", [text])]), "could not be read")
        }
        var malformed: [(String, [String: Any])] = [("an unknown column type", grid([("A", "integer", ["1"])])),
                                                     ("an unknown type with no values", grid([("A", "factor", [nil])]))]
        func changed(_ change: (inout [String: Any]) -> Void) -> [String: Any] { var data = small; change(&data); return data }
        malformed += [("a number not written as text", changed { $0["columns"] = [["type": "double", "values": [12]] as [String: Any]]; $0["names"] = ["A"]; $0["columnCount"] = 1; $0["rowCount"] = 1 }),
                      ("a names count that differs", changed { $0["names"] = ["Age"] }),
                      ("a missing name", changed { $0["names"] = ["Age", NSNull()] as [Any] }),
                      ("no rangeAll", changed { $0["rangeAll"] = nil }),
                      ("no dates flag", changed { $0["dates"] = nil }),
                      ("a dates flag that is text", changed { $0["dates"] = "yes" }),
                      ("a Boolean row count", changed { $0["rowCount"] = true }),
                      ("no rows", changed { $0["rowCount"] = 0 }),
                      ("a column count that differs", changed { $0["columnCount"] = 3 }),
                      ("no columns", changed { $0["columns"] = [[String: Any]](); $0["names"] = [String](); $0["columnCount"] = 0 })]
        for (label, data) in malformed { try expectFailure(label, data, "could not be read") }
        try expectFailure("columns of different lengths", grid([("A", "double", ["1", "2"]), ("B", "double", ["1"])], rowCount: 2), "incomplete")
        try expectFailure("more values than rows", grid([("A", "double", ["1", "2", "3"])], rowCount: 2), "incomplete")
        try expectFailure("two values fewer than rows", grid([("A", "double", ["1"])], rowCount: 3), "incomplete")

        // Each object, checked in R.
        var checks = #"""
            bits <- function(h) {
              s <- paste(h, collapse = "")
              readBin(as.raw(strtoi(substring(s, seq(1L, nchar(s), 2L), seq(2L, nchar(s), 2L)), 16L)), "double", n = length(h), endian = "big")
            }
            failures <- 0L
            check <- function(label, script, output, expected, extra) {
              env <- new.env(parent = globalenv())
              invisible(capture.output(sys.source(script, envir = env)))
              x <- get("worksheet_data", envir = env, inherits = FALSE)
              alone <- identical(ls(env, all.names = TRUE), "worksheet_data")
              same <- identical(x, expected)
              shown <- identical(readLines(output, encoding = "UTF-8"), capture.output(str(expected)))
              more <- isTRUE(extra(x))
              if (alone && same && shown && more) cat("OK", label, "\n") else {
                failures <<- failures + 1L
                cat("FAIL", label, "- only worksheet_data:", alone, "- identical:", same, "- prints only str():", shown, "- other checks:", more, "\n")
                str(x); str(expected)
              }
            }

            """#
        for item in cases {
            checks += "check(\(try q(item.label)), \(try q(item.script.path)), \(try q(item.output.path)),\n\(item.expected),\nfunction(x) \(item.extra))\n"
        }
        checks += "if (failures > 0L) quit(status = 1L)\n"
        let checkFile = folder.appendingPathComponent("check.R")
        try checks.write(to: checkFile, atomically: true, encoding: .utf8)
        let result = try runR([checkFile.path])
        let confirmed = result.output.components(separatedBy: "\n").filter { $0.hasPrefix("OK ") }
        guard result.status == 0, result.errors.isEmpty, confirmed.count == cases.count else {
            throw ConversationRScript.Failure(message: "FAIL the R checks (status \(result.status)):\n" + result.output + result.errors)
        }
        for item in cases { try check(true, item.label + " (run alone in R, prints only str(), identical())") }
        print("PASS \(passed) worksheet R script checks")
    }

    /// A grid import object (the contract's I2). A nil value is missing.
    static func grid(_ columns: [(String, String, [String?])], rowCount: Int? = nil, sheet: String = "Sheet1",
                     range: String = "A1", dates: Bool = false) -> [String: Any] {
        ["sheet": sheet, "range": range, "rangeAll": range, "rowCount": rowCount ?? columns[0].2.count,
         "columnCount": columns.count, "names": columns.map(\.0), "dates": dates,
         "columns": columns.map { ["type": $0.1, "values": $0.2.map { (value: String?) -> Any in value ?? NSNull() }] as [String: Any] }]
    }

    /// A number in the grid's form (the contract's I4), written here independently: the shortest decimal when it has at
    /// most 15 digits, no exponent and at most four digits after the point, otherwise R's hexadecimal form.
    static func rNumber(_ x: Double) -> String {
        if x.isInfinite { return x < 0 ? "-Inf" : "Inf" }
        if x == 0 { return "0" }
        let sign = x < 0 ? "-" : ""
        // Swift's description holds the shortest digits that name the double, as JavaScript's String(x) does.
        let text = "\(abs(x))", parts = text.split(separator: "e")
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(mantissa[0] + (mantissa.count > 1 ? mantissa[1] : "")), point = mantissa[0].count + (parts.count > 1 ? Int(parts[1])! : 0)
        while digits.first == "0" { digits.removeFirst(); point -= 1 }
        while digits.last == "0" { digits.removeLast() }
        if point >= digits.count && point <= 15 { return sign + String(digits) + String(repeating: "0", count: point - digits.count) }
        if point < digits.count && digits.count <= 15 && digits.count - point <= 4 {
            return sign + (point > 0 ? String(digits[..<point]) + "." + String(digits[point...])
                                     : "0." + String(repeating: "0", count: -point) + String(digits))
        }
        let fraction = String(x.significandBitPattern, radix: 16)
        let hex = String(repeating: "0", count: 13 - fraction.count) + fraction
        if x.exponentBitPattern == 0 { return sign + "0x0." + hex + "p-1022" }
        let exponent = Int(x.exponentBitPattern) - 1023
        return sign + "0x1." + hex + "p" + (exponent < 0 ? "-" : "+") + String(abs(exponent))
    }
}

/// A small seeded generator, so that every run tests the same numbers.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
