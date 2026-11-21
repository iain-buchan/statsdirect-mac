import Foundation
import Darwin

/// R+ delivery (rules 6.1 and 6.2 of the worksheet R rules), checked without launching R.app, RStudio or StatsDirect:
/// - under Rscript, the generated startup.R runs the user's own profile and .First as R would, leaves R_PROFILE_USER
///   unset for child processes, and removes its script copy (unless changed), itself and its launch record when R ends;
/// - R+ file names, and the leftover clean-up of R.app launch folders and of console private folders, on fake trees;
/// - a real console worker whose host is killed leaves its private folder, which start-up removes once it has gone.
/// Usage: r-delivery-driver Rscript work-folder RConsoleWorker console-bootstrap.R
///   (or, as the killed host: r-delivery-driver host RConsoleWorker console-bootstrap.R sessions-folder temporary-folder info-file)
@main struct RDeliveryDriver {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static let fm = FileManager.default

    @MainActor static func main() async {
        do {
            let arguments = CommandLine.arguments
            if arguments.count == 7, arguments[1] == "host" {
                try await host(worker: URL(fileURLWithPath: arguments[2]), bootstrap: URL(fileURLWithPath: arguments[3]),
                               sessions: URL(fileURLWithPath: arguments[4]), temporary: URL(fileURLWithPath: arguments[5]),
                               info: URL(fileURLWithPath: arguments[6]))
                return
            }
            guard arguments.count == 5 else { throw Failure(description: "Usage: r-delivery-driver Rscript work-folder RConsoleWorker console-bootstrap.R") }
            let rscript = arguments[1], work = URL(fileURLWithPath: arguments[2], isDirectory: true)
            try startupProfile(rscript: rscript, work: work.appendingPathComponent("startup", isDirectory: true))
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

    struct RRun { let status: Int32; let output: String }
    /// Rscript as R.app would start R: HOME is the given folder, and R_PROFILE_USER names StatsDirect's startup.R.
    static func runR(_ rscript: String, _ file: URL, in directory: URL, home: URL, profile: URL) throws -> RRun {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: rscript)
        process.arguments = [file.path]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        for key in ["R_PROFILE_USER", "R_ENVIRON_USER", "R_LIBS_USER", "R_DEFAULT_PACKAGES", "R_PROFILE"] { environment[key] = nil }
        environment["HOME"] = home.path; environment["LC_ALL"] = "en_US.UTF-8"
        environment["R_PROFILE_USER"] = profile.path
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

    // MARK: 6.1 and the R side of 6.2

    static func startupProfile(rscript: String, work: URL) throws {
        // Quotes, a backslash, accented letters and a bidirectional-text control in the folder R works in.
        let root = try folder(work.appendingPathComponent("R Sessions ' \" \\ café \u{202E}x", isDirectory: true))
        let home = try folder(work.appendingPathComponent("home", isDirectory: true))
        let start = try folder(work.appendingPathComponent("start", isDirectory: true))
        try #"""
        cat("USER_PROFILE_RAN\n")
        options(statsdirect.test.profile = "home")
        .First <- function() { cat("USER_FIRST_RAN\n"); options(statsdirect.test.first = "home") }

        """#.write(to: home.appendingPathComponent(".Rprofile"), atomically: true, encoding: .utf8)
        func session(_ name: String = "Sheet1 café Worksheet.R") throws -> RExternalSession {
            try RExternalSession(data: Data(worksheetScript.utf8), name: name, directory: RExternalScript.launchFolder(in: root))
        }
        func checks(_ name: String, _ lines: String) throws -> URL {
            let file = work.appendingPathComponent(name + ".R")
            try (lines + "\ncat(\"PARENT_CHECKS_PASSED\\n\")\n").write(to: file, atomically: true, encoding: .utf8)
            return file
        }

        // The launch record comes with the files, naming this StatsDirect and no R.app yet.
        let main = try session()
        let record = RExternalLaunchRecord.read(main.record)
        try check(exists(main.script) && exists(main.profile) && record == RExternalLaunchRecord(
                    script: main.script.lastPathComponent, scriptSHA256: RExternalLaunchRecord.digest(Data(worksheetScript.utf8)),
                    files: ["startup.R"], host: RProcessIdentity.current, app: nil),
                  "an R.app launch writes its script copy, startup.R and a launch record naming its StatsDirect", String(describing: record))
        let profileText = try String(contentsOf: main.profile, encoding: .utf8)
        try check(!profileText.unicodeScalars.contains { $0.value == 0x202E } && profileText.contains("\\u202e"),
                  "startup.R writes a bidirectional-text control in a path as an escape, which R accepts")

        // The user's profile and .First run as R would, and a child Rscript does not inherit StatsDirect's profile.
        let child = work.appendingPathComponent("child.R")
        try #"cat(paste("CHILD_STATE", Sys.getenv("R_PROFILE_USER", unset = "UNSET"), exists("worksheet_data"), exists(".First"), getOption("statsdirect.test.profile", "none")), "\n", sep = "")"#
            .write(to: child, atomically: true, encoding: .utf8)
        let first = try runR(rscript, try checks("main", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "home"), identical(getOption("statsdirect.test.first"), "home"))
            stopifnot(is.na(Sys.getenv("R_PROFILE_USER", unset = NA)), \(expectedData))
            stopifnot(identical(normalizePath(getwd()), normalizePath(\(rString(main.directory.path)))))
            child <- system2(file.path(R.home("bin"), "Rscript"), shQuote(\(rString(child.path))), stdout = TRUE, stderr = TRUE)
            writeLines(paste("CHILD:", child))
            stopifnot("CHILD_STATE UNSET FALSE TRUE home" %in% child, !any(grepl("StatsDirect", child)))
            """), in: start, home: home, profile: main.profile)
        let output = first.output
        func at(_ text: String) -> Int { output.range(of: text).map { output.distance(from: output.startIndex, to: $0.lowerBound) } ?? -1 }
        try check(first.status == 0 && output.contains("PARENT_CHECKS_PASSED"),
                  "R.app's R runs the user's ~/.Rprofile and .First, then the import; R_PROFILE_USER is unset and a child Rscript runs only the user's own profile", output)
        try check(at("USER_PROFILE_RAN") >= 0 && at("USER_PROFILE_RAN") < at("USER_FIRST_RAN") && at("USER_FIRST_RAN") < at("StatsDirect: running Sheet1 café Worksheet.R")
                  && output.components(separatedBy: "StatsDirect: running ").count == 2 && output.contains("'data.frame':\t2 obs. of  1 variable:"),
                  "the profile, then the user's .First, then the script once, with its str() output", output)
        try check(!exists(main.script) && !exists(main.profile) && !exists(main.record)
                  && exists(main.directory.appendingPathComponent("user-output.txt")) && exists(main.directory),
                  "when R ends, the script copy, startup.R and the launch record go; R's working folder and the user's files stay")

        // ./.Rprofile in the folder R starts in is used instead of ~/.Rprofile, as R would.
        let local = try folder(work.appendingPathComponent("start with profile", isDirectory: true))
        try "options(statsdirect.test.profile = \"here\")\n".write(to: local.appendingPathComponent(".Rprofile"), atomically: true, encoding: .utf8)
        let here = try session()
        let second = try runR(rscript, try checks("here", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "here"), is.null(getOption("statsdirect.test.first")), \(expectedData))
            """), in: local, home: home, profile: here.profile)
        try check(second.status == 0 && second.output.contains("PARENT_CHECKS_PASSED") && !second.output.contains("USER_PROFILE_RAN"),
                  "./.Rprofile where R starts takes the place of ~/.Rprofile", second.output)

        // With no profile at all, nothing is reported and the import runs.
        let bare = try session(), empty = try folder(work.appendingPathComponent("empty home", isDirectory: true))
        let third = try runR(rscript, try checks("bare", "stopifnot(is.null(getOption(\"statsdirect.test.profile\")), \(expectedData))"),
                             in: empty, home: empty, profile: bare.profile)
        try check(third.status == 0 && third.output.contains("PARENT_CHECKS_PASSED") && !third.output.contains("Error"),
                  "without a user profile the import runs and nothing else is reported", third.output)

        // An error in the user's profile stops the rest of it, as in R; an error in their .First is reported; the
        // import still runs.
        let failing = try folder(work.appendingPathComponent("failing home", isDirectory: true))
        try #"""
        options(statsdirect.test.profile = "partial")
        .First <- function() stop("user first failed")
        stop("user profile failed")
        options(statsdirect.test.after = TRUE)

        """#.write(to: failing.appendingPathComponent(".Rprofile"), atomically: true, encoding: .utf8)
        let broken = try session()
        let fourth = try runR(rscript, try checks("broken", """
            stopifnot(identical(getOption("statsdirect.test.profile"), "partial"), is.null(getOption("statsdirect.test.after")), \(expectedData))
            """), in: start, home: failing, profile: broken.profile)
        try check(fourth.status == 0 && fourth.output.contains("PARENT_CHECKS_PASSED") && fourth.output.contains("user profile failed")
                  && fourth.output.contains("user first failed"),
                  "errors in the user's profile and .First are reported and do not stop the import", fourth.output)

        // A script copy the user saved changes to (in R.app's editor) is theirs: only startup.R and the record go.
        let edited = try session()
        let fifth = try runR(rscript, try checks("edited", "cat(\"# my own edit\\n\", file = \(rString(edited.script.path)), append = TRUE)"),
                             in: start, home: home, profile: edited.profile)
        try check(fifth.status == 0 && (try? String(contentsOf: edited.script, encoding: .utf8)) == worksheetScript + "# my own edit\n"
                  && !exists(edited.profile) && !exists(edited.record),
                  "a script copy saved with changes stays when R ends; startup.R and the launch record go", fifth.output)

        // Quitting with the workspace saved keeps it, and the user's files, in R's folder; the copies still go.
        let saving = try session()
        let sixth = try runR(rscript, try checks("saving", "writeLines('kept', 'user-file.txt'); cat('PARENT_CHECKS_PASSED\\n'); q('yes')"),
                             in: start, home: home, profile: saving.profile)
        try check(sixth.status == 0 && sixth.output.contains("PARENT_CHECKS_PASSED") && exists(saving.directory.appendingPathComponent(".RData"))
                  && exists(saving.directory.appendingPathComponent("user-file.txt")) && !exists(saving.script) && !exists(saving.profile)
                  && !exists(saving.record),
                  "q(\"yes\") saves the workspace in R's folder, which stays with the user's files, and the copies still go", sixth.output)

        // recordLaunch adds R.app's process; it never brings back a record R has already removed. discard removes all
        // three files when R.app did not start, and keeps the folder.
        let recorded = try session()
        let me = RProcessIdentity.current!
        recorded.recordLaunch(me)
        try check(RExternalLaunchRecord.read(recorded.record)?.app == me, "a launched R.app's process is added to its launch record")
        try fm.removeItem(at: recorded.record); recorded.recordLaunch(me)
        try check(!exists(recorded.record), "a launch record that R removed is not written again")
        recorded.discard()
        try check(!exists(recorded.script) && !exists(recorded.profile) && exists(recorded.directory),
                  "a launch whose R.app did not start leaves no files, and its folder")
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
                  && (try String(contentsOf: first, encoding: .utf8)) == "first <- 1\n"
                  && (try String(contentsOf: second, encoding: .utf8)) == "second <- 2\n"
                  && (try String(contentsOf: third, encoding: .utf8)) == "third <- 3\n",
                  "RStudio gets one new file per import, named by date and time, numbered on a clash, never replacing another",
                  [first, second, third, console].map(\.lastPathComponent).joined(separator: "\n"))
        let saved = try RExternalScript.save("old <- 1\n", name: "Sheet1 Worksheet", in: scripts)
        let again = try RExternalScript.save("new <- 2\n", name: "Sheet1 Worksheet", in: scripts)
        try check(saved == again && saved.lastPathComponent == "Sheet1 Worksheet.R" && (try String(contentsOf: again, encoding: .utf8)) == "new <- 2\n",
                  "without RStudio or R.app the script is saved in R Scripts under its own name, as before")
    }

    // MARK: Process identity

    static func spawnSleep() throws -> Process {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]
        try process.run(); return process
    }
    /// The identity of a process that has since ended.
    static func endedProcess() throws -> RProcessIdentity {
        let process = try spawnSleep()
        guard let identity = RProcessIdentity.of(process.processIdentifier) else { throw Failure(description: "no identity for a child process") }
        process.terminate(); process.waitUntilExit()
        return identity
    }

    static func processIdentity() throws {
        let me = RProcessIdentity.current!
        try check(me.pid == getpid() && me.isRunning && !RProcessIdentity(pid: me.pid, started: me.started + 1).isRunning,
                  "a process is known by its id and start time, so a reused id does not match")
        let child = try spawnSleep()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let identity = RProcessIdentity.of(child.processIdentifier)
        try check(identity?.isRunning == true && RProcessIdentity.anyRunning(named: "sleep") && !RProcessIdentity.anyRunning(named: "no-such-statsdirect-process"),
                  "a running child is found by its identity and by its executable's name")
        child.terminate(); child.waitUntilExit()
        try check(identity?.isRunning == false && RProcessIdentity.of(1) == nil,
                  "an ended process, or another user's process, is not taken for the one recorded")
    }

    // MARK: R.app launch folders (6.2, at quit and at start)

    @MainActor static func launchRecords(work: URL) throws {
        let root = try folder(work.appendingPathComponent("R Sessions", isDirectory: true))
        let ended = try endedProcess(), me = RProcessIdentity.current!
        let reused = RProcessIdentity(pid: me.pid, started: me.started + 1)
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
        let session = try folder(root.appendingPathComponent("Session-" + UUID().uuidString, isDirectory: true))
        let inSession = try launch(in: session, app: ended, host: nil)
        let tooDeep = try launch(in: try folder(session.appendingPathComponent("deeper", isDirectory: true)), app: ended, host: nil)
        let retained = try launch(in: root, named: "External R-retained", app: ended, host: nil)
        let lowercase = try launch(in: root, named: "External R-" + UUID().uuidString.lowercased(), app: ended, host: nil)
        // A folder without a record (an older version's, or RStudio's) is never touched.
        let unknown = try folder(RExternalScript.launchFolder(in: root))
        try Data("x <- 1\n".utf8).write(to: unknown.appendingPathComponent("Sheet1 Worksheet.R"))
        try Data("x".utf8).write(to: unknown.appendingPathComponent("startup.R"))
        // A record that names files outside its folder, a folder, or itself removes only the plain files it names.
        let hostile = try launch(in: root, app: ended, host: nil)
        try Data("outside".utf8).write(to: root.appendingPathComponent("outside.txt"))
        _ = try folder(hostile.directory.appendingPathComponent("sub", isDirectory: true))
        try Data("inner".utf8).write(to: hostile.directory.appendingPathComponent("sub/inner.txt"))
        var hostileRecord = RExternalLaunchRecord.read(hostile.record)!
        hostileRecord.files = ["startup.R", "../outside.txt", root.appendingPathComponent("outside.txt").path, "sub/inner.txt", "sub", ".", "..", "",
                               RExternalLaunchRecord.fileName, "user.csv\0"]
        try hostileRecord.write(to: hostile.record)
        // A script copy the user changed is kept; one replaced by a link to an identical file loses only the link.
        let changed = try launch(in: root, app: ended, host: nil)
        try Data("x <- 2\n".utf8).write(to: changed.script)
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

        // Any R.app might be the one a launch without a recorded R.app is using: keep it.
        let removedWhileRApp = RExternalScript.removeLeftovers(in: [root, root], rAppRunning: { true })
        try check(cleaned(endedApp) && cleaned(reusedApp) && cleaned(inSession) && untouched(runningApp) && untouched(starting) && untouched(unrecorded),
                  "at quit or start, a launch whose R.app has ended (or whose id another process now has) loses its files; a running or starting one keeps them")
        try check(untouched(tooDeep) && untouched(retained) && untouched(lowercase) && exists(unknown.appendingPathComponent("Sheet1 Worksheet.R"))
                  && exists(unknown.appendingPathComponent("startup.R")) && untouched(elsewhere) && exists(link) && untouched(corrupt),
                  "only External R-<UUID> folders with a valid record, in R Sessions or one folder below, are looked at; links are not followed")
        try check(cleaned(hostile) && exists(root.appendingPathComponent("outside.txt")) && exists(hostile.directory.appendingPathComponent("sub/inner.txt")),
                  "a record cannot remove anything but plain files in its own folder")
        try check(exists(changed.script) && (try String(contentsOf: changed.script, encoding: .utf8)) == "x <- 2\n" && !exists(changed.profile) && !exists(changed.record),
                  "a script copy the user changed stays; startup.R and the record go")
        try check(!exists(linked.script) && exists(target) && !exists(linked.profile), "a linked script copy loses only its link")
        try check(Set(removedWhileRApp.map(\.path)).count == removedWhileRApp.count, "a root named twice is cleaned once")

        // Once no R.app runs, an unrecorded launch whose StatsDirect has gone loses its files too.
        let removedLater = RExternalScript.removeLeftovers(in: [root], rAppRunning: { false })
        try check(cleaned(unrecorded) && untouched(starting) && untouched(runningApp)
                  && Set(removedLater.map(\.path)) == Set([unrecorded.script, unrecorded.profile, unrecorded.record].map(\.path)),
                  "an unrecorded launch goes once its StatsDirect has gone and no R.app runs", removedLater.map(\.path).joined(separator: "\n"))
    }

    // MARK: Console private folders (6.2, at start)

    static func privateFolders(work: URL) throws {
        let temporary = try folder(work.appendingPathComponent("T", isDirectory: true))
        let ended = try endedProcess(), me = RProcessIdentity.current!
        func make(_ name: String, worker: RProcessIdentity?, raw: Data? = nil, hoursOld: Double = 0) throws -> URL {
            let folder = temporary.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("Rtmp/RtmpABCDEF", isDirectory: true), withIntermediateDirectories: true)
            try Data("{\"type\":\"commandFinished\",\"source\":\"secret <- 'data'\"}\n".utf8).write(to: folder.appendingPathComponent("events.ndjson"))
            try Data("r temp".utf8).write(to: folder.appendingPathComponent("Rtmp/RtmpABCDEF/file1"))
            guard mkfifo(folder.appendingPathComponent("input").path, 0o600) == 0 else { throw Failure(description: "mkfifo failed") }
            if let worker { try JSONEncoder().encode(worker).write(to: folder.appendingPathComponent(RConsoleSession.workerRecordName)) }
            if let raw { try raw.write(to: folder.appendingPathComponent(RConsoleSession.workerRecordName)) }
            if hoursOld > 0 { try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-hoursOld * 3600)], ofItemAtPath: folder.path) }
            return folder
        }
        let prefix = RConsoleSession.privateFolderPrefix
        let endedWorker = try make(prefix + UUID().uuidString, worker: ended)
        let runningWorker = try make(prefix + UUID().uuidString, worker: me)
        let reusedWorker = try make(prefix + UUID().uuidString, worker: RProcessIdentity(pid: me.pid, started: me.started + 1))
        let young = try make(prefix + UUID().uuidString, worker: nil)
        let old = try make(prefix + UUID().uuidString, worker: nil, hoursOld: 2)
        let corrupt = try make(prefix + UUID().uuidString, worker: nil, raw: Data("{\"pid\":".utf8), hoursOld: 2)
        let others = try [prefix + UUID().uuidString.lowercased(), prefix + "not-a-uuid", "StatsDirect-RConsoleX-" + UUID().uuidString,
                          "Other-" + UUID().uuidString].map { try make($0, worker: ended, hoursOld: 2) }
        let elsewhere = try make("elsewhere", worker: ended, hoursOld: 2)
        let link = temporary.appendingPathComponent(prefix + UUID().uuidString)
        try fm.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        let file = temporary.appendingPathComponent(prefix + UUID().uuidString)
        try Data("a file".utf8).write(to: file)

        try check(RConsoleSession.removeLeftoverPrivateFolders(in: temporary, owner: getuid() + 1, anyWorkerRunning: { false }).isEmpty
                  && exists(endedWorker), "another user's folders are never removed")
        let whileWorking = RConsoleSession.removeLeftoverPrivateFolders(in: temporary, anyWorkerRunning: { true })
        try check(Set(whileWorking.map(\.path)) == Set([endedWorker, reusedWorker].map(\.path)) && exists(runningWorker) && exists(young) && exists(old) && exists(corrupt),
                  "a folder whose recorded worker has gone is removed, whole; a running worker's folder stays; unrecorded folders stay while any worker runs",
                  whileWorking.map(\.path).joined(separator: "\n"))
        let afterwards = RConsoleSession.removeLeftoverPrivateFolders(in: temporary, anyWorkerRunning: { false })
        try check(Set(afterwards.map(\.path)) == Set([old, corrupt].map(\.path)) && exists(young) && exists(runningWorker),
                  "an unrecorded folder goes when it is old and no worker runs; a young one stays", afterwards.map(\.path).joined(separator: "\n"))
        try check(others.allSatisfy(exists) && exists(link) && exists(elsewhere.appendingPathComponent("events.ndjson")) && exists(file),
                  "only real StatsDirect-RConsole-<UUID> folders are looked at: not other names, links or files")
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
                throw Failure(description: "the host did not start its console:\n" + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let details = try JSONSerialization.jsonObject(with: Data(contentsOf: info)) as! [String: Any]
        let pid = Int32(details["pid"] as! Int), directory = URL(fileURLWithPath: details["directory"] as! String)
        let ipc = URL(fileURLWithPath: details["temporary"] as! String).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let record = try? JSONDecoder().decode(RProcessIdentity.self, from: Data(contentsOf: ipc.appendingPathComponent(RConsoleSession.workerRecordName)))
        workerIdentity = record
        try check(ipc.deletingLastPathComponent().path == temporary.resolvingSymlinksInPath().path
                  && ipc.lastPathComponent.hasPrefix(RConsoleSession.privateFolderPrefix) && record?.pid == pid && record?.isRunning == true,
                  "a console session records its worker's identity in its private folder", ipc.path)
        let events = { (try? String(contentsOf: ipc.appendingPathComponent("events.ndjson"), encoding: .utf8)) ?? "" }
        try check(events().contains("worksheet data 12345"), "the private event log holds the command's data, which is why a leftover matters")
        try check(RConsoleSession.removeLeftoverPrivateFolders(in: temporary).isEmpty && exists(ipc),
                  "start-up keeps the private folder of a worker that is still running")

        kill(host.processIdentifier, SIGKILL); host.waitUntilExit()
        let gone = Date().addingTimeInterval(20)
        while record?.isRunning == true && Date() < gone { try await Task.sleep(nanoseconds: 50_000_000) }
        try check(record?.isRunning == false && exists(ipc) && events().contains("worksheet data 12345"),
                  "when its host is killed, the worker ends and its private folder, with the data, is left behind")
        let removed = RConsoleSession.removeLeftoverPrivateFolders(in: temporary)
        try check(removed.map(\.lastPathComponent) == [ipc.lastPathComponent] && !exists(ipc)
                  && exists(directory.appendingPathComponent("host-info.txt")),
                  "the next start removes that private folder, and leaves the session's own folder and files")
    }
}
