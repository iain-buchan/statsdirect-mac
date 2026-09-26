import Foundation
import CryptoKit

@main struct RInstallationTests {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Unsafe package accepted") } catch {}
    }
    static func main() async throws {
        let package = try RInstallPackage.current()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("R-install-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.pkg")
        try Data("not an installer".utf8).write(to: file)
        precondition(RRuntime.executable(in: [file.path]) == nil)
        precondition(RRuntime.executable(in: ["/does/not/exist", "/bin/sh"]) == "/bin/sh")
        precondition(!RRuntime.ready(in: ["/does/not/exist"]))
        precondition(!RRuntime.ready(in: ["/usr/bin/false"]))
        rejects { try package.verifyChecksum(file) }
        let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        let fixture = RInstallPackage(version: "fixture", url: package.url, sha256: digest, minimumOS: 14, maximumBytes: 100)
        try fixture.verifyChecksum(file)
        rejects { try fixture.verify(file) } // Matching checksum is insufficient: it must also be an Apple-trusted R installer.
        try Data().write(to: file); rejects { try fixture.verifyChecksum(file) }
        try Data(repeating: 0, count: 101).write(to: file); rejects { try fixture.verifyChecksum(file) }
        for url in ["http://cran.r-project.org/bin/macosx/sonoma-arm64/base/R-4.6.1-arm64.pkg", "https://example.org/R.pkg", package.url.absoluteString + "?other=1", "https://cran.r-project.org/bin/macosx/R-4.6.0-arm64.pkg"] {
            precondition(!package.permits(URL(string: url)))
        }
        for status in [302, 404, 500] {
            rejects { try package.validate(HTTPURLResponse(url: package.url, statusCode: status, httpVersion: nil, headerFields: nil)!) }
        }
        rejects { try package.validate(HTTPURLResponse(url: URL(string: "https://example.org/R.pkg")!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        rejects { try package.validate(HTTPURLResponse(url: package.url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "999999999"])!) }
        try package.validate(HTTPURLResponse(url: package.url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "105066342"])!)
        print("PASS runtime detection, failed probes, pinned URL, HTTP failures, size, checksum and unsigned-file rejection")

        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--fetch" {
            let download = RPackageDownload(package: package)
            let file = try await download.fetch(into: folder)
            try package.verify(file)
            precondition(RRuntime.ready()) // Existing local R remains untouched.
            print("PASS real CRAN download through URLSession, SHA-256, R publisher signature and macOS installer assessment; existing R remains runnable")
        } else if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--failure" {
            let url = URL(string: CommandLine.arguments[2])!
            let candidate = RInstallPackage(version: "fixture", url: url, sha256: digest, minimumOS: 14, maximumBytes: 100)
            let task = Task { try await RPackageDownload(package: candidate).fetch(into: folder) }
            if CommandLine.arguments.contains("--cancel") {
                try await Task.sleep(for: .milliseconds(100)); task.cancel()
            }
            do { _ = try await task.value; fatalError("Failed download accepted") } catch {}
            let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            precondition(remaining == ["fixture.pkg"])
            print("PASS failed/cancelled download removed its staging directory")
        }
    }
}
