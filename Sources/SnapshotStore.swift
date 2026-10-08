import Cocoa
import WebKit

// Worksheet cells travel between the engine, grid pages and derived worksheets as typed
// columnar snapshot files (Grid/snapshot.mjs, FullEngine/WorkbookIO.cs), never as JSON.
// A page fetches a snapshot by id (GET sdsnapshot://blob/<id>) and stores one with
// POST sdsnapshot://blob, which answers {"id", "bytes"}. Files live in a per-process
// temporary folder and are deleted when their document closes or the application quits.
@MainActor
final class SnapshotStore: NSObject, WKURLSchemeHandler {
    static let shared = SnapshotStore()
    static let scheme = "sdsnapshot"
    let directory: URL
    private var files: [String: URL] = [:]
    private var active = Set<ObjectIdentifier>()
    private override init() {
        let temporary = FileManager.default.temporaryDirectory
        directory = temporary.appendingPathComponent("StatsDirect-snapshots-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        super.init()
        sweep(temporary)
    }
    // Folders left by earlier processes that no longer run (a crash, a kill) are removed.
    private func sweep(_ temporary: URL) {
        let prefix = "StatsDirect-snapshots-"
        for item in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            let name = item.lastPathComponent
            guard name.hasPrefix(prefix), let pid = Int32(name.dropFirst(prefix.count)), pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH { try? FileManager.default.removeItem(at: item) }
        }
    }
    func register(_ file: URL) -> String { let id = UUID().uuidString; files[id] = file; return id }
    func file(for id: String) -> URL? { files[id] }
    func url(for id: String) -> String { "\(Self.scheme)://blob/\(id)" }
    func forget(_ id: String) { if let file = files.removeValue(forKey: id) { try? FileManager.default.removeItem(at: file) } }
    func shutdown() { files = [:]; try? FileManager.default.removeItem(at: directory) }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let key = ObjectIdentifier(task); active.insert(key)
        let request = task.request
        guard let url = request.url else { task.didFailWithError(URLError(.badURL)); return }
        func respond(_ status: Int, _ data: Data, _ type: String) {
            guard active.contains(key) else { return }
            active.remove(key)
            let headers = ["Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "*",
                           "Cache-Control": "no-store", "Content-Type": type, "Content-Length": String(data.count)]
            task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
            if !data.isEmpty { task.didReceive(data) }
            task.didFinish()
        }
        let text = { (message: String) in Data(message.utf8) }
        switch request.httpMethod ?? "GET" {
        case "OPTIONS": respond(204, Data(), "text/plain")
        case "POST":
            guard url.host == "blob", let body = request.httpBody else { respond(400, text("A snapshot body is required."), "text/plain"); return }
            let file = directory.appendingPathComponent(UUID().uuidString + ".sdcol")
            DispatchQueue.global(qos: .userInitiated).async {
                let written = (try? body.write(to: file, options: .atomic)) != nil
                DispatchQueue.main.async {
                    guard written else { respond(500, text("The snapshot could not be stored."), "text/plain"); return }
                    let id = self.register(file)
                    respond(200, text("{\"id\":\"\(id)\",\"bytes\":\(body.count)}"), "application/json")
                }
            }
        case "GET":
            guard url.host == "blob", let id = url.pathComponents.last, let file = files[id] else { respond(404, text("No such snapshot."), "text/plain"); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: file)
                DispatchQueue.main.async {
                    if let data { respond(200, data, "application/octet-stream") } else { respond(404, text("The snapshot file is missing."), "text/plain") }
                }
            }
        default: respond(405, text("Method not allowed."), "text/plain")
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { active.remove(ObjectIdentifier(task)) }
}
