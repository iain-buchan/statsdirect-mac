import Cocoa
import CryptoKit

/// Open in R (the script pane and the console) and R+ (the worksheet) hand a script to RStudio or R.app, keeping data
/// only where R needs it (rule 6.2 of the worksheet R rules):
/// - RStudio opens a script for the user to run when they choose, so R+ gives it one uniquely named file per import in
///   R Scripts: the user's own file, and the only copy.
/// - R.app is started to run a copy in "External R-<UUID>", which is also R's working directory, and shows that copy in
///   its editor. When R ends, startup.R removes the copy (unless the user has saved changes to it) and itself. A launch
///   record beside them lets StatsDirect do the same for an R.app that did not end normally, when StatsDirect quits or
///   next starts. The folder always stays: users save files there.
/// - With neither installed, the script is saved in R Scripts under its own name.
@MainActor enum RExternalScript {
    nonisolated(unsafe) static var opensExternally = true
    static var scriptsFolder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect Viewer/R Scripts", isDirectory: true) }
    nonisolated static let rAppIdentifier = "org.R-project.R"
    private static var rstudio: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.rstudio.RStudio")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.rstudio.desktop")
    }

    /// The file name for a script titled `name`: "/", ":", control characters and bidirectional-text controls as "_",
    /// without surrounding spaces, with ".R" added unless it has an R extension, and short enough for a date and number
    /// to be added.
    nonisolated static func fileName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            let replaced = scalar == "/" || scalar == ":" || scalar.properties.generalCategory == .control
                || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
            scalars.append(replaced ? "_" : scalar)
        }
        var file = String(scalars).trimmingCharacters(in: .whitespaces)
        if file.isEmpty { file = "Script" }
        if (file as NSString).pathExtension.lowercased() != "r" { file += ".R" }
        if file.utf8.count > 200 {
            var stem = (file as NSString).deletingPathExtension
            while stem.utf8.count > 198 { stem.removeLast() }
            file = stem + ".R"
        }
        return file
    }

    /// The script saved in R Scripts under its own name, replacing an earlier save of that name.
    static func save(_ source: String, name: String, in folder: URL? = nil) throws -> URL {
        let folder = folder ?? scriptsFolder
        let url = folder.appendingPathComponent(fileName(name))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A new file in R Scripts for each import, never replacing another: "Sheet1 Worksheet 2026-11-21 101530.R", then
    /// " 2", " 3" and so on when that name is taken.
    static func saveUnique(_ source: String, name: String, date: Date = Date(), in folder: URL? = nil) throws -> URL {
        let folder = folder ?? scriptsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stem = (fileName(name) as NSString).deletingPathExtension + " " + formatter.string(from: date)
        let data = Data(source.utf8)
        for number in 1...1000 {
            let url = folder.appendingPathComponent(stem + (number == 1 ? "" : " \(number)") + ".R")
            do { try data.write(to: url, options: .withoutOverwriting); return url }
            catch { if !FileManager.default.fileExists(atPath: url.path) { throw error } }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Each external window receives immutable source, even when another tab
    /// saves the same title while installation or application launch is pending.
    static func snapshot(_ url: URL, source: String? = nil, workingDirectory: URL) throws -> URL {
        let directory = launchFolder(in: workingDirectory)
        let copy = directory.appendingPathComponent(url.lastPathComponent)
        let data = try source.map { Data($0.utf8) } ?? Data(contentsOf: url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: copy, options: .atomic)
        return copy
    }

    nonisolated static func launchFolder(in workingDirectory: URL) -> URL {
        workingDirectory.appendingPathComponent("External R-" + UUID().uuidString, isDirectory: true)
    }

    /// The script pane's Open in R, which has already saved `url` in R Scripts as the user's file.
    static func launch(_ url: URL, source: String? = nil, workingDirectory: URL, status: @escaping @MainActor (String) -> Void) {
        let workspace = NSWorkspace.shared
        if let rstudio {
            let script: URL
            do { script = try snapshot(url, source: source, workingDirectory: workingDirectory) }
            catch { status("Open in R failed: \(error.localizedDescription)"); return }
            status("Opening script in RStudio…")
            workspace.open([script], withApplicationAt: rstudio, configuration: NSWorkspace.OpenConfiguration()) { application, error in
                let name = application?.localizedName, reason = error?.localizedDescription
                DispatchQueue.main.async {
                    if let reason { status("Open in R failed: \(reason). Your script is saved in R Scripts.") }
                    else { status("Opened \(url.lastPathComponent) in \(name ?? "R")") }
                }
            }
        } else if let r = workspace.urlForApplication(withBundleIdentifier: rAppIdentifier) {
            do {
                let data = try source.map { Data($0.utf8) } ?? Data(contentsOf: url)
                let session = try RExternalSession(data: data, name: url.lastPathComponent, directory: launchFolder(in: workingDirectory))
                start(session, with: r, status: status) { reason in status("Open in R failed: \(reason). Your script is saved in R Scripts.") }
            } catch { status("Open in R failed: \(error.localizedDescription)") }
        } else { status("Saved \(url.lastPathComponent) in R Scripts; install RStudio or R to open it") }
    }

    /// R+ from the worksheet, and Open in R from the console. Returns the script file written, if any.
    @discardableResult static func open(_ source: String, name: String, workingDirectory: URL,
                                         status: @escaping @MainActor (String) -> Void) -> URL? {
        do {
            if let rstudio {
                let file = try saveUnique(source, name: name)
                status("Opening \(file.path) in RStudio…")
                NSWorkspace.shared.open([file], withApplicationAt: rstudio, configuration: NSWorkspace.OpenConfiguration()) { application, error in
                    let name = application?.localizedName, reason = error?.localizedDescription
                    DispatchQueue.main.async {
                        if let reason { status("Open in R failed: \(reason). Your script is saved as \(file.path).") }
                        else { status("Opened \(file.path) in \(name ?? "RStudio")") }
                    }
                }
                return file
            }
            if let r = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rAppIdentifier) {
                let session = try RExternalSession(data: Data(source.utf8), name: fileName(name), directory: launchFolder(in: workingDirectory))
                start(session, with: r, status: status) { reason in
                    // R.app did not start: keep the script for the user, as when no R application is installed.
                    if let saved = try? save(source, name: name) { status("Open in R failed: \(reason). Your script is saved as \(saved.path).") }
                    else { status("Open in R failed: \(reason).") }
                }
                return session.script
            }
            let saved = try save(source, name: name)
            status("Saved \(saved.path); install RStudio or R to open it")
            return saved
        } catch {
            status("Open in R failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Starts a new R.app for this session and records its process in the launch record. `failed` is told why when
    /// R.app did not start; its files are then removed, since nothing will read them.
    static func start(_ session: RExternalSession, with r: URL, status: @escaping @MainActor (String) -> Void,
                      failed: @escaping @MainActor (String) -> Void) {
        status("Starting R and running the script…")
        NSWorkspace.shared.open([session.directory], withApplicationAt: r, configuration: session.configuration()) { application, error in
            let launched = application.flatMap { RProcessIdentity.of($0.processIdentifier) }
            let started = application != nil, name = application?.localizedName, reason = error?.localizedDescription
            DispatchQueue.main.async {
                if let launched { session.recordLaunch(launched) }
                if let reason {
                    if started { status("Open in R failed: \(reason)") } else { session.discard(); failed(reason) }
                    return
                }
                status("Opened \(session.script.lastPathComponent) in \(name ?? "R")")
            }
        }
    }

    /// Removes what R.app sessions that did not end normally left in External R-<UUID> folders, directly in each root or
    /// one folder below it (a console session's or a script pane's folder): the files a launch record lists, the script
    /// copy while it is unchanged, and the record itself. A launch whose R.app is still running, or may be, keeps
    /// everything, and so does a folder without a record. Folders always stay. Returns the files removed.
    @discardableResult nonisolated static func removeLeftovers(
        in roots: [URL], isRunning: (RProcessIdentity) -> Bool = { $0.isRunning },
        rAppRunning: () -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: rAppIdentifier).isEmpty }) -> [URL] {
        let fm = FileManager.default, owner = getuid()
        func isFolder(_ url: URL) -> Bool {
            var info = stat()
            return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == owner
        }
        func isLaunchFolder(_ name: String) -> Bool {
            guard name.hasPrefix("External R-") else { return false }
            let id = String(name.dropFirst("External R-".count))
            return UUID(uuidString: id)?.uuidString == id
        }
        var folders: [URL] = [], roots = roots.map(\.standardizedFileURL), seen = Set<String>()
        roots.removeAll { !seen.insert($0.path).inserted }
        for root in roots where isFolder(root) {
            for name in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
                let entry = root.appendingPathComponent(name, isDirectory: true)
                if isLaunchFolder(name) { folders.append(entry); continue }
                guard isFolder(entry) else { continue }
                for inner in ((try? fm.contentsOfDirectory(atPath: entry.path)) ?? []).sorted() where isLaunchFolder(inner) {
                    folders.append(entry.appendingPathComponent(inner, isDirectory: true))
                }
            }
        }
        var removed: [URL] = [], rApp: Bool?
        for folder in folders where isFolder(folder) {
            let recordURL = folder.appendingPathComponent(RExternalLaunchRecord.fileName)
            guard let launch = RExternalLaunchRecord.read(recordURL) else { continue }
            if let app = launch.app {
                if isRunning(app) { continue }
            } else {
                // Not yet recorded: still starting while the StatsDirect that launched it runs; afterwards, any R.app
                // that is running might be the one using these files.
                if let host = launch.host, isRunning(host) { continue }
                if rApp == nil { rApp = rAppRunning() }
                if rApp == true { continue }
            }
            for name in Set(launch.files + [launch.script]).sorted() where RExternalLaunchRecord.isPlainName(name) {
                let file = folder.appendingPathComponent(name)
                var info = stat()
                guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFLNK else { continue }
                // A script copy the user has saved changes to, in R.app's editor, is the user's file.
                if name == launch.script, fm.contents(atPath: file.path).map(RExternalLaunchRecord.digest) != launch.scriptSHA256 { continue }
                if unlink(file.path) == 0 { removed.append(file) }
            }
            if unlink(recordURL.path) == 0 { removed.append(recordURL) }
        }
        return removed
    }
}

/// What one R.app launch leaves in its folder (rule 6.2): the script copy, which goes only while it is unchanged, the
/// other files that go with it, and the processes that may still need them. R removes all of these when it ends;
/// StatsDirect removes them, when it quits or next starts, after an R.app that did not end normally.
struct RExternalLaunchRecord: Codable, Equatable {
    static let fileName = ".statsdirect-launch.json"
    var script: String
    var scriptSHA256: String
    var files: [String]
    /// The StatsDirect that launched R.app: while it runs, a launch it has not yet recorded is still starting.
    var host: RProcessIdentity?
    /// R.app, once it has launched.
    var app: RProcessIdentity?

    static func read(_ url: URL) -> RExternalLaunchRecord? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size < 65_536,
              let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func write(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// A name that stays in its folder, and is not the record itself.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name != fileName && !name.contains("/") && !name.contains("\0")
    }
}

/// A private startup profile for a new R.app process. Merely opening an .R file
/// in R.app opens its editor; the profile also runs it, as the Windows host does.
/// Never change the user's .Rprofile or replace an existing R workspace.
struct RExternalSession {
    let directory: URL
    let script: URL
    let profile: URL
    var record: URL { directory.appendingPathComponent(RExternalLaunchRecord.fileName) }

    init(script source: URL, directory: URL) throws {
        try self.init(data: try Data(contentsOf: source), name: source.lastPathComponent, directory: directory)
    }

    init(data: Data, name: String, directory: URL) throws {
        self.directory = directory
        script = directory.appendingPathComponent(name)
        profile = directory.appendingPathComponent("startup.R")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The record comes first, so that whatever a crash interrupts can still be found and removed.
        try RExternalLaunchRecord(script: name, scriptSHA256: RExternalLaunchRecord.digest(data), files: [profile.lastPathComponent],
                                  host: .current, app: nil).write(to: record)
        try data.write(to: script, options: .atomic)
        // R refuses a whole file whose string literal holds a raw bidirectional-text control.
        func literal(_ value: String) throws -> String {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
            var text = ""
            for scalar in json.unicodeScalars {
                if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { text += String(format: "\\u%04x", scalar.value) }
                else { text.unicodeScalars.append(scalar) }
            }
            return text
        }
        let text = """
        # Only this R process uses the StatsDirect startup profile.
        Sys.unsetenv("R_PROFILE_USER")
        # When R ends, remove this file, the launch record and the script copy, unless the user has saved changes to the
        # copy. The folder stays: it is R's working directory.
        invisible(try(local({
          file <- \(try literal(script.path))
          saved <- tools::md5sum(file)
          reg.finalizer(globalenv(), function(e) {
            try(if (identical(tools::md5sum(file), saved)) unlink(file), silent = TRUE)
            unlink(c(\(try literal(profile.path)), \(try literal(record.path))))
          }, onexit = TRUE)
        }), silent = TRUE))
        # The user's own start-up file, as R itself would have run it: ./.Rprofile, else ~/.Rprofile.
        local({
          home <- Sys.getenv("HOME", unset = NA)
          profile <- if (file.access(".Rprofile", 4L) == 0L) ".Rprofile" else if (!is.na(home)) file.path(home, ".Rprofile")
          if (!is.null(profile) && file.access(profile, 4L) == 0L) try(source(profile, local = globalenv(), print.eval = TRUE))
          invisible(NULL)
        })
        .First <- local({
          started <- FALSE
          # A .First from the user's profile runs first, before the default packages are attached, as in R.
          user_first <- if (exists(".First", envir = globalenv(), inherits = FALSE)) get(".First", envir = globalenv(), inherits = FALSE)
          function() {
            if (started) return(invisible(NULL))
            started <<- TRUE
            if (is.function(user_first)) try(user_first())
            # Only base is attached when R calls .First.
            for (package in getOption("defaultPackages"))
              suppressPackageStartupMessages(require(package, character.only = TRUE))
            folder <- Sys.getenv("STATSDIRECT_R_FOLDER", unset = path.expand("~/Library/Application Support/StatsDirect Viewer"))
            library <- file.path(folder, "R Library")
            if (dir.exists(library)) .libPaths(c(library, .libPaths()))
            setwd(\(try literal(directory.path)))
            file <- \(try literal(script.path))
            cat("\\nStatsDirect: running ", basename(file), "\\n", sep = "")
            tryCatch(source(file, local = .GlobalEnv, echo = TRUE, print.eval = TRUE,
                            max.deparse.length = Inf, spaced = FALSE, encoding = "UTF-8"),
                     error = function(e) message("StatsDirect script: ", conditionMessage(e)))
            if (interactive()) try(utils::file.edit(file), silent = TRUE)
            invisible(NULL)
          }
        })
        """
        // R's startup parser requires a final newline to evaluate the last
        // expression (source() alone would not expose this difference).
        try (text + "\n").write(to: profile, atomically: true, encoding: .utf8)
    }

    @MainActor func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = ["R_PROFILE_USER": profile.path]
        return configuration
    }

    /// R.app has launched: record its process, so that StatsDirect leaves these files alone while it runs.
    func recordLaunch(_ app: RProcessIdentity) {
        // R removes the record when it ends; never bring back one it has removed.
        guard var launch = RExternalLaunchRecord.read(record) else { return }
        launch.app = app
        try? launch.write(to: record)
    }

    /// R.app did not start, so nothing will read these files.
    func discard() {
        for file in [script, profile, record] { try? FileManager.default.removeItem(at: file) }
    }
}
