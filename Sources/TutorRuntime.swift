import Foundation
import CryptoKit
import Darwin

/// Trusted application metadata pins both the download and every extracted runtime file.
struct TutorRuntimePackage: Codable, Sendable {
    struct File: Codable, Sendable { let size: Int; let sha256: String }
    let version: String
    let url: URL
    let sha256: String
    let maximumBytes: Int64
    let teamIdentifier: String
    let signingIdentifier: String
    let files: [String: File]
    var folderName: String { version + "-" + sha256.prefix(12) }
    static func load(_ resources: URL) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: resources.appendingPathComponent("runtime.json")))
        guard value.url.scheme == "https", value.url.host == "github.com", value.url.path.hasPrefix("/openai/codex/releases/download/"),
              value.url.user == nil, value.url.password == nil, value.url.port == nil,
              value.version.range(of: "^[0-9.]+$", options: .regularExpression) != nil,
              value.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              value.maximumBytes > 0, value.maximumBytes <= 200 * 1024 * 1024,
              value.teamIdentifier == "2DC432GLL2", value.signingIdentifier == "codex-app-server",
              !value.files.isEmpty, value.files["bin/codex-app-server"] != nil,
              value.files.values.allSatisfy({ $0.size > 0 && $0.size <= 300 * 1024 * 1024 && $0.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil }),
              value.files.keys.allSatisfy(Self.safePath) else { throw failure("The AI download information is invalid. Install the latest StatsDirect build.") }
        return value
    }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") && !path.contains("\n") && !path.split(separator:"/",omittingEmptySubsequences:false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }
    func permits(_ candidate: URL?) -> Bool {
        guard let candidate, candidate.user == nil, candidate.password == nil else { return false }
        if candidate == url { return true }
        return candidate.scheme == "https" && candidate.port == nil && candidate.host == "release-assets.githubusercontent.com"
    }
    static func failure(_ text: String) -> NSError { NSError(domain:"StatsDirect.TutorRuntime",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount:1024 * 1024), !block.isEmpty { try Task.checkCancellation(); hash.update(data:block) }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    func verifyArchive(_ file: URL) throws {
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size > 0, Int64(size) <= maximumBytes, try Self.digest(file) == sha256 else { throw Self.failure("The AI download failed its integrity check. Please retry.") }
    }
    func verifyPublisher(_ directory: URL) throws {
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(signingIdentifier)\""
        let result = try Self.run("/usr/bin/codesign",["--verify","--strict","-R","="+requirement,directory.appendingPathComponent("bin/codex-app-server").path])
        guard result == 0 else { throw Self.failure("The AI component's OpenAI publisher signature could not be verified. Please retry.") }
    }
    func verifyFiles(_ directory: URL) throws {
        let manager = FileManager.default
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw Self.failure("The AI installation folder must not be a symbolic link.") }
        for (name, expected) in files {
            try Task.checkCancellation()
            let file = directory.appendingPathComponent(name)
            let info = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == expected.size,
                  file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL,
                  try Self.digest(file) == expected.sha256 else { throw Self.failure("The installed AI component is incomplete or has changed. Choose Use my ChatGPT to repair it.") }
        }
        let allowed = Set(files.keys).union(["LICENSE","NOTICE","STATSDIRECT-RUNTIME.json"])
        guard let items = manager.enumerator(at:directory,includingPropertiesForKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey]) else { throw Self.failure("The AI installation cannot be read.") }
        for case let item as URL in items {
            let info = try item.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey])
            let name = String(item.path.dropFirst(directory.path.count + 1))
            guard info.isSymbolicLink != true, info.isDirectory == true || info.isRegularFile == true && allowed.contains(name) else { throw Self.failure("The AI installation contains an unexpected file. Choose Use my ChatGPT to repair it.") }
        }
        guard manager.isExecutableFile(atPath:directory.appendingPathComponent("bin/codex-app-server").path) else { throw Self.failure("The AI component cannot be started. Choose Use my ChatGPT to repair it.") }
    }
    static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        try Task.checkCancellation()
        let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        process.environment = ["PATH":"/usr/bin:/bin:/usr/sbin:/sbin","LANG":"C","LC_ALL":"C"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:timeout)
        process.waitUntilExit(); timeout.cancel(); try Task.checkCancellation()
        return process.terminationStatus
    }
}

/// Download never sees account credentials. Its only output is an unexecuted pinned archive.
final class TutorRuntimeDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let package: TutorRuntimePackage
    let progress: @Sendable (Double?) -> Void
    init(_ package: TutorRuntimePackage, progress: @escaping @Sendable (Double?) -> Void) { self.package=package; self.progress=progress }
    func fetch(to file: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=30; config.timeoutIntervalForResource=600
        config.httpCookieStorage=nil; config.urlCredentialStorage=nil; config.urlCache=nil
        let session=URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let (temporary,response)=try await session.download(for:URLRequest(url:package.url),delegate:self)
        try Task.checkCancellation()
        guard let response=response as? HTTPURLResponse, response.statusCode == 200, package.permits(response.url), response.expectedContentLength <= package.maximumBytes else { throw TutorRuntimePackage.failure("The AI download could not be completed from GitHub. Check your connection and retry.") }
        try FileManager.default.moveItem(at:temporary,to:file)
        progress(nil); try package.verifyArchive(file)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(package.permits(request.url) ? request : nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= package.maximumBytes, totalBytesExpectedToWrite <= package.maximumBytes else { downloadTask.cancel(); return }
        progress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten)/Double(totalBytesExpectedToWrite) : 0)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// Private staging and an interprocess lock keep cancellation/failure away from installed bytes.
enum TutorRuntimeInstallation {
    static func verify(_ package: TutorRuntimePackage, at directory: URL) async throws {
        try package.verifyFiles(directory); try package.verifyPublisher(directory)
    }
    static func install(_ package: TutorRuntimePackage, root: URL, resources: URL,
                        progress: @escaping @Sendable (Double?) -> Void,
                        download: (@Sendable (URL) async throws -> Void)? = nil,
                        publisher: (@Sendable (URL) throws -> Void)? = nil) async throws -> URL {
        try Task.checkCancellation()
        let manager=FileManager.default
        try manager.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else { throw TutorRuntimePackage.failure("The AI setup folder must not be a symbolic link.") }
        let lock=open(root.appendingPathComponent(".install.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock >= 0 else { throw TutorRuntimePackage.failure("The AI installation folder cannot be written.") }
        defer { close(lock) }
        guard flock(lock,LOCK_EX|LOCK_NB) == 0 else { throw TutorRuntimePackage.failure("Another StatsDirect instance is setting up AI. Wait for it to finish, then retry.") }
        defer { flock(lock,LOCK_UN) }
        // A force-quit can bypass defer. With the lock held, no live setup owns these.
        for item in try manager.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            where item.lastPathComponent.hasPrefix(".staging-") && UUID(uuidString:String(item.lastPathComponent.dropFirst(9))) != nil {
            try manager.removeItem(at:item)
        }
        let destination=root.appendingPathComponent(package.folderName)
        if (try? package.verifyFiles(destination)) != nil {
            try (publisher ?? package.verifyPublisher)(destination); return destination
        }
        try Task.checkCancellation()
        let stage=root.appendingPathComponent(".staging-"+UUID().uuidString)
        try manager.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? manager.removeItem(at:stage) }
        let archive=stage.appendingPathComponent("package.tar.gz"), unpacked=stage.appendingPathComponent("runtime")
        try manager.createDirectory(at:unpacked,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        if let download { try await download(archive) } else { try await TutorRuntimeDownload(package,progress:progress).fetch(to:archive) }
        try Task.checkCancellation(); progress(nil); try package.verifyArchive(archive)
        // Only extract the exact pinned archive. Every extracted file is checked before execution.
        guard try TutorRuntimePackage.run("/usr/bin/tar",["-xzf",archive.path,"--no-same-owner","--no-same-permissions","-C",unpacked.path]) == 0 else { throw TutorRuntimePackage.failure("The AI download could not be unpacked. Please retry.") }
        try package.verifyFiles(unpacked); try (publisher ?? package.verifyPublisher)(unpacked)
        for name in ["LICENSE","NOTICE"] { try manager.copyItem(at:resources.appendingPathComponent("Runtime-"+name),to:unpacked.appendingPathComponent(name)) }
        try JSONEncoder().encode(package).write(to:unpacked.appendingPathComponent("STATSDIRECT-RUNTIME.json"),options:.atomic)
        try Task.checkCancellation()
        if manager.fileExists(atPath:destination.path) {
            // Swap directories atomically: failed promotion never removes the previous install.
            guard renameatx_np(AT_FDCWD,unpacked.path,AT_FDCWD,destination.path,UInt32(RENAME_SWAP)) == 0 else {
                throw Self.installationError()
            }
        } else { try manager.moveItem(at:unpacked,to:destination) }
        return destination
    }
    private static func installationError() -> NSError {
        TutorRuntimePackage.failure("The AI component could not be installed. Check the available disk space and folder permissions, then retry.")
    }
}
