import Foundation
import Darwin

/// R+ delivery (rules 6.1 and 6.2 of the worksheet R rules, with amendment 1), checked without launching R.app, RStudio
/// or StatsDirect:
/// - under Rscript, the generated start-up file runs the user's own profile and .First as R would: the file the user's
///   own R_PROFILE_USER names, else ./.Rprofile, else ~/.Rprofile. Child processes get the user's R_PROFILE_USER back, or
///   none. The script is read as written whatever the user's profile sets options(encoding) or defaultPackages to. When
///   R ends, the script copy and the start-up file go by their exact paths, each only while unchanged, then the record;
/// - a script copy never takes the start-up file's or the launch record's name;
/// - R+ file names and saves in R Scripts: never hidden, within the disk's limit on a name however its accents decompose,
///   numbered only when a name is in use, and nothing left by a save that fails (one cut short by a file-size limit);
/// - the leftover clean-up of R.app launch folders and of console private folders, on fake trees, with another StatsDirect
///   still running;
/// - a real console worker whose host is killed leaves its private folder, which start-up removes once it has gone.
/// Usage: r-delivery-driver Rscript work-folder RConsoleWorker console-bootstrap.R
///   (or, as the killed host: r-delivery-driver host RConsoleWorker console-bootstrap.R sessions-folder temporary-folder info-file)
@main struct RDeliveryDriver {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static let fm = FileManager.default
    static let profileName = ".statsdirect-startup.R", recordName = ".statsdirect-launch.json"

    @MainActor static func main() async {
        do {
            let arguments = CommandLine.arguments
            if arguments.count == 3, arguments[1] == "file-names" {
                try fileNames(work: URL(fileURLWithPath: arguments[2], isDirectory: true))
                return
            }
            if arguments.count == 7, arguments[1] == "host" {
                try await host(worker: URL(fileURLWithPath: arguments[2]), bootstrap: URL(fileURLWithPath: arguments[3]),
                               sessions: URL(fileURLWithPath: arguments[4]), temporary: URL(fileURLWithPath: arguments[5]),
                               info: URL(fileURLWithPath: arguments[6]))
                return
            }
            guard arguments.count == 5 else { throw Failure(description: "Usage: r-delivery-driver Rscript work-folder RConsoleWorker console-bootstrap.R") }
            let rscript = arguments[1], work = URL(fileURLWithPath: arguments[2], isDirectory: true)
            try startupProfile(rscript: rscript, work: work.appendingPathComponent("startup", isDirectory: true))
            try userProfileVariable(rscript: rscript, work: work.appendingPathComponent("user profile", isDirectory: true))
            try encodings(rscript: rscript, work: work.appendingPathComponent("encoding", isDirectory: true))
            try basePackagesOnly(rscript: rscript, work: work.appendingPathComponent("base only", isDirectory: true))
            try exactRemoval(rscript: rscript, work: work.appendingPathComponent("exact", isDirectory: true))
            try reservedNames(rscript: rscript, work: work.appendingPathComponent("reserved", isDirectory: true))
            try fileNames(work: work.appendingPathComponent("names", isDirectory: true))
            try processIdentity()
            try launchRecords(work: work.appendingPathComponent("launches", isDirectory: true))
            try privateFolders(work: work.appendingPathComponent("private", isDirectory: true))
            try await crashedHost(work: work.appendingPathComponent("crash", isDirectory: true),
                                  worker: URL(fileURLWithPath: arguments[3]), bootstrap: URL(fileURLWithPath: arguments[4]))
            print("PASS: R+ delivery, all checks")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") throws {
        guard condition else { throw Failure(description: label + (detail().isEmpty ? "" : "\n" + detail())) }
        print("PASS: " + label)
    }
    static func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 }
    static func folder(_ url: URL) throws -> URL { try fm.createDirectory(at: url, withIntermediateDirectories: true); return url }
    static func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    /// Paths compared as the clean-up reports them: standardized, so that a doubled slash in the work folder does not matter.
    static func paths(_ urls: [URL]) -> Set<String> { Set(urls.map { $0.standardizedFileURL.path }) }

    /// An R string literal in ASCII: every other character as a \u escape, which R reads in any locale.
    static func rString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 32..<127: result.unicodeScalars.append(scalar)
            case 0..<0x10000: result += String(format: "\\u%04x", scalar.value)
            default: result += String(format: "\\U%08x", scalar.value)
            }
        }
        return result + "\""
    }

    /// A string as R code from its UTF-8 bytes, rawToChar(as.raw(c(0x.., ...))), which R hands to the file system unchanged in
    /// any locale: the form the start-up file must use for a path or name that a string literal would need an escape for.
    static func rBytes(_ text: String) -> String {
        "rawToChar(as.raw(c(" + text.utf8.map { String(format: "0x%02x", $0) }.joined(separator: ", ") + ")))"
    }

    struct RRun {
        let status: Int32
        let output: String
        /// The lines R printed itself, without those it relayed from a child process ("CHILD: ...").
        var own: String { output.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("CHILD:") }.joined(separator: "\n") }
        func count(_ text: String) -> Int { own.components(separatedBy: text).count - 1 }
        /// Whether R printed `first` before `second`, both of them.
        func printed(_ first: String, before second: String) -> Bool {
            guard let a = own.range(of: first), let b = own.range(of: second) else { return false }
            return a.lowerBound < b.lowerBound
        }
        /// The rest of each printed line that starts with `prefix`, the relayed child lines included. Swift compares the
        /// results as Unicode text: the system hands a process its environment with accented letters decomposed.
        func values(after prefix: String) -> [String] {
            output.split(separator: "\n").filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
    }
    /// Rscript as R.app would start R: HOME is the given folder, and R gets the variables StatsDirect gives R.app
    /// (configuration), for StatsDirect's own environment `statsDirect`: its start-up file and, when StatsDirect has
    /// one, the user's own R_PROFILE_USER. `extra` adds variables, such as R_PROFILE for a site profile.
    @MainActor static func runR(_ rscript: String, _ file: URL, in directory: URL, home: URL, session: RExternalSession,
                                statsDirect: [String: String] = [:], extra: [String: String] = [:]) throws -> RRun {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: rscript)
        process.arguments = [file.path]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        for key in ["R_PROFILE_USER", "R_ENVIRON_USER", "R_LIBS_USER", "R_DEFAULT_PACKAGES", "R_PROFILE", RExternalSession.userProfileVariable] {
            environment[key] = nil
        }
        environment["HOME"] = home.path; environment["LC_ALL"] = "en_US.UTF-8"
        for (key, value) in session.configuration(environment: statsDirect).environment { environment[key] = value }
        for (key, value) in extra { environment[key] = value }
        process.environment = environment
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RRun(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
    }

    static let worksheetScript = """
    worksheet_data <- structure(list(c(1, 2)), names = "A", row.names = c(NA_integer_, -2L), class = "data.frame")
    str(worksheet_data)
    writeLines("made by the script", "user-output.txt")

    """
    static let expectedData = #"identical(worksheet_data, structure(list(c(1, 2)), names = "A", row.names = c(NA_integer_, -2L), class = "data.frame"))"#

    /// A check script for R to run after the import, in `work`; it ends by printing PARENT_CHECKS_PASSED.
    static func checks(_ work: URL, _ name: String, _ lines: String) throws -> URL {
        let file = work.appendingPathComponent(name + ".R")
        try (lines + "\ncat(\"PARENT_CHECKS_PASSED\\n\")\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }
    static func write(_ text: String, to url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }

    // MARK: 6.1 and the R side of 6.2

    @MainActor static func startupProfile(rscript: String, work: URL) throws {
        // Quotes, a backslash, accented letters and a bidirectional-text control in the folder R works in.
        let root = try folder(work.appendingPathComponent("R Sessions ' \" \\ café \u{202E}x", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        let start = try folder(work.appendingPathComponent("start", isDirectory: true))
        try write(#"""
        cat("USER_PROFILE_RAN\n")
        options(statsdirect.test.profile = "home")
        .First <- function() { cat("USER_FIRST_RAN\n"); options(statsdirect.test.first = "home") }

        """#, to: home.appendingPathComponent(".Rprofile"))
        func session(_ name: String = "Sheet1 café Worksheet.R") throws -> RExternalSession {
            try RExternalSession(data: Data(worksheetScript.utf8), name: name, directory: RExternalScript.launchFolder(in: root))
        }

        // The launch record comes with the files, naming this StatsDirect and no R.app yet, with a digest for each file.
        let main = try session()
        let record = RExternalLaunchRecord.read(main.record)
        let profileData = fm.contents(atPath: main.profile.path) ?? Data()
        let profileText = String(decoding: profileData, as: UTF8.self)
        try check(main.profile.lastPathComponent == profileName && exists(main.script) && exists(main.profile)
                  && record?.files == [main.script.lastPathComponent: RExternalLaunchRecord.digest(Data(worksheetScript.utf8)),
                                       profileName: RExternalLaunchRecord.digest(profileData)]
                  && record?.host == RProcessIdentity.current && record?.app == nil
                  && record.flatMap { UUID(uuidString: $0.id) } != nil && record.map { profileText.contains("\"\($0.id)\"") } == true,
                  "an R.app launch writes its script copy, \(profileName) and a launch record naming its StatsDirect, a SHA-256 for each file and the id the start-up file holds",
                  String(describing: record))
        // The folder holds quotes, a backslash and a bidirectional-text control, which a string literal would need escapes for:
        // each path in it is written as its UTF-8 bytes, and the id, which needs none, as a plain literal. Neither the bidi
        // control nor the accented letter appears as a character (Foundation may give é decomposed, as e and U+0301).
        try check(String(data: profileData, encoding: .utf8) != nil
                  && [main.directory.path, main.script.path, main.profile.path, main.record.path].allSatisfy { profileText.contains(rBytes($0)) }
                  && record.map { profileText.contains("\"\($0.id)\"") } == true
                  && !profileText.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0xE9 || $0.value == 0x301 }
                  && !profileText.contains("\\u") && !profileText.unicodeScalars.contains { $0.value < 32 && $0.value != 10 } && !profileText.contains("unlink("),
                  "the start-up file is UTF-8, with every path in a folder holding quotes, a backslash and a bidirectional-text control as its bytes, no escape, no other control character, and never uses unlink()")

        // The user's profile and .First run as R would, and a child Rscript does not inherit StatsDirect's profile.
        let child = work.appendingPathComponent("child.R")
        try write(#"cat(paste("CHILD_STATE", Sys.getenv("R_PROFILE_USER", unset = "UNSET"), exists("worksheet_data"), exists(".First"), getOption("statsdirect.test.profile", "none")), "\n", sep = "")"#,
                  to: child)
        let first = try runR(rscript, try checks(work, "main", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "home"), identical(getOption("statsdirect.test.first"), "home"))
            stopifnot(is.na(Sys.getenv("R_PROFILE_USER", unset = NA)), is.na(Sys.getenv("\(RExternalSession.userProfileVariable)", unset = NA)), \(expectedData))
            stopifnot(identical(normalizePath(getwd()), normalizePath(\(rString(main.directory.path)))))
            child <- system2(file.path(R.home("bin"), "Rscript"), shQuote(\(rString(child.path))), stdout = TRUE, stderr = TRUE)
            writeLines(paste("CHILD:", child))
            stopifnot("CHILD_STATE UNSET FALSE TRUE home" %in% child, !any(grepl("StatsDirect", child)))
            """), in: start, home: home, session: main)
        let output = first.output
        func at(_ text: String) -> Int { output.range(of: text).map { output.distance(from: output.startIndex, to: $0.lowerBound) } ?? -1 }
        try check(first.status == 0 && output.contains("PARENT_CHECKS_PASSED"),
                  "R.app's R runs the user's ~/.Rprofile and .First, then the import; R_PROFILE_USER is unset and a child Rscript runs only the user's own profile", output)
        try check(at("USER_PROFILE_RAN") >= 0 && at("USER_PROFILE_RAN") < at("USER_FIRST_RAN") && at("USER_FIRST_RAN") < at("StatsDirect: running Sheet1 café Worksheet.R")
                  && first.count("StatsDirect: running ") == 1 && output.contains("'data.frame':\t2 obs. of  1 variable:"),
                  "the profile, then the user's .First, then the script once, with its str() output", output)
        try check(!exists(main.script) && !exists(main.profile) && !exists(main.record)
                  && exists(main.directory.appendingPathComponent("user-output.txt")) && exists(main.directory),
                  "when R ends, the script copy, \(profileName) and the launch record go; R's working folder and the user's files stay")

        // ./.Rprofile in the folder R starts in is used instead of ~/.Rprofile, as R would.
        let local = try folder(work.appendingPathComponent("start with profile", isDirectory: true))
        try write("options(statsdirect.test.profile = \"here\")\n", to: local.appendingPathComponent(".Rprofile"))
        let here = try session()
        let second = try runR(rscript, try checks(work, "here", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "here"), is.null(getOption("statsdirect.test.first")), \(expectedData))
            """), in: local, home: home, session: here)
        try check(second.status == 0 && second.output.contains("PARENT_CHECKS_PASSED") && !second.output.contains("USER_PROFILE_RAN"),
                  "./.Rprofile where R starts takes the place of ~/.Rprofile", second.output)

        // With no profile at all, nothing is reported and the import runs.
        let bare = try session(), empty = try folder(work.appendingPathComponent("empty home", isDirectory: true))
        let third = try runR(rscript, try checks(work, "bare", "stopifnot(is.null(getOption(\"statsdirect.test.profile\")), \(expectedData))"),
                             in: empty, home: empty, session: bare)
        try check(third.status == 0 && third.output.contains("PARENT_CHECKS_PASSED") && !third.output.contains("Error"),
                  "without a user profile the import runs and nothing else is reported", third.output)

        // A worksheet import does not echo its data into R.app's console, so only str() shows (rule 5.4); a console or
        // script pane's own code, the default, is still echoed command by command.
        let quiet = try RExternalSession(data: Data(worksheetScript.utf8), name: "Quiet Worksheet.R",
                                         directory: RExternalScript.launchFolder(in: root), echo: false)
        let silent = try runR(rscript, try checks(work, "quiet", "stopifnot(\(expectedData))"), in: empty, home: empty, session: quiet)
        try check(silent.status == 0 && silent.output.contains("PARENT_CHECKS_PASSED") && silent.output.contains("'data.frame':")
                  && !silent.output.contains("structure(list(c(1, 2))"),
                  "a worksheet import shows str() in R.app's console without echoing its data", silent.output)
        try check(first.output.contains("structure(list(c(1, 2))"), "a console script's commands are still echoed", first.output)

        // In a locale that is not UTF-8, R hands the file system the bytes of a path as written, so a launch folder and a
        // script with an accented name still run the import (an escape would make R translate them, which fails there).
        let plain = try folder(work.appendingPathComponent("C locale caf\u{e9}", isDirectory: true))
        // The script itself holds what a worksheet import holds: curly quotation marks in its first comment and accented data.
        let unicodeScript = "# Data copied from the worksheet \u{201C}Sheet1\u{201D}, A1:A2.\n"
            + "worksheet_data <- structure(list(c(\"caf\u{e9}\", \"x\")), names = c(\"Name\"), row.names = c(NA_integer_, -2L), class = \"data.frame\")\n"
            + "utils::str(worksheet_data)\n"
        let cSession = try RExternalSession(data: Data(unicodeScript.utf8), name: "Sheet1 caf\u{e9} Worksheet.R",
                                            directory: RExternalScript.launchFolder(in: plain), echo: false)
        let cProfile = String(decoding: fm.contents(atPath: cSession.profile.path) ?? Data(), as: UTF8.self)
        let cLocale = try runR(rscript, try checks(work, "clocale",
                                                   "stopifnot(identical(charToRaw(worksheet_data$Name[1]), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))))"),
                               in: empty, home: empty, session: cSession, extra: ["LC_ALL": "C", "LANG": "C"])
        try check(cLocale.status == 0 && cLocale.output.contains("PARENT_CHECKS_PASSED") && !exists(cSession.script),
                  "in the C locale an accented launch folder and a script with curly quotes and accented data still run the import exactly, and the copy goes when R ends", cLocale.output)
        try check(cProfile.contains("\"" + cSession.script.path + "\"") && cProfile.contains("\"" + cSession.directory.path + "\"") && !cProfile.contains("rawToChar"),
                  "a path that needs no escape, an accented one among them, is written as a plain UTF-8 literal", cProfile)
        // In the C locale R cannot translate a \u escape into the native encoding ("unable to translate ... to native
        // encoding"), so a launch folder or a script name holding a character a literal must escape would fail there: here a
        // bidirectional-text control in both, with quotes, a backslash, a C1 control and an accented letter in the folder.
        // Written as raw bytes, R hands them to the file system unchanged, and the import runs and its copies go.
        let awkward = try folder(work.appendingPathComponent("C locale \u{202E}x \" \\ \u{85} caf\u{e9}", isDirectory: true))
        let bidi = try RExternalSession(data: Data(unicodeScript.utf8), name: "Sheet1 \u{202E}x Worksheet.R",
                                        directory: RExternalScript.launchFolder(in: awkward), echo: false)
        let bidiProfile = String(decoding: fm.contents(atPath: bidi.profile.path) ?? Data(), as: UTF8.self)
        let bidiRun = try runR(rscript, try checks(work, "clocale-bidi", """
            stopifnot(identical(charToRaw(worksheet_data$Name[1]), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))))
            stopifnot(identical(basename(getwd()), "\(bidi.directory.lastPathComponent)"), file.exists(\(rBytes(bidi.script.path))))
            """), in: empty, home: empty, session: bidi, extra: ["LC_ALL": "C", "LANG": "C"])
        try check(bidiRun.status == 0 && bidiRun.output.contains("PARENT_CHECKS_PASSED") && bidiRun.output.contains("StatsDirect: running Sheet1 ")
                  && !bidiRun.output.contains("unable to translate") && !exists(bidi.script) && !exists(bidi.profile) && !exists(bidi.record)
                  && bidiProfile.contains(rBytes(bidi.script.path)) && bidiProfile.contains(rBytes(bidi.directory.path)),
                  "in the C locale a launch folder and a script name holding a bidirectional-text control are written as raw bytes, so the import runs in that folder and its copies go when R ends", bidiRun.output)
        // Echoed code is still the script's own text, comments included.
        let echoed = try RExternalSession(data: Data(unicodeScript.utf8), name: "Echoed Worksheet.R",
                                          directory: RExternalScript.launchFolder(in: root))
        let echoRun = try runR(rscript, try checks(work, "echoed", "stopifnot(exists(\"worksheet_data\"))"), in: empty, home: empty, session: echoed)
        try check(echoRun.status == 0 && echoRun.output.contains("PARENT_CHECKS_PASSED") && echoRun.output.contains("# Data copied from the worksheet"),
                  "a console script is echoed as written, its comment included", echoRun.output)

        // A copy R cannot read when it ends keeps the launch record, so that StatsDirect's own clean-up finds it later.
        let locked = try RExternalSession(data: Data(worksheetScript.utf8), name: "Locked Worksheet.R",
                                          directory: RExternalScript.launchFolder(in: root), echo: false)
        let lockedRun = try runR(rscript, try checks(work, "locked", "invisible(Sys.chmod(\(rString(locked.script.path)), \"000\"))"),
                                 in: empty, home: empty, session: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.script.path)
        try check(lockedRun.status == 0 && lockedRun.output.contains("PARENT_CHECKS_PASSED") && exists(locked.script) && exists(locked.record),
                  "a copy R cannot read when it ends keeps its launch record", lockedRun.output)

        // A StatsDirect start-up file passed on through an inherited R_PROFILE_USER is never taken for the user's own.
        let inherited = try RExternalSession(data: Data(worksheetScript.utf8), name: "Inherited Worksheet.R",
                                             directory: RExternalScript.launchFolder(in: root), echo: false)
        let variables = inherited.configuration(environment: ["R_PROFILE_USER": main.profile.path]).environment
        try check(variables[RExternalSession.userProfileVariable] == nil && variables["R_PROFILE_USER"] == inherited.profile.path,
                  "an inherited StatsDirect start-up file in R_PROFILE_USER is not passed on as the user's own", String(describing: variables))

        // An error in the user's profile stops the rest of it, as in R; an error in their .First is reported; the
        // import still runs.
        let failing = try folder(work.appendingPathComponent("failing home", isDirectory: true))
        try write(#"""
        options(statsdirect.test.profile = "partial")
        .First <- function() stop("user first failed")
        stop("user profile failed")
        options(statsdirect.test.after = TRUE)

        """#, to: failing.appendingPathComponent(".Rprofile"))
        let broken = try session()
        let fourth = try runR(rscript, try checks(work, "broken", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "partial"), is.null(getOption("statsdirect.test.after")), \(expectedData))
            """), in: start, home: failing, session: broken)
        try check(fourth.status == 0 && fourth.output.contains("PARENT_CHECKS_PASSED") && fourth.output.contains("user profile failed")
                  && fourth.output.contains("user first failed"),
                  "errors in the user's profile and .First are reported and do not stop the import", fourth.output)

        // A script copy the user saved changes to (in R.app's editor) is theirs: only the start-up file and the record go.
        let edited = try session()
        let fifth = try runR(rscript, try checks(work, "edited", "cat(\"# my own edit\\n\", file = \(rString(edited.script.path)), append = TRUE)"),
                             in: start, home: home, session: edited)
        try check(fifth.status == 0 && text(edited.script) == worksheetScript + "# my own edit\n" && !exists(edited.profile) && !exists(edited.record),
                  "a script copy saved with changes stays when R ends; \(profileName) and the launch record go", fifth.output)

        // Quitting with the workspace saved keeps it, and the user's files, in R's folder; the copies still go.
        let saving = try session()
        let sixth = try runR(rscript, try checks(work, "saving", "writeLines('kept', 'user-file.txt'); cat('PARENT_CHECKS_PASSED\\n'); q('yes')"),
                             in: start, home: home, session: saving)
        try check(sixth.status == 0 && sixth.output.contains("PARENT_CHECKS_PASSED") && exists(saving.directory.appendingPathComponent(".RData"))
                  && exists(saving.directory.appendingPathComponent("user-file.txt")) && !exists(saving.script) && !exists(saving.profile)
                  && !exists(saving.record),
                  "q(\"yes\") saves the workspace in R's folder, which stays with the user's files, and the copies still go", sixth.output)

        // recordLaunch adds R.app's process; it never brings back a record R has already removed. discard removes all
        // three files when R.app did not start, and keeps the folder.
        let recorded = try session()
        let me = RProcessIdentity.current!
        let before = RExternalLaunchRecord.read(recorded.record)
        recorded.recordLaunch(me)
        let after = RExternalLaunchRecord.read(recorded.record)
        try check(after?.app == me && after?.id == before?.id && after?.files == before?.files && after?.host == before?.host,
                  "a launched R.app's process is added to its launch record, which keeps everything else")
        try fm.removeItem(at: recorded.record); recorded.recordLaunch(me)
        try check(!exists(recorded.record), "a launch record that R removed is not written again")
        recorded.discard()
        try check(!exists(recorded.script) && !exists(recorded.profile) && exists(recorded.directory),
                  "a launch whose R.app did not start leaves no files, and its folder")
    }

    // MARK: 6.1, the user's own R_PROFILE_USER

    @MainActor static func userProfileVariable(rscript: String, work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        let start = try folder(work.appendingPathComponent("start", isDirectory: true))
        let profiles = try folder(home.appendingPathComponent("profiles", isDirectory: true))
        // ~/.Rprofile and ./.Rprofile are both there, and neither may run while the user's R_PROFILE_USER names a file.
        try write("cat(\"HOME_PROFILE_RAN\\n\")\noptions(statsdirect.test.profile = \"home\")\n", to: home.appendingPathComponent(".Rprofile"))
        try write("cat(\"LOCAL_PROFILE_RAN\\n\")\noptions(statsdirect.test.profile = \"here\")\n", to: start.appendingPathComponent(".Rprofile"))
        try write(#"""
        cat("USER_R_PROFILE_RAN ", Sys.getenv("R_PROFILE_USER", unset = "UNSET"), "\n", sep = "")
        options(statsdirect.test.profile = "user")
        "USER_PROFILE_VISIBLE"
        .First <- function() cat("USER_FIRST_RAN\n")

        """#, to: profiles.appendingPathComponent("user profile é.R"))
        let child = work.appendingPathComponent("child.R")
        try write(#"cat(paste("CHILD_STATE", Sys.getenv("R_PROFILE_USER", unset = "UNSET"), exists("worksheet_data"), getOption("statsdirect.test.profile", "none")), "\n", sep = "")"#,
                  to: child)
        let runChild = """
            child <- system2(file.path(R.home("bin"), "Rscript"), shQuote(\(rString(child.path))), stdout = TRUE, stderr = TRUE)
            writeLines(paste("CHILD:", child))
            """
        func session() throws -> RExternalSession {
            try RExternalSession(data: Data(worksheetScript.utf8), name: "Sheet1 Worksheet.R", directory: RExternalScript.launchFolder(in: root))
        }

        // StatsDirect hands the user's own value to R.app in a variable of its own, only when it has one.
        let handover = try session(), variable = RExternalSession.userProfileVariable
        let given = handover.configuration(environment: ["R_PROFILE_USER": "~/profiles/user profile é.R", "HOME": "/elsewhere"]).environment
        let blank = handover.configuration(environment: ["R_PROFILE_USER": ""]).environment
        let none = handover.configuration(environment: ["HOME": "/elsewhere"]).environment
        try check(given == ["R_PROFILE_USER": handover.profile.path, variable: "~/profiles/user profile é.R"]
                  && blank == ["R_PROFILE_USER": handover.profile.path, variable: ""] && none == ["R_PROFILE_USER": handover.profile.path]
                  && handover.configuration().environment[variable] == ProcessInfo.processInfo.environment["R_PROFILE_USER"]
                  && handover.configuration().createsNewApplicationInstance,
                  "R.app gets StatsDirect's start-up file, and \(variable) only when StatsDirect's own environment has R_PROFILE_USER",
                  "\(given)\n\(blank)\n\(none)")
        handover.discard()

        // The file the user's R_PROFILE_USER names (here with ~, as a user may write it) runs in place of ./.Rprofile and
        // ~/.Rprofile, printing what it prints, with R_PROFILE_USER already the user's own; R processes started from the
        // session get it back, and run the user's profile, not StatsDirect's.
        let userValue = "~/profiles/user profile é.R"
        let named = try session()
        let run = try runR(rscript, try checks(work, "named", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "user"), is.na(Sys.getenv("\(variable)", unset = NA)), \(expectedData))
            cat("PARENT_R_PROFILE_USER=", Sys.getenv("R_PROFILE_USER", unset = "UNSET"), "\\n", sep = "")
            \(runChild)
            stopifnot(!any(grepl("StatsDirect|HOME_PROFILE_RAN|LOCAL_PROFILE_RAN", child)))
            """), in: start, home: home, session: named, statsDirect: ["R_PROFILE_USER": userValue])
        try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && run.values(after: "USER_R_PROFILE_RAN ") == [userValue]
                  && run.count("[1] \"USER_PROFILE_VISIBLE\"") == 1 && run.count("USER_FIRST_RAN") == 1
                  && run.count("HOME_PROFILE_RAN") == 0 && run.count("LOCAL_PROFILE_RAN") == 0
                  && run.printed("USER_R_PROFILE_RAN", before: "USER_FIRST_RAN") && run.printed("USER_FIRST_RAN", before: "StatsDirect: running")
                  && run.values(after: "PARENT_R_PROFILE_USER=") == [userValue]
                  && !exists(named.script) && !exists(named.profile) && !exists(named.record),
                  "the user's own R_PROFILE_USER file runs instead of ./.Rprofile and ~/.Rprofile, with that variable already the user's, and prints its values",
                  run.output)
        try check(run.values(after: "CHILD: USER_R_PROFILE_RAN ") == [userValue] && run.values(after: "CHILD: CHILD_STATE ") == [userValue + " FALSE user"],
                  "a child Rscript gets the user's R_PROFILE_USER back, and runs that profile, not StatsDirect's", run.output)

        // An empty R_PROFILE_USER means no user profile in R; it stays so, for R processes started from the session too.
        let empty = try session()
        let blankRun = try runR(rscript, try checks(work, "empty", """
            stopifnot(is.null(getOption("statsdirect.test.profile")), identical(Sys.getenv("R_PROFILE_USER", unset = NA), ""), \(expectedData))
            \(runChild)
            stopifnot("CHILD_STATE  FALSE none" %in% child)
            """), in: start, home: home, session: empty, statsDirect: ["R_PROFILE_USER": ""])
        try check(blankRun.status == 0 && blankRun.output.contains("PARENT_CHECKS_PASSED") && !blankRun.output.contains("PROFILE_RAN"),
                  "an empty R_PROFILE_USER of the user's runs no profile, and child processes get it back empty", blankRun.output)

        // A value naming no file runs nothing, as in R, and does not fall back to ~/.Rprofile.
        let missing = try session()
        let missingRun = try runR(rscript, try checks(work, "missing", """
            stopifnot(is.null(getOption("statsdirect.test.profile")), identical(Sys.getenv("R_PROFILE_USER"), "~/profiles/missing.R"), \(expectedData))
            """), in: start, home: home, session: missing, statsDirect: ["R_PROFILE_USER": "~/profiles/missing.R"])
        try check(missingRun.status == 0 && missingRun.output.contains("PARENT_CHECKS_PASSED") && !missingRun.output.contains("PROFILE_RAN")
                  && !missingRun.output.contains("Error") && !missingRun.output.contains("cannot open"),
                  "a user R_PROFILE_USER naming no file runs no profile and reports nothing, as R does", missingRun.output)
    }

    // MARK: 6.1, encodings

    @MainActor static func encodings(rscript: String, work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        try write("options(encoding = \"latin1\")\n", to: home.appendingPathComponent(".Rprofile"))
        // As a worksheet import writes it: UTF-8, with bidirectional-text controls as escapes and other characters as they are.
        let cafe = "caf\u{E9}", naive = "na\u{EF}ve", shalom = "\u{5E9}\u{5DC}\u{5D5}\u{5DD}", emoji = "\u{1F600}"
        let heading = "\u{3A9} \u{2067}x\u{2069}"
        let script = """
        worksheet_data <- structure(list(c("\(cafe)", "\(naive)"), c(1, 2), c("\(shalom)", "\(emoji)")), names = c("\(cafe)", "\u{3A9} \\u2067x\\u2069", "\(shalom)"), row.names = c(NA_integer_, -2L), class = "data.frame")
        utils::str(worksheet_data)

        """
        try check(script.unicodeScalars.contains { $0.value == 0xE9 } && !script.unicodeScalars.contains { $0.value == 0x2067 },
                  "the encoding test's script holds é as UTF-8 and its bidirectional-text controls as escapes")
        // The expected object in printable ASCII, with every other character as an escape, which no setting can change.
        let expected = """
        expected <- structure(list(c(\(rString(cafe)), \(rString(naive))), c(1, 2), c(\(rString(shalom)), \(rString(emoji)))), names = c(\(rString(cafe)), \(rString(heading)), \(rString(shalom))), row.names = c(NA_integer_, -2L), class = "data.frame")
        bytes <- function(x) lapply(c(names(x), unlist(lapply(x, as.character))), charToRaw)
        stopifnot(identical(worksheet_data, expected), identical(bytes(worksheet_data), bytes(expected)))
        """
        func session() throws -> RExternalSession {
            try RExternalSession(data: Data(script.utf8), name: "Sheet1 café Worksheet.R", directory: RExternalScript.launchFolder(in: root), echo: false)
        }

        let launch = try session()
        let run = try runR(rscript, try checks(work, "latin1", """
            stopifnot(identical(getOption("encoding"), "latin1"))
            \(expected)
            # The user's setting is in force: read with it, the same file would give other values.
            reread <- new.env()
            changed <- tryCatch({ capture.output(source(\(rString(launch.script.path)), local = reread)); !identical(reread$worksheet_data, expected) },
                                error = function(e) TRUE)
            stopifnot(changed)
            """), in: home, home: home, session: launch)
        try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && run.output.contains("StatsDirect: running Sheet1 café Worksheet.R")
                  && run.output.contains("'data.frame':\t2 obs. of  3 variables:") && !run.output.contains("StatsDirect script:"),
                  "options(encoding = \"latin1\") in the user's .Rprofile leaves café, a bidirectional heading, Hebrew and an emoji exactly as written",
                  run.output)

        // The user's own start-up file is read as R reads it, without re-encoding, even when a site profile sets
        // options(encoding) before it runs.
        let site = work.appendingPathComponent("Rprofile.site")
        try write("options(encoding = \"latin1\")\n", to: site)
        let siteHome = try folder(work.appendingPathComponent("site home", isDirectory: true))
        try write("options(statsdirect.test.text = \"caf\u{E9} \u{3A9}\")\n", to: siteHome.appendingPathComponent(".Rprofile"))
        let siteLaunch = try session()
        let siteRun = try runR(rscript, try checks(work, "site", """
            stopifnot(identical(getOption("encoding"), "latin1"), identical(charToRaw(getOption("statsdirect.test.text")), charToRaw(\(rString("caf\u{E9} \u{3A9}")))))
            \(expected)
            """), in: siteHome, home: siteHome, session: siteLaunch, extra: ["R_PROFILE": site.path])
        try check(siteRun.status == 0 && siteRun.output.contains("PARENT_CHECKS_PASSED"),
                  "the user's .Rprofile is read without re-encoding, and the import is exact, when a site profile sets options(encoding)", siteRun.output)
    }

    // MARK: 6.1, default packages

    @MainActor static func basePackagesOnly(rscript: String, work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        try write("options(defaultPackages = \"base\")\n", to: home.appendingPathComponent(".Rprofile"))
        let script = """
        worksheet_data <- structure(list(c(1, 2)), names = "A", row.names = c(NA_integer_, -2L), class = "data.frame")
        utils_attached <- "package:utils" %in% search()
        utils::str(worksheet_data)

        """
        let launch = try RExternalSession(data: Data(script.utf8), name: "Sheet1 Worksheet.R", directory: RExternalScript.launchFolder(in: root), echo: false)
        let run = try runR(rscript, try checks(work, "base", "stopifnot(!utils_attached, identical(getOption(\"defaultPackages\"), \"base\"), \(expectedData))"),
                           in: home, home: home, session: launch)
        try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && run.output.contains("'data.frame':\t2 obs. of  1 variable:")
                  && !run.output.contains("StatsDirect script:") && !run.output.contains("Error") && !exists(launch.script) && !exists(launch.profile)
                  && !exists(launch.record),
                  "with a profile that sets options(defaultPackages = \"base\"), utils is not attached, and the import and utils::str() still work", run.output)
    }

    // MARK: 6.2, exact paths and the user's own files

    @MainActor static func exactRemoval(rscript: String, work: URL) throws {
        // A folder whose own path holds no pattern characters, so that R can read the copy's path as a pattern, as
        // unlink() did.
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let home = try folder(work.appendingPathComponent("empty home", isDirectory: true))
        let cases = [("survey [final] Worksheet.R", "survey f Worksheet.R"), ("draft* Worksheet.R", "draft-final Worksheet.R"),
                     ("what? Worksheet.R", "whatX Worksheet.R"), ("a\\b Worksheet.R", "ab Worksheet.R")]
        for (index, (name, other)) in cases.enumerated() {
            let launch = try RExternalSession(data: Data(worksheetScript.utf8), name: name, directory: RExternalScript.launchFolder(in: root), echo: false)
            let users = launch.directory.appendingPathComponent(other)
            try write("# the user's own\n", to: users)
            // R works in the launch folder: there the copy's name, read as a pattern, matches the user's file.
            let run = try runR(rscript, try checks(work, "pattern \(index)", """
                stopifnot(\(expectedData), \(rString(other)) %in% Sys.glob(\(rString(name))))
                """), in: home, home: home, session: launch)
            try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && !exists(launch.script) && !exists(launch.profile)
                      && !exists(launch.record) && text(users) == "# the user's own\n",
                      "when R ends, the copy \"\(name)\" goes by its exact path, and \"\(other)\", which that name read as a pattern matches, stays",
                      run.output)
        }

        // The user's own files in the launch folder are theirs: one under the start-up file's old name, and StatsDirect's
        // start-up file itself once the user has replaced it. Only what StatsDirect wrote, unchanged, goes.
        let launch = try RExternalSession(data: Data(worksheetScript.utf8), name: "Sheet1 Worksheet.R", directory: RExternalScript.launchFolder(in: root), echo: false)
        let run = try runR(rscript, try checks(work, "own files", """
            writeLines("# my own set-up", "startup.R")
            writeLines("# my own, in StatsDirect's place", \(rString(launch.profile.path)))
            stopifnot(\(expectedData))
            """), in: home, home: home, session: launch)
        try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && !exists(launch.script) && !exists(launch.record)
                  && text(launch.directory.appendingPathComponent("startup.R")) == "# my own set-up\n"
                  && text(launch.profile) == "# my own, in StatsDirect's place\n",
                  "when R ends, a startup.R the user saved stays, and so does \(profileName) once the user has replaced it; the copy and the record go",
                  run.output)
        // A file the user put in the record's place is not this launch's record, and stays.
        let replaced = try RExternalSession(data: Data(worksheetScript.utf8), name: "Sheet1 Worksheet.R", directory: RExternalScript.launchFolder(in: root), echo: false)
        let replacedRun = try runR(rscript, try checks(work, "own record", """
            writeLines("my own notes", \(rString(replaced.record.path)))
            stopifnot(\(expectedData))
            """), in: home, home: home, session: replaced)
        try check(replacedRun.status == 0 && replacedRun.output.contains("PARENT_CHECKS_PASSED") && !exists(replaced.script) && !exists(replaced.profile)
                  && text(replaced.record) == "my own notes\n",
                  "when R ends, a file the user saved in the launch record's place stays; the copy and the start-up file go", replacedRun.output)
    }

    // MARK: Reserved names

    @MainActor static func reservedNames(rscript: String, work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        try write("cat(\"USER_PROFILE_RAN\\n\")\n", to: home.appendingPathComponent(".Rprofile"))
        let code = "user_value <- \"the user's code\"\ncat(\"USER_CODE_RAN\\n\")\n"
        // The start-up file's and the record's names in other letter cases, including a long s, which the Mac's disks
        // also take for an s.
        let reserved = [profileName, ".STATSDIRECT-STARTUP.R", ".Statsdirect-Startup.r", ".\u{17F}tatsdirect-startup.R",
                        recordName, ".Statsdirect-Launch.JSON"]
        for name in reserved {
            let launch = try RExternalSession(data: Data(code.utf8), name: name, directory: RExternalScript.launchFolder(in: root))
            let names = Set((try? fm.contentsOfDirectory(atPath: launch.directory.path)) ?? [])
            try check(launch.script.lastPathComponent == "Script " + name && names == [recordName, profileName, "Script " + name]
                      && text(launch.script) == code && RExternalLaunchRecord.read(launch.record)?.files.count == 2,
                      "a script named \"\(name)\" is copied as \"Script \(name)\", beside the start-up file and the record", names.sorted().joined(separator: ", "))
        }
        try check([".statsdirect-startup.R.R", "startup.R", "Startup.R", "x.statsdirect-startup.R", ".Rprofile.R", "Sheet1 Worksheet.R"]
                    .allSatisfy { RExternalSession.scriptName($0) == $0 },
                  "every other name, startup.R included, is kept as it is")

        // R runs the user's code once, from its own file, and the user's profile once.
        for name in [profileName, "startup.R"] {
            let launch = try RExternalSession(data: Data(code.utf8), name: name, directory: RExternalScript.launchFolder(in: root))
            let run = try runR(rscript, try checks(work, "reserved " + name, "stopifnot(identical(user_value, \"the user's code\"))"),
                               in: home, home: home, session: launch)
            try check(run.status == 0 && run.output.contains("PARENT_CHECKS_PASSED") && run.count("USER_CODE_RAN\n") == 1
                      && run.count("USER_PROFILE_RAN") == 1 && run.count("StatsDirect: running " + launch.script.lastPathComponent + "\n") == 1
                      && !run.output.contains("Sys.unsetenv") && !exists(launch.script) && !exists(launch.profile) && !exists(launch.record),
                      "a script named \(name) runs once as the user's code, and the user's profile once", run.output)
        }
    }

    // MARK: R+ file names

    @MainActor static func fileNames(work: URL) throws {
        try check(RExternalScript.fileName("Sheet1 Worksheet") == "Sheet1 Worksheet.R"
                  && RExternalScript.fileName("Tutor/replay: X.R") == "Tutor_replay_ X.R"
                  && RExternalScript.fileName("analysis.r") == "analysis.r"
                  && RExternalScript.fileName("  ") == "Script.R"
                  && RExternalScript.fileName("a\nb\u{202E}c\u{7}d") == "a_b_c_d.R",
                  "script file names replace / : control and bidirectional-text characters, keep an R extension, and are never empty")
        let long = RExternalScript.fileName(String(repeating: "é", count: 150))
        try check(long == String(repeating: "é", count: 99) + ".R", "a long title is shortened on a character boundary", long)

        var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 21; parts.hour = 10; parts.minute = 15; parts.second = 30
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        let scripts = work.appendingPathComponent("R Scripts", isDirectory: true)
        let first = try RExternalScript.saveUnique("first <- 1\n", name: "Sheet1 Worksheet", date: date, in: scripts)
        let second = try RExternalScript.saveUnique("second <- 2\n", name: "Sheet1 Worksheet", date: date, in: scripts)
        let third = try RExternalScript.saveUnique("third <- 3\n", name: "Sheet1 Worksheet", date: date, in: scripts)
        let console = try RExternalScript.saveUnique("x\n", name: "R Console 1: analysis.R", date: date, in: scripts)
        try check([first, second, third, console].map(\.lastPathComponent)
                    == ["Sheet1 Worksheet 2026-11-21 101530.R", "Sheet1 Worksheet 2026-11-21 101530 2.R",
                        "Sheet1 Worksheet 2026-11-21 101530 3.R", "R Console 1_ analysis 2026-11-21 101530.R"]
                  && text(first) == "first <- 1\n" && text(second) == "second <- 2\n" && text(third) == "third <- 3\n",
                  "RStudio gets one new file per import, named by date and time, numbered on a clash, never replacing another",
                  [first, second, third, console].map(\.lastPathComponent).joined(separator: "\n"))
        let saved = try RExternalScript.save("old <- 1\n", name: "Sheet1 Worksheet", in: scripts)
        let again = try RExternalScript.save("new <- 2\n", name: "Sheet1 Worksheet", in: scripts)
        try check(saved == again && saved.lastPathComponent == "Sheet1 Worksheet.R" && text(again) == "new <- 2\n",
                  "explicit script Save can still replace the earlier save of the same name")

        // The same production fallback handles no GUI, a failed R.app launch, and a declined R installation. Each
        // quiet worksheet source must remain separate, including when the title and timestamp collide with files
        // already saved by the user. No R application is launched by these checks.
        let fallbacks = try ["no GUI", "failed R.app launch", "declined installation"].enumerated().map { index, reason in
            try RExternalScript.saveFallback("# \(reason)\nworksheet_data <- \(index + 1)\n",
                                             name: "Sheet1 Worksheet", echo: false, date: date, in: scripts)
        }
        try check(fallbacks.map(\.lastPathComponent) == ["Sheet1 Worksheet 2026-11-21 101530 4.R",
                                                       "Sheet1 Worksheet 2026-11-21 101530 5.R",
                                                       "Sheet1 Worksheet 2026-11-21 101530 6.R"]
                  && Set(fallbacks).count == 3
                  && fallbacks.enumerated().allSatisfy { text($0.element)?.contains("worksheet_data <- \($0.offset + 1)\n") == true },
                  "worksheet fallbacks retain each same-title import, numbering existing timestamp collisions")
        try check(text(saved) == "new <- 2\n" && text(first) == "first <- 1\n" && text(second) == "second <- 2\n"
                  && text(third) == "third <- 3\n",
                  "worksheet fallbacks never replace the user's plain filename or any earlier dated import")
        let consoleFallback = try RExternalScript.saveFallback("console <- 9\n", name: "Console", echo: true, date: date, in: scripts)
        let consoleAgain = try RExternalScript.saveFallback("console <- 10\n", name: "Console", echo: true, date: date, in: scripts)
        try check(consoleFallback == consoleAgain && consoleAgain.lastPathComponent == "Console.R" && text(consoleAgain) == "console <- 10\n",
                  "console fallback keeps its established named-script behavior, independently of worksheet imports")

        try hiddenNames(work: work.appendingPathComponent("visible", isDirectory: true), date: date)
        try longNames(work: work.appendingPathComponent("long", isDirectory: true), date: date)
        try clashes(work: work.appendingPathComponent("clashes", isDirectory: true), date: date)
        try failedWrites(work: work.appendingPathComponent("write fails", isDirectory: true), date: date)
    }

    /// No file in R Scripts is hidden: Finder, RStudio's Files pane and R's list.files() do not show a name that starts with ".".
    @MainActor static func hiddenNames(work: URL, date: Date) throws {
        let accents = "a" + String(repeating: "\u{301}", count: 300)
        // The "." becomes "_", as "/" and ":" do, also after spaces or with an accent on it. A title that shortening leaves
        // empty, one character with 300 accents on it, is named Script.
        try check(RExternalScript.fileName(".backup Worksheet") == "_backup Worksheet.R" && RExternalScript.fileName("  .Data") == "_Data.R"
                  && RExternalScript.fileName(".") == "_.R" && RExternalScript.fileName(".\u{301}x.r") == "_\u{301}x.r"
                  && RExternalScript.fileName(accents) == "Script.R",
                  "a title starting with \".\" gives a file name starting with \"_\", and one that shortening leaves empty is named Script",
                  [".backup Worksheet", "  .Data", ".", ".\u{301}x.r", accents].map { RExternalScript.fileName($0).debugDescription }.joined(separator: "\n"))
        let place = try folder(work)
        let saved = try [RExternalScript.saveFallback("x <- 1\n", name: ".backup Worksheet", echo: false, date: date, in: place),
                         RExternalScript.saveFallback("x <- 2\n", name: accents, echo: false, date: date, in: place)]
        let shown = try fm.contentsOfDirectory(at: place, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).map(\.lastPathComponent)
        try check(saved.map(\.lastPathComponent) == ["_backup Worksheet 2026-11-21 101530.R", "Script 2026-11-21 101530.R"]
                  && Set(shown) == Set(saved.map(\.lastPathComponent))
                  && saved.allSatisfy { (try? $0.resourceValues(forKeys: [.isHiddenKey]).isHidden) == false },
                  "a worksheet named \".backup\", or one whose name shortening empties, is saved where Finder and R's list.files() show it",
                  shown.joined(separator: "\n"))
    }

    /// The Mac's disks allow a name 255 UTF-16 units in the decomposed form Foundation hands them, which can be several times
    /// its length as typed.
    @MainActor static func longNames(work: URL, date: Date) throws {
        /// A name's length as the disk counts it, from the path Foundation gives the file system.
        func units(_ name: String) -> Int {
            URL(fileURLWithPath: "/").appendingPathComponent(name).withUnsafeFileSystemRepresentation { String(cString: $0!) }.utf16.count - 1
        }
        try check(RExternalScript.fileName(String(repeating: "\u{E9}", count: 99)) == String(repeating: "\u{E9}", count: 99) + ".R"
                  && RExternalScript.fileName(String(repeating: "a", count: 199)) == String(repeating: "a", count: 198) + ".R",
                  "a file name of 200 units is kept as it is; one unit more and it is shortened")
        // However a title decomposes, its file name leaves room for a date and a number, and each kind of save works: here
        // "ǖ" and "ΐ" (3 units each, decomposed), "ᾂ" (4) and a CJK compatibility ideograph, which Foundation keeps whole
        // (2 units, where NFD would give 1).
        for (letter, count) in [("\u{1D6}", 76), ("\u{390}", 99), ("\u{1F82}", 66), ("\u{2F800}", 150)] {
            let title = String(repeating: letter, count: count) + " Worksheet", name = RExternalScript.fileName(title)
            let place = try folder(work.appendingPathComponent(String(format: "U+%04X", letter.unicodeScalars.first!.value), isDirectory: true))
            let saved = try [RExternalScript.saveUnique("x <- 1\n", name: title, date: date, in: place),
                             RExternalScript.saveUnique("x <- 2\n", name: title, date: date, in: place),
                             RExternalScript.save("x <- 3\n", name: title, in: place)]
            try check(units(name) <= 200 && name.hasPrefix(letter) && saved.map(text) == ["x <- 1\n", "x <- 2\n", "x <- 3\n"]
                      && saved[1].lastPathComponent.hasSuffix(" 101530 2.R"),
                      "a title of \(count) \(letter) gives a name of \(units(name)) units as the disk counts them, and the dated, numbered and named saves all work",
                      saved.map { "\(units($0.lastPathComponent)) units: \($0.lastPathComponent)" }.joined(separator: "\n"))
        }
    }

    /// A file written under its name exactly as given, as R or a shell writes one, where Foundation would decompose its accents.
    static func writeAsGiven(_ text: String, in folder: URL, name: String) throws {
        let descriptor = open(folder.path + "/" + name, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else { throw Failure(description: "could not create \(name): errno \(errno)") }
        defer { close(descriptor) }
        let bytes = Array(text.utf8)
        guard Darwin.write(descriptor, bytes, bytes.count) == bytes.count else { throw Failure(description: "could not write \(name)") }
    }

    /// What is in a folder, by name: each file's permissions and text, each link's destination.
    static func entries(_ folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for name in try fm.contentsOfDirectory(atPath: folder.path) {
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw Failure(description: "cannot read \(name)") }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: result[name] = "folder"
            case S_IFLNK: result[name] = "link to " + (try fm.destinationOfSymbolicLink(atPath: url.path))
            default: result[name] = "file " + String(info.st_mode & 0o777, radix: 8) + " " + (text(url) ?? "unreadable")
            }
        }
        return result
    }

    /// Only a name in use moves on to the next number.
    @MainActor static func clashes(work: URL, date: Date) throws {
        let root = try folder(work)
        let ignoresCase = try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames != true
        let first = "Caf\u{E9} Worksheet 2026-11-21 101530.R", user = "# the user's\n"
        // Each of these takes the first name, and is left as it was: the name in capitals (on a disk that ignores case, as a
        // Mac's does unless set up otherwise), the name with its accent precomposed or decomposed (as R or a shell may write
        // it), a folder, a link to a file, a broken link and a read-only file.
        for kind in ["letter case", "precomposed", "decomposed", "folder", "link to a file", "broken link", "read-only file"] {
            let place = try folder(root.appendingPathComponent(kind, isDirectory: true)), taken = place.appendingPathComponent(first)
            switch kind {
            case "letter case": try writeAsGiven(user, in: place, name: "CAF\u{C9} WORKSHEET 2026-11-21 101530.R")
            case "precomposed": try writeAsGiven(user, in: place, name: first)
            case "decomposed": try writeAsGiven(user, in: place, name: "Cafe\u{301} Worksheet 2026-11-21 101530.R")
            case "folder": try fm.createDirectory(at: taken, withIntermediateDirectories: false)
            case "link to a file":
                try writeAsGiven(user, in: place, name: "target.R")
                try fm.createSymbolicLink(atPath: taken.path, withDestinationPath: "target.R")
            case "broken link": try fm.createSymbolicLink(atPath: taken.path, withDestinationPath: "no such file.R")
            default:
                try writeAsGiven(user, in: place, name: first)
                guard chmod(taken.path, 0o444) == 0 else { throw Failure(description: "could not make the file read-only") }
            }
            // The name is on the disk in the form it was written in: the accent precomposed (U+00E9) or decomposed (U+0301).
            if kind == "precomposed" || kind == "decomposed" {
                let accent: Unicode.Scalar = kind == "precomposed" ? "\u{E9}" : "\u{301}"
                try check(try fm.contentsOfDirectory(atPath: place.path).contains { $0.unicodeScalars.contains(accent) },
                          "the user's file is on the disk with its accent " + kind)
            }
            let before = try entries(place)
            let saved = try RExternalScript.saveUnique("x <- 1\n", name: "Caf\u{E9} Worksheet", date: date, in: place)
            var after = try entries(place)
            let added = after.removeValue(forKey: saved.lastPathComponent)
            // A disk that tells case apart has no clash in capitals.
            let numbered = kind != "letter case" || ignoresCase
            let expected = numbered ? "Caf\u{E9} Worksheet 2026-11-21 101530 2.R" : first
            let what: String
            switch kind {
            case "letter case": what = "the name in capitals"
            case "precomposed", "decomposed": what = "the name with its accent " + kind
            default: what = "a " + kind
            }
            try check(saved.lastPathComponent == expected && added?.hasPrefix("file ") == true && text(saved) == "x <- 1\n" && after == before,
                      "a name taken by " + what + (numbered ? " moves the import on to \" 2\"" : " is no clash on this disk") + ", and is left as it was",
                      "\(saved.lastPathComponent)\nbefore: \(before)\nafter: \(after)")
        }
    }

    /// `body` run while a write that takes a file beyond `bytes` fails with EFBIG, as a full disk fails one, rather than
    /// raising SIGXFSZ, which would end the process. Nothing is printed meanwhile, in case the output is a file.
    @MainActor static func withFileSizeLimit<T>(_ bytes: rlim_t, _ body: () -> T) throws -> T {
        var limit = rlimit()
        guard getrlimit(RLIMIT_FSIZE, &limit) == 0 else { throw Failure(description: "could not read the file-size limit") }
        let saved = limit, handler = signal(SIGXFSZ, SIG_IGN)
        defer { signal(SIGXFSZ, handler) }
        fflush(stdout)
        limit.rlim_cur = bytes
        guard setrlimit(RLIMIT_FSIZE, &limit) == 0 else { throw Failure(description: "could not set a file-size limit") }
        let result = body()
        var restored = saved
        guard setrlimit(RLIMIT_FSIZE, &restored) == 0 else { throw Failure(description: "could not restore the file-size limit") }
        return result
    }

    /// Any other failure is reported as it is, and leaves nothing behind.
    @MainActor static func failedWrites(work: URL, date: Date) throws {
        let place = try folder(work), script = String(repeating: "x <- 1\n", count: 1200)
        // An 8 KiB import stops at a 4 KiB file-size limit, as it would on a full disk. Foundation leaves the file it created,
        // cut short; were that taken for a name in use, each attempt would leave one more and move on, to " 2", " 3" and so
        // on, and after 1000 report that the name was taken. RStudio's imports and every worksheet fallback save this way.
        let (unique, fallback) = try withFileSizeLimit(4096) {
            (Result { try RExternalScript.saveUnique(script, name: "Sheet1 Worksheet", date: date, in: place) },
             Result { try RExternalScript.saveFallback(script, name: "Sheet1 Worksheet", echo: false, date: date, in: place) })
        }
        func tooLarge(_ result: Result<URL, Error>) -> Bool {
            guard case .failure(let error) = result else { return false }
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            return (error as? CocoaError)?.code != .fileWriteFileExists && underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EFBIG)
        }
        let left = try fm.contentsOfDirectory(atPath: place.path)
        try check(tooLarge(unique) && tooLarge(fallback) && left.isEmpty,
                  "a save that fails for another reason, here a file-size limit, reports that error and leaves no file",
                  "\(unique)\n\(fallback)\n\(left.count) files left")
        // Once the write can succeed, the first name is free again.
        let saved = try RExternalScript.saveUnique(script, name: "Sheet1 Worksheet", date: date, in: place)
        try check(saved.lastPathComponent == "Sheet1 Worksheet 2026-11-21 101530.R" && text(saved) == script,
                  "after a failed save, the next import takes the first name")
    }

    // MARK: Process identity

    static func spawnSleep() throws -> Process {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["60"]
        try process.run(); return process
    }
    static func stop(_ process: Process) { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    /// The identity of a process that has since ended.
    static func endedProcess() throws -> RProcessIdentity {
        let process = try spawnSleep()
        guard let identity = RProcessIdentity.of(process.processIdentifier) else { throw Failure(description: "no identity for a child process") }
        stop(process)
        return identity
    }

    static func processIdentity() throws {
        let me = RProcessIdentity.current!
        try check(me.pid == getpid() && me.isRunning && !RProcessIdentity(pid: me.pid, started: me.started + 1).isRunning,
                  "a process is known by its id and start time, so a reused id does not match")
        let child = try spawnSleep()
        defer { stop(child) }
        let identity = RProcessIdentity.of(child.processIdentifier)
        try check(identity?.isRunning == true && RProcessIdentity.anyRunning(named: "sleep") && !RProcessIdentity.anyRunning(named: "no-such-statsdirect-process"),
                  "a running child is found by its identity and by its executable's name")
        stop(child)
        try check(identity?.isRunning == false && RProcessIdentity.of(1) == nil,
                  "an ended process, or another user's process, is not taken for the one recorded")
    }

    // MARK: R.app launch folders (6.2, at quit and at start)

    @MainActor static func launchRecords(work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let ended = try endedProcess(), me = RProcessIdentity.current!
        let reused = RProcessIdentity(pid: me.pid, started: me.started + 1)
        // Another StatsDirect that is still running: a live process that is not this one.
        let other = try spawnSleep()
        defer { stop(other) }
        guard let otherHost = RProcessIdentity.of(other.processIdentifier) else { throw Failure(description: "no identity for a child process") }
        func launch(in parent: URL, named name: String? = nil, app: RProcessIdentity?, host: RProcessIdentity?) throws -> RExternalSession {
            let session = try RExternalSession(data: Data("x <- 1\n".utf8), name: "Sheet1 Worksheet.R",
                                               directory: name.map { parent.appendingPathComponent($0, isDirectory: true) } ?? RExternalScript.launchFolder(in: parent))
            var record = RExternalLaunchRecord.read(session.record)!
            record.app = app; record.host = host
            try record.write(to: session.record)
            try Data("user data".utf8).write(to: session.directory.appendingPathComponent("user.csv"))
            return session
        }
        func untouched(_ session: RExternalSession) -> Bool {
            exists(session.script) && exists(session.profile) && exists(session.record) && exists(session.directory.appendingPathComponent("user.csv"))
        }
        func cleaned(_ session: RExternalSession) -> Bool {
            !exists(session.script) && !exists(session.profile) && !exists(session.record)
                && exists(session.directory.appendingPathComponent("user.csv")) && exists(session.directory)
        }
        let endedApp = try launch(in: root, app: ended, host: me)
        let runningApp = try launch(in: root, app: me, host: nil)
        let reusedApp = try launch(in: root, app: reused, host: nil)
        let starting = try launch(in: root, app: nil, host: me)
        let unrecorded = try launch(in: root, app: nil, host: ended)
        // Another running StatsDirect's launches are its own: one whose R.app has ended, and one still starting.
        let otherEnded = try launch(in: root, app: ended, host: otherHost)
        let otherStarting = try launch(in: root, app: nil, host: otherHost)
        let session = try folder(root.appendingPathComponent("Session-" + UUID().uuidString, isDirectory: true))
        let inSession = try launch(in: session, app: ended, host: nil)
        let tooDeep = try launch(in: try folder(session.appendingPathComponent("deeper", isDirectory: true)), app: ended, host: nil)
        let retained = try launch(in: root, named: "External R-retained", app: ended, host: nil)
        let lowercase = try launch(in: root, named: "External R-" + UUID().uuidString.lowercased(), app: ended, host: nil)
        // A folder without a record (an older version's, or RStudio's) is never touched.
        let unknown = try folder(RExternalScript.launchFolder(in: root))
        try Data("x <- 1\n".utf8).write(to: unknown.appendingPathComponent("Sheet1 Worksheet.R"))
        try Data("x".utf8).write(to: unknown.appendingPathComponent("startup.R"))
        // Nor is one whose record has the shape this branch's earlier builds wrote, before each file had a digest.
        let earlier = try launch(in: root, app: ended, host: nil)
        try Data(#"{"files":["startup.R"],"script":"Sheet1 Worksheet.R","scriptSHA256":"0"}"#.utf8).write(to: earlier.record)
        // A record that names files outside its folder, a folder, or itself removes only the plain files it names.
        let hostile = try launch(in: root, app: ended, host: nil)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        _ = try folder(hostile.directory.appendingPathComponent("sub", isDirectory: true))
        try Data("inner".utf8).write(to: hostile.directory.appendingPathComponent("sub/inner.txt"))
        var hostileRecord = RExternalLaunchRecord.read(hostile.record)!
        let outsideDigest = RExternalLaunchRecord.digest(Data("outside".utf8)), innerDigest = RExternalLaunchRecord.digest(Data("inner".utf8))
        for (name, digest) in ["../outside.txt": outsideDigest, outside.path: outsideDigest, "sub/inner.txt": innerDigest, "sub": "", ".": "",
                               "..": "", "": "", recordName: "", "user.csv\0": RExternalLaunchRecord.digest(Data("user data".utf8))] {
            hostileRecord.files[name] = digest
        }
        try hostileRecord.write(to: hostile.record)
        // A script copy the user changed is kept, and so is a start-up file the user replaced; one replaced by a link to an
        // identical file loses only the link; a file the record does not list (the user's own startup.R) stays.
        let changed = try launch(in: root, app: ended, host: nil)
        try Data("x <- 2\n".utf8).write(to: changed.script)
        let replaced = try launch(in: root, app: ended, host: nil)
        try Data("# my own\n".utf8).write(to: replaced.profile)
        try Data("# my own set-up\n".utf8).write(to: replaced.directory.appendingPathComponent("startup.R"))
        let linked = try launch(in: root, app: ended, host: nil)
        let target = root.appendingPathComponent("target.R")
        try Data("x <- 1\n".utf8).write(to: target)
        try fm.removeItem(at: linked.script); try fm.createSymbolicLink(at: linked.script, withDestinationURL: target)
        // A linked launch folder is not followed, and a corrupt record is left alone.
        let elsewhere = try launch(in: try folder(work.appendingPathComponent("elsewhere", isDirectory: true)), app: ended, host: nil)
        let link = root.appendingPathComponent("External R-" + UUID().uuidString)
        try fm.createSymbolicLink(at: link, withDestinationURL: elsewhere.directory)
        let corrupt = try launch(in: root, app: ended, host: nil)
        try Data("{not json".utf8).write(to: corrupt.record)
        // A listed file that cannot be read now (here a script copy with no permissions) may still be what the launch wrote:
        // it stays, and so does the record, so that a later run, once it can read the file, finishes the clean-up.
        let unreadable = try launch(in: root, app: ended, host: nil)
        guard chmod(unreadable.script.path, 0) == 0, fm.contents(atPath: unreadable.script.path) == nil else {
            throw Failure(description: "the test could not make a script copy unreadable")
        }
        defer { chmod(unreadable.script.path, 0o644) }

        // Any R.app might be the one a launch without a recorded R.app is using: keep it.
        let removedWhileRApp = RExternalScript.removeLeftovers(in: [root, root], rAppRunning: { true })
        try check(cleaned(endedApp) && cleaned(reusedApp) && cleaned(inSession) && untouched(runningApp) && untouched(starting) && untouched(unrecorded),
                  "at quit or start, a launch whose R.app has ended (or whose id another process now has) loses its files; a running or starting one keeps them")
        try check(untouched(otherEnded) && untouched(otherStarting),
                  "another StatsDirect that is still running keeps its launches, both one whose R.app has ended and one still starting")
        try check(untouched(tooDeep) && untouched(retained) && untouched(lowercase) && exists(unknown.appendingPathComponent("Sheet1 Worksheet.R"))
                  && exists(unknown.appendingPathComponent("startup.R")) && untouched(elsewhere) && exists(link) && untouched(corrupt) && untouched(earlier),
                  "only External R-<UUID> folders with a valid record, in R Sessions or one folder below, are looked at; links are not followed")
        try check(cleaned(hostile) && exists(outside) && exists(hostile.directory.appendingPathComponent("sub/inner.txt")),
                  "a record cannot remove anything but plain files in its own folder")
        try check(text(changed.script) == "x <- 2\n" && !exists(changed.profile) && !exists(changed.record),
                  "a script copy the user changed stays; the start-up file and the record go")
        try check(text(replaced.profile) == "# my own\n" && text(replaced.directory.appendingPathComponent("startup.R")) == "# my own set-up\n"
                  && !exists(replaced.script) && !exists(replaced.record),
                  "a start-up file the user replaced stays, as does their own startup.R; the unchanged copy and the record go")
        try check(!exists(linked.script) && exists(target) && !exists(linked.profile), "a linked script copy loses only its link")
        try check(paths(removedWhileRApp).count == removedWhileRApp.count, "a root named twice is cleaned once")
        try check(exists(unreadable.script) && exists(unreadable.record) && !exists(unreadable.profile)
                  && RExternalLaunchRecord.read(unreadable.record)?.files.count == 2,
                  "a listed file that cannot be read stays, and keeps the launch record, while the rest goes")

        // Once no R.app runs, an unrecorded launch whose StatsDirect has gone loses its files too.
        let removedLater = RExternalScript.removeLeftovers(in: [root], rAppRunning: { false })
        try check(cleaned(unrecorded) && untouched(starting) && untouched(runningApp) && untouched(otherEnded) && untouched(otherStarting)
                  && paths(removedLater) == paths([unrecorded.script, unrecorded.profile, unrecorded.record]),
                  "an unrecorded launch goes once its StatsDirect has gone and no R.app runs; another running StatsDirect's launch still stays",
                  removedLater.map(\.path).joined(separator: "\n"))

        // This test process, too, is another running StatsDirect to a clean-up that is not its own: its launch whose R.app
        // has ended, and its launch still starting, stay until it cleans up itself.
        let mine = try launch(in: root, app: ended, host: me)
        let removedByAnother = RExternalScript.removeLeftovers(in: [root], this: reused, rAppRunning: { false })
        try check(removedByAnother.isEmpty && untouched(mine) && untouched(starting),
                  "another StatsDirect's clean-up leaves this running one's launches alone, ended or starting", removedByAnother.map(\.path).joined(separator: "\n"))
        let removedByMine = RExternalScript.removeLeftovers(in: [root], rAppRunning: { false })
        try check(cleaned(mine) && untouched(starting) && paths(removedByMine) == paths([mine.script, mine.profile, mine.record]),
                  "this StatsDirect's own clean-up removes its launch whose R.app has ended, and keeps the one still starting",
                  removedByMine.map(\.path).joined(separator: "\n"))

        // When that other StatsDirect has gone, its launches are leftovers like any other.
        stop(other)
        let removedAfterOther = RExternalScript.removeLeftovers(in: [root], rAppRunning: { false })
        try check(cleaned(otherEnded) && cleaned(otherStarting) && untouched(starting) && untouched(runningApp)
                  && paths(removedAfterOther) == paths([otherEnded.script, otherEnded.profile, otherEnded.record,
                                                         otherStarting.script, otherStarting.profile, otherStarting.record]),
                  "once the other StatsDirect has gone, and no R.app runs, its launches lose their files", removedAfterOther.map(\.path).joined(separator: "\n"))

        // The unreadable copy was kept through every run so far. Once it can be read, and is still what the launch wrote, it
        // goes, and the record with it.
        try check(exists(unreadable.script) && exists(unreadable.record), "a file that still cannot be read keeps its record run after run")
        guard chmod(unreadable.script.path, 0o644) == 0 else { throw Failure(description: "the test could not make the script copy readable again") }
        let removedOnceReadable = RExternalScript.removeLeftovers(in: [root], rAppRunning: { false })
        try check(paths(removedOnceReadable) == paths([unreadable.script, unreadable.record]) && !exists(unreadable.script) && !exists(unreadable.record)
                  && exists(unreadable.directory.appendingPathComponent("user.csv")),
                  "once it can be read, the copy and its record go", removedOnceReadable.map(\.path).joined(separator: "\n"))
    }

    // MARK: Console private folders (6.2, at start)

    static func privateFolders(work: URL) throws {
        let temporary = try folder(work.appendingPathComponent("T", isDirectory: true))
        let ended = try endedProcess(), me = RProcessIdentity.current!
        let other = try spawnSleep()
        defer { stop(other) }
        guard let otherHost = RProcessIdentity.of(other.processIdentifier) else { throw Failure(description: "no identity for a child process") }
        func make(_ name: String, host: RProcessIdentity? = nil, worker: RProcessIdentity?, record: Bool = true, raw: Data? = nil, hoursOld: Double = 0) throws -> URL {
            let folder = temporary.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("Rtmp/RtmpABCDEF", isDirectory: true), withIntermediateDirectories: true)
            try Data("{\"type\":\"commandFinished\",\"source\":\"secret <- 'data'\"}\n".utf8).write(to: folder.appendingPathComponent("events.ndjson"))
            try Data("r temp".utf8).write(to: folder.appendingPathComponent("Rtmp/RtmpABCDEF/file1"))
            guard mkfifo(folder.appendingPathComponent("input").path, 0o600) == 0 else { throw Failure(description: "mkfifo failed") }
            let file = folder.appendingPathComponent(RConsoleSession.processRecordName)
            if record { try JSONEncoder().encode(RConsolePrivateFolderRecord(host: host, worker: worker)).write(to: file) }
            if let raw { try raw.write(to: file) }
            if hoursOld > 0 { try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-hoursOld * 3600)], ofItemAtPath: folder.path) }
            return folder
        }
        let prefix = RConsoleSession.privateFolderPrefix
        func named() -> String { prefix + UUID().uuidString }
        let endedWorker = try make(named(), host: ended, worker: ended)
        let runningWorker = try make(named(), host: ended, worker: me)
        let reusedWorker = try make(named(), host: ended, worker: RProcessIdentity(pid: me.pid, started: me.started + 1))
        // While the StatsDirect that made a folder runs, the folder is its own: another one's, or this one's.
        let otherHostEnded = try make(named(), host: otherHost, worker: ended, hoursOld: 2)
        let otherHostStarting = try make(named(), host: otherHost, worker: nil, hoursOld: 2)
        let thisHostEnded = try make(named(), host: me, worker: ended, hoursOld: 2)
        let thisHostStarting = try make(named(), host: me, worker: nil, hoursOld: 2)
        // Its StatsDirect ended before recording a worker, which may still be running.
        let endedHostStarting = try make(named(), host: ended, worker: nil)
        // Without a record (an older version's folder), or with a corrupt one, age decides as well.
        let young = try make(named(), worker: nil, record: false)
        let old = try make(named(), worker: nil, record: false, hoursOld: 2)
        let corrupt = try make(named(), worker: nil, record: false, raw: Data("{\"host\":".utf8), hoursOld: 2)
        let others = try [prefix + UUID().uuidString.lowercased(), prefix + "not-a-uuid", "StatsDirect-RConsoleX-" + UUID().uuidString,
                          "Other-" + UUID().uuidString].map { try make($0, host: ended, worker: ended, hoursOld: 2) }
        let elsewhere = try make("elsewhere", host: ended, worker: ended, hoursOld: 2)
        let link = temporary.appendingPathComponent(named())
        try fm.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        let file = temporary.appendingPathComponent(named())
        try Data("a file".utf8).write(to: file)
        let kept = [otherHostEnded, otherHostStarting, thisHostEnded, thisHostStarting]

        try check(RConsoleSession.removeLeftoverPrivateFolders(in: temporary, owner: getuid() + 1, anyWorkerRunning: { false }).isEmpty
                  && exists(endedWorker), "another user's folders are never removed")
        let whileWorking = RConsoleSession.removeLeftoverPrivateFolders(in: temporary, anyWorkerRunning: { true })
        try check(paths(whileWorking) == paths([endedWorker, reusedWorker]) && exists(runningWorker) && exists(endedHostStarting)
                  && exists(young) && exists(old) && exists(corrupt) && kept.allSatisfy(exists),
                  "a folder whose StatsDirect and worker have both gone is removed, whole; a running worker's folder stays; folders without a worker stay while any worker runs",
                  whileWorking.map(\.path).joined(separator: "\n"))
        try check(kept.allSatisfy(exists),
                  "a folder whose StatsDirect still runs stays, whether that is another StatsDirect or this one, with its worker ended or not yet recorded")
        let afterwards = RConsoleSession.removeLeftoverPrivateFolders(in: temporary, anyWorkerRunning: { false })
        try check(paths(afterwards) == paths([endedHostStarting, old, corrupt]) && exists(young) && exists(runningWorker) && kept.allSatisfy(exists),
                  "when no worker runs, a folder whose StatsDirect ended before its worker was recorded goes, and so does an old folder without a record; a young one stays",
                  afterwards.map(\.path).joined(separator: "\n"))
        try check(others.allSatisfy(exists) && exists(link) && exists(elsewhere.appendingPathComponent("events.ndjson")) && exists(file),
                  "only real StatsDirect-RConsole-<UUID> folders are looked at: not other names, links or files")
        stop(other)
        let afterOther = RConsoleSession.removeLeftoverPrivateFolders(in: temporary, anyWorkerRunning: { false })
        try check(paths(afterOther) == paths([otherHostEnded, otherHostStarting]) && exists(thisHostEnded) && exists(thisHostStarting),
                  "once the other StatsDirect has gone, its folders go; this one's stay while it runs", afterOther.map(\.path).joined(separator: "\n"))
    }

    // MARK: A console worker whose host is killed

    /// The killed host: a real console session that has run a command with data, then waits to be killed.
    @MainActor static func host(worker: URL, bootstrap: URL, sessions: URL, temporary: URL, info: URL) async throws {
        let session = RConsoleSession(worker: worker, bootstrap: bootstrap, workingRoot: sessions, temporaryRoot: temporary)
        var notices: [String] = []
        session.onEvent = { event in if event["type"] as? String == "notice", let text = event["text"] as? String { notices.append(text) } }
        func wait(_ what: String, _ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(90)
            while !condition() {
                // start() leaves the session "starting"; "stopped" afterwards means R or the worker failed.
                guard Date() < deadline, session.state != "stopped" else {
                    throw Failure(description: "the host's console did not reach \(what): " + notices.joined(separator: " | "))
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        session.start()
        try await wait("ready") { session.state == "ready" }
        guard session.submit(source: "secret <- 'worksheet data 12345'; writeLines(c(Sys.getpid(), tempdir()), 'host-info.txt')") else {
            throw Failure(description: "the host's command was refused")
        }
        let written = session.workingDirectory!.appendingPathComponent("host-info.txt")
        try await wait("its command") { session.state == "ready" && exists(written) }
        let lines = try String(contentsOf: written, encoding: .utf8).split(separator: "\n").map(String.init)
        try JSONSerialization.data(withJSONObject: ["pid": Int(lines[0]) ?? 0, "temporary": lines[1], "directory": session.workingDirectory!.path])
            .write(to: info, options: .atomic)
        while true { try await Task.sleep(nanoseconds: 1_000_000_000) }
    }

    static func crashedHost(work: URL, worker: URL, bootstrap: URL) async throws {
        // The host's own temporary root, inside the user's, so that only this test's folders are ever looked at.
        // R refuses a temporary folder whose path has a space, as the work folder's may.
        let temporary = try folder(fm.temporaryDirectory.appendingPathComponent("statsdirect-r-delivery-" + UUID().uuidString, isDirectory: true))
        defer { try? fm.removeItem(at: temporary) }
        guard !temporary.path.contains(" ") else { throw Failure(description: "$TMPDIR must not contain a space: " + temporary.path) }
        let sessions = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let info = work.appendingPathComponent("host.json"), log = work.appendingPathComponent("host.log")
        fm.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        let host = Process()
        host.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        host.arguments = ["host", worker.path, bootstrap.path, sessions.path, temporary.path, info.path]
        host.standardOutput = output; host.standardError = output
        try host.run()
        var workerIdentity: RProcessIdentity?
        defer {
            if host.isRunning { kill(host.processIdentifier, SIGKILL); host.waitUntilExit() }
            if let workerIdentity, workerIdentity.isRunning { kill(workerIdentity.pid, SIGKILL) }
        }
        let deadline = Date().addingTimeInterval(120)
        while !exists(info) {
            guard host.isRunning, Date() < deadline else {
                throw Failure(description: "the host did not start its console:\n" + (text(log) ?? ""))
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let details = try JSONSerialization.jsonObject(with: Data(contentsOf: info)) as! [String: Any]
        let pid = Int32(details["pid"] as! Int), directory = URL(fileURLWithPath: details["directory"] as! String)
        let ipc = URL(fileURLWithPath: details["temporary"] as! String).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let record = try? JSONDecoder().decode(RConsolePrivateFolderRecord.self,
                                               from: Data(contentsOf: ipc.appendingPathComponent(RConsoleSession.processRecordName)))
        workerIdentity = record?.worker
        try check(ipc.deletingLastPathComponent().path == temporary.resolvingSymlinksInPath().path
                  && ipc.lastPathComponent.hasPrefix(RConsoleSession.privateFolderPrefix) && record?.worker?.pid == pid && record?.worker?.isRunning == true
                  && record?.host?.pid == host.processIdentifier && record?.host?.isRunning == true,
                  "a console session records its StatsDirect's identity and its worker's in its private folder", ipc.path)
        let events = { text(ipc.appendingPathComponent("events.ndjson")) ?? "" }
        try check(events().contains("worksheet data 12345"), "the private event log holds the command's data, which is why a leftover matters")
        try check(RConsoleSession.removeLeftoverPrivateFolders(in: temporary).isEmpty && exists(ipc),
                  "start-up keeps the private folder of a StatsDirect and worker that are still running")

        kill(host.processIdentifier, SIGKILL); host.waitUntilExit()
        let gone = Date().addingTimeInterval(20)
        while record?.worker?.isRunning == true && Date() < gone { try await Task.sleep(nanoseconds: 50_000_000) }
        try check(record?.worker?.isRunning == false && record?.host?.isRunning == false && exists(ipc) && events().contains("worksheet data 12345"),
                  "when its host is killed, the worker ends and its private folder, with the data, is left behind")
        let removed = RConsoleSession.removeLeftoverPrivateFolders(in: temporary)
        try check(removed.map(\.lastPathComponent) == [ipc.lastPathComponent] && !exists(ipc)
                  && exists(directory.appendingPathComponent("host-info.txt")),
                  "the next start removes that private folder, and leaves the session's own folder and files")
    }
}
