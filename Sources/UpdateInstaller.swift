import Cocoa
import Darwin
import Security

struct StagedUpdate: Sendable {
    fileprivate let directory: URL
    fileprivate let version: String
    fileprivate let installedInode: ino_t

    func discard() { try? FileManager.default.removeItem(at: directory) }

    func launchInstaller() throws {
        guard let executable = Bundle.main.executableURL else {
            throw UpdateService.failure("StatsDirect could not start the update installer.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = [UpdateInstaller.installArgument, directory.path, version,
                             String(installedInode), String(getpid())]
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }
}

enum UpdateInstaller {
    fileprivate static let installArgument = "--install-statsdirect-update"
    private static let stagingPrefix = ".StatsDirect-update-"
    private static let bundleName = "StatsDirect.app"
    private static let bundleID = "com.statsdirect.viewer.prototype"
    private static let validationFlags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode))

    private struct InstalledApp {
        let url: URL
        let version: AppVersion
        let requirement: SecRequirement
        let inode: ino_t

        init(_ url: URL, team runningTeam: String? = nil) throws {
            self.url = url.resolvingSymlinksInPath().standardizedFileURL
            guard let bundle = Bundle(url: self.url), bundle.bundleIdentifier == UpdateInstaller.bundleID,
                  let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let version = AppVersion(text) else {
                throw UpdateService.failure("StatsDirect could not identify this installation.")
            }
            self.version = version
            inode = try UpdateInstaller.directoryInfo(self.url).st_ino
            let code = try UpdateInstaller.staticCode(self.url)
            let team = try runningTeam ?? UpdateInstaller.teamIdentifier(code)
            let rule = """
            identifier "\(UpdateInstaller.bundleID)" and anchor apple generic
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
            and certificate leaf[subject.OU] = "\(team)"
            """
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement,
                  SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else {
                throw UpdateService.failure("This copy of StatsDirect could not be verified for automatic installation.")
            }
            self.requirement = requirement
        }
    }

    static var canInstall: Bool {
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        return FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) &&
            (try? runningInstallation()) != nil
    }

    static func prepare(_ release: PublishedUpdate) async throws -> StagedUpdate {
        guard let archive = release.archive else {
            throw UpdateService.failure("A verified download is unavailable for this release.")
        }
        let installed = try runningInstallation()
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("StatsDirect-update-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: work) }
        let zip = try await archive.download(to: work)
        try Task.checkCancellation()
        let candidate = try extract(zip, in: work)
        try verify(candidate, version: release.version, installed: installed)
        try Task.checkCancellation()

        // Only stage a verified app beside the installation. That keeps the
        // download in temporary storage and puts the eventual swap on one volume.
        let directory = installed.url.deletingLastPathComponent().appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let staged = StagedUpdate(directory: directory, version: release.version, installedInode: installed.inode)
        do {
            let extracted = candidate.deletingLastPathComponent()
            try manager.moveItem(at: extracted, to: directory.appendingPathComponent(extracted.lastPathComponent, isDirectory: true))
            try Task.checkCancellation()
            return staged
        } catch {
            staged.discard()
            throw error
        }
    }

    // The system ZIP tools can assess the archive before writing to the private staging directory.
    // BSD tar's default path checks prevent archive paths and symlinks from escaping staging.
    static func extract(_ archive: URL, in directory: URL) throws -> URL {
        let summary = Pipe()
        let listing = try command("/usr/bin/unzip", ["-Z", "-t", archive.path], output: summary)
        let data = summary.fileHandleForReading.readDataToEndOfFile()
        listing.waitUntilExit()
        let fields = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)
        guard listing.terminationStatus == 0, fields.count >= 5,
              let entries = Int(fields[0]), (1...20_000).contains(entries),
              fields[1] == "files," || fields[1] == "file,",
              let bytes = Int64(fields[2]), (1...1_073_741_824).contains(bytes),
              fields[3] == "bytes", fields[4] == "uncompressed," else {
            throw UpdateService.failure("The update ZIP is invalid or expands beyond the installation limit.")
        }
        let destination = directory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        // macOS's tar still applies the AppleDouble entries of a ZIP (access control lists and extended
        // attributes) whatever flags it is given, so checkAttributes below is the real guard against them.
        let extraction = try command("/usr/bin/tar", ["-xf", archive.path, "--safe-writes",
                                                     "--no-same-owner", "--no-same-permissions", "--no-mac-metadata",
                                                     "--no-acls", "--no-xattrs", "--no-fflags",
                                                     "-C", destination.path])
        extraction.waitUntilExit()
        let contents = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        guard extraction.terminationStatus == 0, contents == [bundleName] else {
            throw UpdateService.failure("The ZIP could not be safely expanded to a single StatsDirect app.")
        }
        let app = destination.appendingPathComponent(bundleName, isDirectory: true)
        _ = try directoryInfo(app)
        return app
    }

    static func verify(_ candidate: URL, version: String, replacing installed: URL) throws {
        try verify(candidate, version: version, installed: InstalledApp(installed))
    }

    private static func verify(_ candidate: URL, version: String, installed: InstalledApp) throws {
        _ = try directoryInfo(candidate)
        try checkAttributes(candidate)
        let code = try staticCode(candidate)
        guard SecStaticCodeCheckValidity(code, validationFlags, installed.requirement) == errSecSuccess else {
            throw UpdateService.failure("The update failed the StatsDirect Developer ID signature check.")
        }
        guard let offered = AppVersion(version), offered > installed.version,
              let bundle = Bundle(url: candidate), bundle.bundleIdentifier == bundleID,
              let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(text) == offered else {
            throw UpdateService.failure("The downloaded app does not match the offered update version.")
        }
        let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        guard supportsThisMac(minimum: minimum) else {
            throw UpdateService.failure("StatsDirect \(text) needs macOS \(minimum ?? "") or later, so it cannot be installed on this Mac.")
        }
        let policy = try command("/usr/bin/syspolicy_check", ["distribution", candidate.path])
        policy.waitUntilExit()
        guard policy.terminationStatus == 0 else {
            throw UpdateService.failure("macOS could not verify the update’s notarisation and distribution signature.")
        }
    }

    // A code signature covers what a file holds, not who may change it. Refuse an app whose files other
    // users could alter or that carries marks a genuine release never has; nothing is repaired.
    static func checkAttributes(_ app: URL) throws {
        let refusal = UpdateService.failure("The update has file permissions or attributes that a StatsDirect release never has.")
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in false }) else { throw refusal }
        var items = [app]
        for case let item as URL in walker { items.append(item) }
        for item in items {
            var info = stat()
            guard lstat(item.path, &info) == 0 else { throw refusal }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFREG || kind == S_IFDIR, info.st_uid == geteuid(),
                  info.st_mode & (S_ISUID | S_ISGID | S_ISVTX | S_IWGRP | S_IWOTH) == 0,
                  kind == S_IFDIR || info.st_nlink == 1 else { throw refusal }
            if let list = acl_get_link_np(item.path, ACL_TYPE_EXTENDED) {
                var entry: acl_entry_t?
                let listed = acl_get_entry(list, ACL_FIRST_ENTRY.rawValue, &entry) == 0
                acl_free(UnsafeMutableRawPointer(list))
                guard !listed else { throw refusal }
            }
            let size = listxattr(item.path, nil, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { throw refusal }
            if size > 0 {
                var names = [CChar](repeating: 0, count: size)
                let read = listxattr(item.path, &names, size, XATTR_NOFOLLOW)
                guard read >= 0 else { throw refusal }
                let attributes = names.prefix(read).split(separator: 0).map { String(cString: Array($0) + [0]) }
                // macOS itself marks files an app writes (com.apple.provenance) or was granted (com.apple.macl);
                // nothing else belongs on a freshly unpacked release.
                guard attributes.allSatisfy({ $0 == "com.apple.provenance" || $0 == "com.apple.macl" }) else { throw refusal }
            }
        }
    }

    static func supportsThisMac(minimum: String?, current: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        let parts = minimum.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), !parts.contains(nil) else { return false }
        let wanted = parts.compactMap { $0 } + Array(repeating: 0, count: 3 - parts.count)
        return [current.majorVersion, current.minorVersion, current.patchVersion].lexicographicallyPrecedes(wanted) == false
    }

    // An interrupted update leaves its private staging folder, with a whole copy of the app, beside StatsDirect.
    static func removeStaleStaging(beside app: URL = Bundle.main.bundleURL, olderThan age: TimeInterval = 86_400, now: Date = Date()) {
        let parent = app.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names where name.hasPrefix(stagingPrefix) && UUID(uuidString: String(name.dropFirst(stagingPrefix.count))) != nil {
            let folder = parent.appendingPathComponent(name, isDirectory: true)
            var info = stat()
            guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                  now.timeIntervalSince1970 - TimeInterval(info.st_mtimespec.tv_sec) > age else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @MainActor static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.dropFirst().first == installArgument else { return false }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        var stage: URL?
        var reopenOnFailure = false
        defer { if let stage { try? FileManager.default.removeItem(at: stage) } }
        do {
            guard args.count == 6, let inode = ino_t(args[4]), let parent = pid_t(args[5]),
                  parent > 1, getppid() == parent || getppid() == 1 else {
                throw UpdateService.failure("StatsDirect could not read the installation request.")
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 60
            while getppid() == parent, ProcessInfo.processInfo.systemUptime < deadline { usleep(100_000) }
            guard getppid() != parent else {
                throw UpdateService.failure("StatsDirect was still closing when the updater was ready.")
            }
            reopenOnFailure = true
            let directory = URL(fileURLWithPath: args[2], isDirectory: true).standardizedFileURL
            let folderName = directory.lastPathComponent
            guard directory.deletingLastPathComponent().path == target.deletingLastPathComponent().path,
                  folderName.hasPrefix(stagingPrefix), UUID(uuidString: String(folderName.dropFirst(stagingPrefix.count))) != nil else {
                throw UpdateService.failure("StatsDirect could not find the private update staging folder.")
            }
            let info = try directoryInfo(directory)
            guard info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
                throw UpdateService.failure("The update staging folder is accessible to other users.")
            }
            stage = directory
            let descriptor = Darwin.open(target.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw UpdateService.failure("The installed application could not be opened.") }
            defer { Darwin.close(descriptor) }
            var locked = stat()
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                reopenOnFailure = false
                throw UpdateService.failure("Another installer is already updating this copy of StatsDirect.")
            }
            guard fstat(descriptor, &locked) == 0, locked.st_ino == inode else {
                throw UpdateService.failure("StatsDirect changed on disk while the update was being prepared.")
            }
            let installed = try runningInstallation()
            let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
            _ = try directoryInfo(extracted)
            let candidate = extracted.appendingPathComponent(bundleName, isDirectory: true)
            try verify(candidate, version: args[3], installed: installed)
            guard try directoryInfo(target).st_ino == inode else {
                throw UpdateService.failure("StatsDirect changed on disk while the update was being prepared.")
            }
            guard !isRunning(target, excluding: parent) else {
                reopenOnFailure = false
                throw UpdateService.failure("Another copy of this installation is open.")
            }
            try replace(target, with: candidate) { try reopen(target) }
        } catch {
            if error is RestoreFailure {
                stage = nil
            } else if reopenOnFailure && !isRunning(target, excluding: pid_t(args[5]) ?? 0) {
                try? reopen(target)
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            application.activate()
            let alert = NSAlert(error: error)
            alert.messageText = "Could not install the StatsDirect update"
            alert.runModal()
        }
        return true
    }

    // The directories are on the same volume. A failed swap leaves the old app in place.
    // Keep the old app in staging until LaunchServices accepts the replacement.
    static func replace(_ target: URL, with candidate: URL, relaunch: () throws -> Void) throws {
        try swap(target, candidate)
        do {
            try relaunch()
        } catch {
            do { try swap(target, candidate) }
            catch { throw RestoreFailure(previousApp: candidate) }
            throw error
        }
    }

    private struct RestoreFailure: LocalizedError {
        let previousApp: URL
        var errorDescription: String? { "The previous StatsDirect app is available at \(previousApp.path). The updater could not restore it automatically." }
    }

    private static func swap(_ first: URL, _ second: URL) throws {
        guard renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path, UInt32(RENAME_SWAP)) == 0 else {
            let reason = String(cString: strerror(errno))
            throw UpdateService.failure("StatsDirect could not replace the installed app. \(reason)")
        }
    }

    private static func reopen(_ target: URL) throws {
        let launch = try command("/usr/bin/open", ["-n", target.path])
        launch.waitUntilExit()
        guard launch.terminationStatus == 0 else {
            throw UpdateService.failure("macOS could not reopen StatsDirect after installation.")
        }
    }

    private static func directoryInfo(_ path: URL) throws -> stat {
        var info = stat()
        guard lstat(path.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw UpdateService.failure("The update contains an unexpected application or folder path.")
        }
        return info
    }

    private static func staticCode(_ url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateService.failure("The application code signature could not be read.")
        }
        return code
    }

    private static func runningInstallation() throws -> InstalledApp {
        var code: SecCode?
        var signature: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &signature) == errSecSuccess, let signature else {
            throw UpdateService.failure("The running StatsDirect signature could not be read.")
        }
        let installation = try InstalledApp(Bundle.main.bundleURL, team: teamIdentifier(signature))
        guard SecCodeCheckValidity(code, [], installation.requirement) == errSecSuccess else {
            throw UpdateService.failure("The running app does not match the installed StatsDirect signature.")
        }
        return installation
    }

    private static func teamIdentifier(_ code: SecStaticCode) throws -> String {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &information) == errSecSuccess,
              let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw UpdateService.failure("This copy of StatsDirect has no Developer ID signature for automatic installation.")
        }
        return team
    }

    private static func isRunning(_ app: URL, excluding parent: pid_t) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
            $0.processIdentifier != parent && $0.processIdentifier != getpid() && !$0.isTerminated &&
                $0.bundleURL?.resolvingSymlinksInPath().path == app.path
        }
    }

    private static func command(_ executable: String, _ arguments: [String], output: Any = FileHandle.nullDevice) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
