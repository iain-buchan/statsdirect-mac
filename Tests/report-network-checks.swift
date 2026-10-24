import Cocoa
import WebKit

extension ReportExportTests {
    /// The Windows report view answers every request outside its own origin, data: and blob: with 403. The Mac's document
    /// pages must make no network request either, whatever markup a report carries (an imported notebook or HTML file can
    /// hold poster, background and image URLs): a local listener must see only the control request made from outside.
    @MainActor static func networkIsolation(_ v: Viewer, output: URL) async throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw NSError(domain: "NetworkIsolationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let log = output.appendingPathComponent("network-isolation.log")
        try? FileManager.default.removeItem(at: log); FileManager.default.createFile(atPath: log.path, contents: nil)
        let port = Int.random(in: 20000...40000), base = "http://127.0.0.1:\(port)/"
        let server = Process(); server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1"]; server.currentDirectoryURL = output
        let handle = try FileHandle(forWritingTo: log); server.standardOutput = handle; server.standardError = handle
        try server.run(); defer { server.terminate() }
        // Control, from outside the web views: the listener answers and logs a request.
        var answered = false
        for _ in 0..<200 where !answered {
            let client = Process(); client.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            client.arguments = ["-c", "import urllib.request,urllib.error\ntry: urllib.request.urlopen('\(base)probe', timeout=2)\nexcept urllib.error.HTTPError: pass"]
            client.standardError = FileHandle.nullDevice; try client.run(); client.waitUntilExit()
            answered = client.terminationStatus == 0
            if !answered { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        try require(answered, "the local listener answers the control request")
        for _ in 0..<100 where Document.networkBlock == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        try require(Document.networkBlock != nil, "the network block rules compiled at launch")
        let doc = v.makeReport()
        doc.reportEntries = [ReportEntry(id: "network-references", title: "External references", operation: "",
            body: "<p>External references</p><video poster='\(base)poster.png'></video><table background='\(base)table.png'><tr><td background='\(base)cell.png'>x</td></tr></table><img src='\(base)image.png' alt='External image'><p style='background-image:url(\(base)style.png)'>styled</p>", record: nil)]
        v.renderReport(doc); try await settled(doc)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let lines = String(decoding: try Data(contentsOf: log), as: UTF8.self).split(separator: "\n")
        let pageHits = lines.filter { $0.contains("GET /") && !$0.contains("/probe") }
        try require(lines.contains { $0.contains("GET /probe") }, "the control request reached the listener")
        try require(pageHits.isEmpty, "document pages make no network requests; the listener saw: " + pageHits.joined(separator: " | "))
        v.remove(doc)
        print("PASS: document web views make no network request for poster, background, image or CSS URLs, as the Windows report view refuses them"); fflush(stdout)
    }
}
