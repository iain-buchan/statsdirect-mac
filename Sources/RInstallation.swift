import Foundation
import CryptoKit

enum RRuntime {
    static let candidates = ["/Library/Frameworks/R.framework/Resources/bin/Rscript", "/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript"]
    static func executable(in paths: [String] = candidates) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    // A framework directory can appear before Installer has finished. Check that R actually runs.
    static func ready(in paths: [String] = candidates) -> Bool {
        guard let path = executable(in: paths),
              let result = try? RInstallProcess.run(path, ["--vanilla", "-e", "cat('STATSDIRECT_R_READY')"], timeout: 10) else { return false }
        return result.status == 0 && result.output.contains("STATSDIRECT_R_READY")
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
