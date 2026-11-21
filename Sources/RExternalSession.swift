import Cocoa
import CryptoKit

/// Open in R (the script pane and the console) and R+ (the worksheet) hand a script to RStudio or R.app, keeping data
/// only where R needs it (rule 6.2 of the worksheet R rules):
/// - RStudio opens a script for the user to run when they choose, so R+ gives it one uniquely named file per import in
///   R Scripts: the user's own file, and the only copy.
/// - R.app is started to run a copy in "External R-<UUID>", which is also R's working directory, and shows that copy in
///   its editor. When R ends, StatsDirect's start-up file removes the copy and itself, each only while it is unchanged
///   (a copy the user has saved changes to is theirs). A launch record beside them lets StatsDirect do the same for an
///   R.app that did not end normally, when StatsDirect quits or next starts. The folder always stays: users save files
///   there.
/// - With neither installed, a worksheet import gets a new file in R Scripts; a console script keeps its own name.
@MainActor enum RExternalScript {
    nonisolated(unsafe) static var opensExternally = true
    static var scriptsFolder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect Viewer/R Scripts", isDirectory: true) }
    nonisolated static let rAppIdentifier = "org.R-project.R"
    private static var rstudio: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.rstudio.RStudio")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.rstudio.desktop")
    }

    /// The file name for a script titled `name`: "/", ":", control characters and bidirectional-text controls as "_", and
    /// a leading "." too, which would hide the file; without surrounding spaces; with ".R" added unless it has an R
    /// extension; never empty; and short enough for a date and number to be added: at most 200 of the 255 units the Mac's
    /// disks allow a name (`diskLength`), shortened on a character boundary.
    nonisolated static func fileName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            let replaced = scalar == "/" || scalar == ":" || scalar.properties.generalCategory == .control
                || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
            scalars.append(replaced ? "_" : scalar)
        }
        var file = String(scalars).trimmingCharacters(in: .whitespaces)
        if file.isEmpty { file = "Script" }
        // Finder, RStudio's Files pane and R's list.files() do not show a file whose name starts with ".". The first
        // scalar, not the first character: "." with an accent on it still starts the name with ".".
        if file.unicodeScalars.first == "." { file.unicodeScalars.removeFirst(); file = "_" + file }
        if (file as NSString).pathExtension.lowercased() != "r" { file += ".R" }
        if diskLength(file) > 200 {
            // Each character takes at least one unit, so the first 198 hold all that can stay.
            var stem = String((file as NSString).deletingPathExtension.prefix(198))
            while diskLength(stem) > 198 { stem.removeLast() }
            // Nothing stays of a title that is one character with a long run of accents on it.
            file = (stem.isEmpty ? "Script" : stem) + ".R"
        }
        return file
    }

    /// A name's length as the Mac's disks limit it, to 255: in UTF-16 units of the decomposed form Foundation gives them,
    /// which can be several times its length as typed ("ǖ" is u, a diaeresis and a macron). That form is NFD, except that
    /// it keeps some characters whole, CJK compatibility ideographs among them, a few of which NFD would make shorter.
    nonisolated static func diskLength(_ name: String) -> Int {
        let text = name as CFString
        var bytes = [CChar](repeating: 0, count: CFStringGetMaximumSizeOfFileSystemRepresentation(text))
        guard CFStringGetFileSystemRepresentation(text, &bytes, bytes.count) else {
            return name.decomposedStringWithCanonicalMapping.utf16.count
        }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).utf16.count
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
    /// " 2", " 3" and so on when that name is taken. Only a name in use moves on to the next number: any other failure is
    /// reported, naming the file, and leaves no file. `rename` moves the finished file to its name unless the name is
    /// taken (0, or the error number); the tests replace it to stand for a disk that cannot do that.
    static func saveUnique(_ source: String, name: String, date: Date = Date(), in folder: URL? = nil,
                           rename: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno }) throws -> URL {
        let folder = folder ?? scriptsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stem = (fileName(name) as NSString).deletingPathExtension + " " + formatter.string(from: date)
        func candidate(_ number: Int) -> URL { folder.appendingPathComponent(stem + (number == 1 ? "" : " \(number)") + ".R") }
        func failure(_ code: Int32) -> Error { fileError(code, candidate(1)) }
        let data = Data(source.utf8)
        // Write to our own private file first. A failed open or write never touches any candidate's path, and no reader
        // can see a partial script at the chosen name. The temporary file is on the same volume as its destination, and
        // is made as any file StatsDirect writes, so the user's file-creation mask applies (mkstemp's would be private).
        var temporary: [CChar] = [], descriptor: Int32 = -1, opened: Int32 = EEXIST
        for _ in 0 ..< 100 where descriptor < 0 && opened == EEXIST {
            let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            let url = folder.appendingPathComponent(temporaryPrefix + String((0 ..< 6).map { _ in letters.randomElement()! }))
            guard let path = url.withUnsafeFileSystemRepresentation({ path in path.map { Array(UnsafeBufferPointer(start: $0, count: strlen($0) + 1)) } })
            else { throw CocoaError(.fileWriteInvalidFileName) }
            temporary = path
            descriptor = Darwin.open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
            opened = descriptor < 0 ? errno : 0
        }
        guard descriptor >= 0 else { throw failure(opened) }
        var published = false, removed = false
        defer { if !published && !removed { unlink(temporary) } }
        let written = writeAll(descriptor, data), closed: Int32 = Darwin.close(descriptor) == 0 ? 0 : errno
        guard written == 0, closed == 0 else { throw failure(written != 0 ? written : closed) }
        var renames = true
        for number in 1 ... 1000 {
            let url = candidate(number)
            let taken: Bool = try url.withUnsafeFileSystemRepresentation { path in
                guard let path else { throw CocoaError(.fileWriteInvalidFileName) }
                if renames {
                    let result = rename(temporary, path)
                    if result == 0 { published = true; return false }
                    if result == EEXIST { return true }
                    // A disk that cannot rename without replacing (FAT, exFAT, some network disks) says so: there the
                    // script is written straight to its name, which is made only if it is free.
                    guard result == ENOTSUP || result == EINVAL else { throw failure(result) }
                    renames = false
                    // The private file has done its work, and would take room on the disk that the script may need.
                    unlink(temporary); removed = true
                }
                return try !createExclusively(path, data, failure)
            }
            if !taken { return url }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// The script written to a name that is free, on a disk that cannot rename without replacing; false when the name is
    /// taken. A failed write removes the file, and only the very file this call made.
    private static func createExclusively(_ path: UnsafePointer<CChar>, _ data: Data, _ failure: (Int32) -> Error) throws -> Bool {
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else {
            let code = errno
            if code == EEXIST { return false }
            throw failure(code)
        }
        let written = writeAll(descriptor, data)
        // Which file this is, is asked after the write: on FAT and exFAT a file's number changes once it is written to.
        var made = stat()
        let known = fstat(descriptor, &made) == 0
        let closed: Int32 = Darwin.close(descriptor) == 0 ? 0 : errno
        if written == 0 && closed == 0 { return true }
        var found = stat()
        if known, lstat(path, &found) == 0, found.st_dev == made.st_dev, found.st_ino == made.st_ino { unlink(path) }
        throw failure(written != 0 ? written : closed)
    }

    /// 0, or the error number of the write that failed.
    private static func writeAll(_ descriptor: Int32, _ data: Data) -> Int32 {
        data.withUnsafeBytes { buffer -> Int32 in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                offset += count
            }
            return 0
        }
    }

    /// A failed save worded as Foundation words its own, naming the file and its folder, with the system's error under it.
    static func fileError(_ code: Int32, _ url: URL) -> Error {
        var info: [String: Any] = [NSFilePathErrorKey: url.path, NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))]
        let kind: CocoaError.Code
        switch code {
        case EACCES, EPERM: kind = .fileWriteNoPermission
        case ENOSPC, EDQUOT: kind = .fileWriteOutOfSpace
        case EROFS: kind = .fileWriteVolumeReadOnly
        default:
            // Foundation has no wording for the other reasons (too many open files, a file too large, an unsupported disk).
            kind = .fileWriteUnknown
            info[NSLocalizedDescriptionKey] = "The file “\(url.lastPathComponent)” couldn’t be saved in the folder “\(url.deletingLastPathComponent().lastPathComponent)”: \(String(cString: strerror(code)))."
        }
        return CocoaError(kind, userInfo: info)
    }

    /// The name of a save in progress in R Scripts, then six letters or digits: hidden, and never a script's name, as
    /// fileName starts no name with ".".
    nonisolated static let temporaryPrefix = ".statsdirect-r-"
    /// Removes what a save that never finished left in R Scripts, when StatsDirect was stopped between writing its
    /// private file and renaming it (rule 6.2: any copy left over is removed when StatsDirect closes or next starts).
    /// Only this user's plain files under a private name go, and only those old enough that no running StatsDirect can
    /// still be writing them.
    @discardableResult nonisolated static func removeStaleTemporaries(in folder: URL, olderThan age: TimeInterval = 600, now: Date = Date()) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        var removed: [URL] = []
        for name in names where name.hasPrefix(temporaryPrefix) {
            let tail = name.dropFirst(temporaryPrefix.count)
            guard tail.count == 6, tail.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { continue }
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
                  now.timeIntervalSince1970 - TimeInterval(info.st_mtimespec.tv_sec) > age, unlink(url.path) == 0 else { continue }
            removed.append(url)
        }
        return removed
    }

    /// Every worksheet fallback keeps a separate import, as the RStudio path does: a failed or declined external
    /// launch must not replace an earlier worksheet or a user's file. `echo` is the existing source distinction:
    /// worksheet imports are quiet, while console scripts keep the script pane's established save-by-name behavior.
    /// Explicit Save continues to use `save` or a save panel and may replace the file the user chose.
    static func saveFallback(_ source: String, name: String, echo: Bool, date: Date = Date(), in folder: URL? = nil) throws -> URL {
        if !echo { return try saveUnique(source, name: name, date: date, in: folder) }
        return try save(source, name: name, in: folder)
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
    @discardableResult static func open(_ source: String, name: String, workingDirectory: URL, echo: Bool = true,
                                         status: @escaping @MainActor (String) -> Void) -> URL? {
        do {
            if let rstudio, source.isEmpty {
                // No data (rule 6.4): RStudio's own session, with no file to keep or remove.
                status("Opening RStudio…")
                NSWorkspace.shared.openApplication(at: rstudio, configuration: NSWorkspace.OpenConfiguration()) { application, error in
                    let name = application?.localizedName, reason = error?.localizedDescription
                    DispatchQueue.main.async { status(reason.map { "Open in R failed: \($0)." } ?? "Opened \(name ?? "RStudio")") }
                }
                return nil
            }
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
                let session = try RExternalSession(data: Data(source.utf8), name: fileName(name), directory: launchFolder(in: workingDirectory), echo: echo)
                start(session, with: r, status: status) { reason in
                    // R.app did not start: keep the script for the user, as when no R application is installed.
                    do {
                        let saved = try saveFallback(source, name: name, echo: echo)
                        status("Open in R failed: \(reason). Your script is saved as \(saved.path).")
                    } catch {
                        status("Open in R failed: \(reason). Your script could not be saved: \(error.localizedDescription)")
                    }
                }
                return session.script
            }
            let saved = try saveFallback(source, name: name, echo: echo)
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
    /// one folder below it (a console session's or a script pane's folder): each file a launch record lists, while it is
    /// still what the launch wrote, and then the record itself, unless a listed file could not be read or removed, when the
    /// record stays for a later run. A launch made by another StatsDirect that is still running
    /// is that StatsDirect's own, whether or not its R.app has started, and keeps everything; so does a launch whose R.app
    /// is still running, or may be, and a folder without a record (an earlier version's, or RStudio's). Folders always
    /// stay. `this` is the StatsDirect calling. Returns the files removed.
    @discardableResult nonisolated static func removeLeftovers(
        in roots: [URL], this: RProcessIdentity? = .current, isRunning: (RProcessIdentity) -> Bool = { $0.isRunning },
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
            // Another StatsDirect that is still running looks after its own launches, even one still starting.
            if let host = launch.host, host != this, isRunning(host) { continue }
            if let app = launch.app {
                if isRunning(app) { continue }
            } else {
                // Not yet recorded: still starting, when this StatsDirect launched it; otherwise any R.app that is
                // running might be the one using these files.
                if let host = launch.host, host == this { continue }
                if rApp == nil { rApp = rAppRunning() }
                if rApp == true { continue }
            }
            var kept = false
            for (name, digest) in launch.files.sorted(by: { $0.key < $1.key }) where RExternalLaunchRecord.isPlainName(name) {
                let file = folder.appendingPathComponent(name)
                var info = stat()
                guard lstat(file.path, &info) == 0 else {
                    if errno != ENOENT { kept = true }
                    continue
                }
                guard info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFLNK else { continue }
                // A file that cannot be read now may still be what this launch wrote: it stays, and keeps the record, so
                // that a later run looks at it again. One that is no longer what the launch wrote is the user's: a script
                // copy they saved changes to in R.app's editor, or their own file under that name.
                guard let contents = fm.contents(atPath: file.path) else { kept = true; continue }
                guard RExternalLaunchRecord.digest(contents) == digest else { continue }
                if unlink(file.path) == 0 { removed.append(file) } else { kept = true }
            }
            // The record goes once what it lists is gone or the user's, so that a later run can retry the rest.
            if !kept, unlink(recordURL.path) == 0 { removed.append(recordURL) }
        }
        return removed
    }
}

/// What one R.app launch leaves in its folder (rule 6.2): the script copy and StatsDirect's start-up file, each of which
/// goes only while it is unchanged, and the processes that may still need them. R removes these when it ends;
/// StatsDirect removes them, when it quits or next starts, after an R.app that did not end normally.
struct RExternalLaunchRecord: Codable, Equatable {
    static let fileName = ".statsdirect-launch.json"
    /// This launch's own identifier. The start-up file holds it too, and R removes the record only while it still does.
    var id: String
    /// The files the launch wrote, by name, each with the SHA-256 of what was written. A file that is no longer that (a
    /// script copy the user has saved changes to in R.app's editor, or their own file in its place) is the user's.
    var files: [String: String]
    /// The StatsDirect that launched R.app: while it runs, the launch is its own, and a launch it has not yet recorded
    /// is still starting.
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
    /// StatsDirect's start-up file in the launch folder, which is R's working directory: a reserved hidden name, which
    /// no script copy takes and a user is unlikely to choose.
    static let profileName = ".statsdirect-startup.R"
    /// Where the user's own R_PROFILE_USER, when StatsDirect has one, reaches the start-up file (rule 6.1).
    static let userProfileVariable = "STATSDIRECT_USER_R_PROFILE"
    let directory: URL
    let script: URL
    let profile: URL
    var record: URL { directory.appendingPathComponent(RExternalLaunchRecord.fileName) }

    /// The name a script copy takes in the launch folder: its own, unless that is the start-up file's or the launch
    /// record's in some letter case (compared as the Mac's disks compare names), when it becomes "Script <name>".
    static func scriptName(_ name: String) -> String {
        [profileName, RExternalLaunchRecord.fileName].contains { name.compare($0, options: .caseInsensitive) == .orderedSame }
            ? "Script " + name : name
    }

    /// A path or a name as R code that gives R its exact UTF-8 bytes in any locale, which R hands to the file system
    /// unchanged. Text a string literal can hold as it is goes in a plain literal, UTF-8 as written. Text it would need an
    /// escape for (a quote, a backslash, a control character, or a bidirectional-text control, for which R refuses the whole
    /// file) is written as its bytes, rawToChar(as.raw(c(0x.., ...))): an escape would make R mark the string UTF-8 and
    /// translate it into the native encoding for the file system, which in the C locale cannot hold the character, so a
    /// launch folder or script name with one would fail there.
    static func rLiteral(_ value: String) -> String {
        let plain = value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x22, 0x5C, 0..<0x20, 0x7F...0x9F, 0x202A...0x202E, 0x2066...0x2069: return false
            default: return true
            }
        }
        if plain { return "\"" + value + "\"" }
        return "rawToChar(as.raw(c(" + value.utf8.map { String(format: "0x%02x", $0) }.joined(separator: ", ") + ")))"
    }

    init(script source: URL, directory: URL) throws {
        try self.init(data: try Data(contentsOf: source), name: source.lastPathComponent, directory: directory)
    }

    /// `echo` shows each command in R.app's console as the script runs: wanted for a console or script pane's own code,
    /// not for a worksheet import, whose data would fill the console before str() (rule 5.4).
    init(data: Data, name: String, directory: URL, echo: Bool = true) throws {
        self.directory = directory
        script = directory.appendingPathComponent(Self.scriptName(name))
        profile = directory.appendingPathComponent(Self.profileName)
        let id = UUID().uuidString
        let literal = Self.rLiteral
        let text = """
        # Only this R process uses the StatsDirect start-up file.
        Sys.unsetenv("R_PROFILE_USER")
        # When R ends, remove the script copy and this file, each only while it is unchanged (a copy the user has saved
        # changes to is theirs), then the launch record. Exact paths, never patterns: R's unlink would read [ ], * and ?
        # in a name as a pattern. The folder stays: it is R's working directory.
        invisible(try(local({
          files <- c(\(literal(script.path)), \(literal(profile.path)))
          record <- \(literal(record.path))
          saved <- tools::md5sum(files)
          reg.finalizer(globalenv(), function(e) try({
            now <- tools::md5sum(files)
            unchanged <- !is.na(saved) & !is.na(now) & saved == now
            suppressWarnings(file.remove(files[unchanged]))
            # The record goes only when each file it lists is gone or is known to be the user's (changed); a file R cannot
            # read keeps the record, so that StatsDirect's own clean-up finds it later. The listing only proves absence
            # if it includes the record itself: an unreadable folder can return an empty listing. Match plain names
            # without case and other names by their ASCII letters and digits, so case and accent aliases keep the record.
            # The name must also be gone for file.access, which asks the disk for the name alone, in whatever case and
            # form of its accents the disk keeps it, where file.exists needs the file's attributes.
            changed <- !is.na(saved) & !is.na(now) & saved != now
            names <- list.files(dirname(record), all.files = TRUE, no.. = TRUE)
            ascii <- function(x) !grepl("[^ -~]", x, useBytes = TRUE)
            fold <- function(x) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
            plainNames <- fold(names[ascii(names)])
            key <- function(x) tolower(gsub("[^A-Za-z0-9]", "", iconv(x, "UTF-8", "ASCII", sub = "")))
            base <- basename(files)
            plain <- ascii(base)
            listed <- key(base) %in% key(names)
            listed[plain] <- fold(base[plain]) %in% plainNames
            gone <- fold(basename(record)) %in% plainNames & !file.exists(files) & !listed & file.access(files, 0) != 0
            if (all(gone | changed) && length(grepRaw(\(literal(id)), readBin(record, "raw", 65536L), fixed = TRUE)))
              suppressWarnings(file.remove(record))
          }, silent = TRUE), onexit = TRUE)
        }), silent = TRUE))
        # The user's own start-up file, as R itself would have run it: the file the user's own R_PROFILE_USER names, when
        # they had one, else ./.Rprofile, else ~/.Rprofile. R processes started from this session get the user's
        # R_PROFILE_USER back, or none.
        local({
          user <- Sys.getenv("\(Self.userProfileVariable)", unset = NA)
          Sys.unsetenv("\(Self.userProfileVariable)")
          # A StatsDirect start-up file is never the user's own, or it would run itself.
          if (!is.na(user) && basename(user) == "\(Self.profileName)") user <- NA
          profile <- if (!is.na(user)) {
            Sys.setenv(R_PROFILE_USER = user)
            if (nzchar(user)) path.expand(user)
          } else if (file.access(".Rprofile", 4L) == 0L) ".Rprofile" else {
            home <- Sys.getenv("HOME", unset = NA)
            if (!is.na(home)) file.path(home, ".Rprofile")
          }
          # As R reads it, without re-encoding, whatever options(encoding) says.
          if (!is.null(profile) && file.access(profile, 4L) == 0L && !dir.exists(profile))
            try(source(profile, local = globalenv(), print.eval = TRUE, encoding = "native.enc"))
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
            setwd(\(literal(directory.path)))
            file <- \(literal(script.path))
            cat("\\nStatsDirect: running ", basename(file), "\\n", sep = "")
            # The script is UTF-8, whatever the locale or the user's options(encoding): its lines are read as they are, marked
            # UTF-8 and parsed, so that no connection re-encodes them. In the C locale, source(file, encoding = "UTF-8") stops
            # at the first character the locale cannot hold, such as the quotation marks in the script's first comment.
            tryCatch({
              connection <- file(file, "rb")
              lines <- tryCatch(readLines(connection, warn = FALSE, encoding = "UTF-8"), finally = close(connection))
              source(exprs = parse(text = lines, keep.source = TRUE, encoding = "UTF-8"), local = .GlobalEnv,
                     echo = \(echo ? "TRUE" : "FALSE"), print.eval = TRUE, max.deparse.length = Inf, spaced = FALSE)
            }, error = function(e) message("StatsDirect script: ", conditionMessage(e)))
            if (interactive()) try(utils::file.edit(file), silent = TRUE)
            invisible(NULL)
          }
        })
        """
        // R's startup parser requires a final newline to evaluate the last
        // expression (source() alone would not expose this difference).
        let profileData = Data((text + "\n").utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The record comes first, so that whatever a crash interrupts can still be found and removed.
        var files = [profile.lastPathComponent: RExternalLaunchRecord.digest(profileData)]
        files[script.lastPathComponent] = RExternalLaunchRecord.digest(data)
        try RExternalLaunchRecord(id: id, files: files, host: .current, app: nil).write(to: record)
        try data.write(to: script, options: .atomic)
        try profileData.write(to: profile, options: .atomic)
    }

    /// R.app's environment: StatsDirect's start-up file in place of the user's, and the user's own R_PROFILE_USER, when
    /// StatsDirect's environment has one (`environment`), for the start-up file to run and give back (rule 6.1).
    @MainActor func configuration(environment: [String: String] = ProcessInfo.processInfo.environment) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        var variables = ["R_PROFILE_USER": profile.path]
        // A StatsDirect start-up file passed on through an inherited R_PROFILE_USER is never taken for the user's own.
        if let user = environment["R_PROFILE_USER"], (user as NSString).lastPathComponent != Self.profileName {
            variables[Self.userProfileVariable] = user
        }
        configuration.environment = variables
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
