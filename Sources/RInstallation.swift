import Foundation
import CryptoKit

enum RRuntime {
    /// The interactive console embeds R and needs this version or later, as the Windows console does (R 4.2); the
    /// script pane runs any R through Rscript. Stated here once; the console's message names it.
    static let consoleMinimum = (major: 4, minor: 2)
    static let candidates = ["/Library/Frameworks/R.framework/Resources/bin/Rscript", "/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript"]
    /// One R the candidates reach: its Rscript, the version and architecture its path tells (CRAN's framework keeps
    /// each series under Versions/<major.minor>-<arch>; Homebrew keeps R under Cellar/r/<version>), and its place
    /// in the candidate order.
    struct Installation: Equatable {
        let path: String
        let version: [Int]
        let native: Bool
        let order: Int
    }
    /// Every R the candidates reach. A framework candidate stands for every version in its Versions folder, so a
    /// newer series installed beside an older one is seen whichever the framework's Current link names.
    static func installations(in paths: [String] = candidates) -> [Installation] {
        let fm = FileManager.default
        var found: [Installation] = [], seen = Set<String>()
        func add(_ path: String, order: Int) {
            guard fm.isExecutableFile(atPath: path) else { return }
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            guard seen.insert(real).inserted else { return }
            found.append(Installation(path: path, version: version(ofRscript: real), native: isNative(rscript: real), order: order))
        }
        for (order, path) in paths.enumerated() {
            let marker = "/R.framework/Resources/bin/Rscript"
            if path.hasSuffix(marker) {
                let versions = String(path.dropLast(marker.count)) + "/R.framework/Versions"
                let names = ((try? fm.contentsOfDirectory(atPath: versions)) ?? []).filter { $0 != "Current" }.sorted()
                for name in names { add(versions + "/" + name + "/Resources/bin/Rscript", order: order) }
            }
            add(path, order: order)
        }
        return found
    }
    /// The R to use: the newest, a native (Apple Silicon) R before an Intel one of any version, the earlier candidate
    /// when nothing else separates two.
    static func executable(in paths: [String] = candidates) -> String? {
        installations(in: paths).max { a, b in
            if a.native != b.native { return !a.native }
            if a.version != b.version { return a.version.lexicographicallyPrecedes(b.version) }
            return a.order > b.order
        }?.path
    }
    /// "4.6", "4.6-arm64" (a framework Versions folder) or "4.5.1", "4.5.1_2" (a Homebrew Cellar folder) as numbers;
    /// empty when the path says nothing.
    static func version(ofRscript real: String) -> [Int] {
        let parts = real.split(separator: "/").map(String.init)
        var name: String?
        if let i = parts.firstIndex(of: "Versions"), i + 1 < parts.count, parts.contains("R.framework") { name = parts[i + 1] }
        else if let i = parts.firstIndex(of: "Cellar"), i + 2 < parts.count, parts[i + 1] == "r" { name = parts[i + 2] }
        guard let name else { return [] }
        let numeric = name.prefix { $0.isNumber || $0 == "." }
        return numeric.split(separator: ".").compactMap { Int($0) }
    }
    /// Whether this R runs natively on Apple Silicon, which the console's helper needs to load it: read from the
    /// Rscript binary's Mach-O header (a thin arm64 image or a universal one with an arm64 slice). CRAN names its
    /// framework folders inconsistently ("4.6" here for an arm64 build, "4.3-arm64" elsewhere), so the name is only
    /// the fallback for a file that is not a Mach-O image, such as a script; Homebrew under /opt/homebrew is arm64.
    static func isNative(rscript real: String) -> Bool {
        if let native = machOHasArm64(at: real) { return native }
        if real.hasPrefix("/opt/homebrew/") { return true }
        let parts = real.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "Versions"), i + 1 < parts.count, parts.contains("R.framework") { return parts[i + 1].hasSuffix("-arm64") }
        return false
    }
    /// nil when the file is not a Mach-O image; otherwise whether it carries arm64 code.
    static func machOHasArm64(at path: String) -> Bool? {
        guard let handle = FileHandle(forReadingAtPath: path), let header = try? handle.read(upToCount: 4096), header.count >= 8 else { return nil }
        let arm64: UInt32 = 0x0100000C
        func word(_ offset: Int, bigEndian: Bool) -> UInt32 {
            let b = [UInt32](header[offset..<offset + 4].map { UInt32($0) })
            return bigEndian ? (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]) : (b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0])
        }
        switch word(0, bigEndian: false) {
        case 0xFEEDFACF, 0xFEEDFACE: return word(4, bigEndian: false) == arm64       // thin, little-endian
        case 0xBEBAFECA, 0xBFBAFECA:                                                   // universal: big-endian fat header
            let count = Int(word(4, bigEndian: true))
            guard count > 0, count < 32, header.count >= 8 + count * 20 else { return false }
            return (0..<count).contains { word(8 + $0 * 20, bigEndian: true) == arm64 }
        default: return nil
        }
    }
    /// Why the interactive console cannot use an R of this version, or nil when it can; `reported` is what R
    /// prints for getRversion(), such as "4.1.3".
    static func consoleVersionProblem(_ reported: String) -> String? {
        let needed = "\(consoleMinimum.major).\(consoleMinimum.minor)"
        let numbers = reported.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2 else { return "The interactive console needs R \(needed) or later; this R did not report its version (\"\(reported.trimmingCharacters(in: .whitespacesAndNewlines))\"). Install a current R, then choose Restart." }
        if numbers.lexicographicallyPrecedes([consoleMinimum.major, consoleMinimum.minor]) {
            return "The interactive console needs R \(needed) or later; this R is \(numbers.map(String.init).joined(separator: ".")). Install a current R, then choose Restart."
        }
        return nil
    }
    // A framework directory can appear before Installer has finished. Check that R actually runs.
    static func ready(in paths: [String] = candidates) -> Bool {
        guard let path = executable(in: paths),
              let result = try? RInstallProcess.run(path, ["--vanilla", "-e", "cat('STATSDIRECT_R_READY')"], timeout: 10) else { return false }
        return result.status == 0 && result.output.contains("STATSDIRECT_R_READY")
    }
    static func nativeReady(in paths: [String] = candidates) -> Bool {
        guard let path = executable(in: paths),
              let result = try? RInstallProcess.run(path, ["--vanilla", "-e",
                "if (R.version$arch %in% c('arm64','aarch64')) cat('STATSDIRECT_NATIVE_R_READY')"], timeout: 10) else { return false }
        return result.status == 0 && result.output.contains("STATSDIRECT_NATIVE_R_READY")
    }
}

struct RInstallPackage {
    let version: String
    let url: URL
    let sha256: String
    let minimumOS: Int
    let maximumBytes: Int64

    static func current() throws -> Self {
        #if arch(arm64)
        let package = Self(version: "4.6.1", url: URL(string: "https://cran.r-project.org/bin/macosx/sonoma-arm64/base/R-4.6.1-arm64.pkg")!,
                           sha256: "67f6eea4ced4ce48f0a0d4fa3a1cac43d1859a05a88993ee3dff7c52e7edbc4b", minimumOS: 14, maximumBytes: 150 * 1024 * 1024)
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= package.minimumOS else {
            throw failure("This R installer requires macOS \(package.minimumOS) or later.")
        }
        return package
        #else
        throw failure("Automatic R installation is currently available in the Apple Silicon build of StatsDirect.")
        #endif
    }

    func permits(_ candidate: URL?) -> Bool { candidate == url }
    func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, permits(http.url) else {
            throw Self.failure("The R download did not return the expected package from CRAN. Please try again.")
        }
        guard response.expectedContentLength <= maximumBytes else { throw Self.failure("The R download is larger than expected.") }
    }
    func verifyChecksum(_ file: URL) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && Int64(size) <= maximumBytes else { throw Self.failure("The R download is empty or larger than expected.") }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw Self.failure("The R download failed its integrity check. It has not been opened. Please retry the download.") }
    }
    func verify(_ file: URL) throws {
        try verifyChecksum(file)
        let signature = try RInstallProcess.run("/usr/sbin/pkgutil", ["--check-signature", file.path])
        guard signature.status == 0 && signature.output.contains("Developer ID Installer: Simon Urbanek (VZLD955F6P)") else {
            throw Self.failure("The R installer’s publisher signature could not be verified. It has not been opened.")
        }
        let assessment = try RInstallProcess.run("/usr/sbin/spctl", ["--assess", "--type", "install", file.path], timeout: 60)
        guard assessment.status == 0 else {
            throw Self.failure("macOS could not verify the R installer. Check your connection and try again. It has not been opened.")
        }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "StatsDirect.RInstallation", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

enum RInstallProcess {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> (status: Int32, output: String) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        task.standardOutput = pipe; task.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["LANG"] = "C"
        task.environment = environment
        try task.run()
        let stop = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit(); stop.cancel()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Each request owns an ephemeral session and a private staging directory. Only a verified package is returned.
final class RPackageDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let package: RInstallPackage
    let progress: @Sendable (Double?) -> Void
    init(package: RInstallPackage, progress: @escaping @Sendable (Double?) -> Void = { _ in }) {
        self.package = package; self.progress = progress
    }
    func fetch(into parent: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        let directory = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: directory) } }
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 600
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        try Task.checkCancellation()
        let (temporary, response) = try await session.download(for: URLRequest(url: package.url), delegate: self)
        try Task.checkCancellation()
        try package.validate(response)
        let file = directory.appendingPathComponent(package.url.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: file)
        progress(nil)
        try package.verify(file)
        try Task.checkCancellation()
        keep = true
        return file
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(package.permits(request.url) ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= package.maximumBytes, totalBytesExpectedToWrite <= package.maximumBytes else { downloadTask.cancel(); return }
        progress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
