import Cocoa
import WebKit
import UniformTypeIdentifiers

private typealias WorkbookFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias WorkbookFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
private let workbookQueue = DispatchQueue(label: "StatsDirect.Excel", qos: .userInitiated)

extension Viewer {
    private func workbookFunctions() throws -> (invoke: WorkbookFunction, free: WorkbookFreeFunction) {
        if libraryHandle == nil {
            libraryHandle = dlopen(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/StatsDirectEngine.dylib").path, RTLD_NOW | RTLD_LOCAL)
        }
        guard let handle = libraryHandle, let invokeSymbol = dlsym(handle, "statsdirect_workbook"), let freeSymbol = dlsym(handle, "statsdirect_workbook_free") else {
            throw NSError(domain: "StatsDirect.Excel", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not be loaded. Rebuild the viewer."])
        }
        return (unsafeBitCast(invokeSymbol, to: WorkbookFunction.self), unsafeBitCast(freeSymbol, to: WorkbookFreeFunction.self))
    }
    // Runs on the workbook queue.
    private static func call(_ functions: (invoke: WorkbookFunction, free: WorkbookFreeFunction), _ json: String) throws -> [String: Any] {
        guard let pointer = json.withCString({ functions.invoke($0) }) else { throw NSError(domain: "StatsDirect.Excel", code: 2, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not start."]) }
        let response = String(cString: pointer); functions.free(pointer)
        guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        if let message = object["error"] as? String { throw NSError(domain: "StatsDirect.Excel", code: 3, userInfo: [NSLocalizedDescriptionKey: message]) }
        return object
    }
    func workbookRequest(_ request: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            let json = String(decoding: data, as: UTF8.self)
            let functions = try workbookFunctions()
            workbookQueue.async {
                let result = Result { try Viewer.call(functions, json) }
                DispatchQueue.main.async { completion(result) }
            }
        } catch { completion(.failure(error)) }
    }
    // At quit: the engine deletes its private copy of each open workbook. Waits for the queue
    // so a save in progress finishes first.
    func closeOpenWorkbooks() {
        let ids = documents.compactMap { $0.workbookID }
        guard !ids.isEmpty, let functions = try? workbookFunctions() else { return }
        workbookQueue.sync {
            for id in ids { _ = try? Viewer.call(functions, "{\"action\":\"close\",\"id\":\"\(id)\"}") }
        }
    }
    @objc func openExcel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.openExcelURL(url) }
        }
    }
    @objc func openExampleWorkbook() { openExcelURL(root.appendingPathComponent("Examples/test.xlsx")) }
    func openExcelURL(_ url: URL) {
        status.stringValue = "Opening \(url.lastPathComponent)…"
        // The engine writes each sheet's cells to a typed snapshot file; the grid fetches them by id.
        workbookRequest(["action": "open", "path": url.path, "snapshot": SnapshotStore.shared.directory.path]) { result in
            switch result {
            case .failure(let error): self.status.stringValue = "Excel import failed"; self.showError(error.localizedDescription)
            case .success(var workbook):
                let doc = self.newDocument(kind: "grid", title: url.lastPathComponent, url: self.root.appendingPathComponent("Grid/index.html"))
                doc.workbookID = workbook["id"] as? String
                doc.workbookName = url.lastPathComponent
                workbook["sheets"] = (workbook["sheets"] as? [[String: Any]] ?? []).map { sheet -> [String: Any] in
                    var sheet = sheet
                    if let path = sheet["snapshot"] as? String {
                        let id = SnapshotStore.shared.register(URL(fileURLWithPath: path)); doc.snapshotIDs.append(id)
                        sheet["snapshot"] = SnapshotStore.shared.url(for: id)
                    }
                    return sheet
                }
                doc.pendingWorkbook = workbook
                self.status.stringValue = "Opened \(url.lastPathComponent)"
            }
        }
    }
    func loadPendingWorkbook(_ doc: Document) {
        guard let workbook = doc.pendingWorkbook else { return }
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.loadWorkbook(data)", arguments: ["data": workbook], in: nil, in: .page) { result in
            guard self.documents.contains(where: { $0 === doc }) else { return }
            for id in doc.snapshotIDs { SnapshotStore.shared.forget(id) }; doc.snapshotIDs = []
            switch result {
            case .failure(let error): self.showError("The worksheet could not be displayed: " + self.javaScriptMessage(error))
            case .success: doc.pendingWorkbook = nil
            }
        }
    }
    func javaScriptMessage(_ error: Error) -> String {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }
    @objc func saveActiveExcel() { if let doc = active, doc.kind == "grid" { saveExcel(doc) } }
    @objc func exportActiveCSV() { if let doc = active, doc.kind == "grid" { saveGrid(doc) } }
    func saveExcel(_ doc: Document) {
        guard !doc.fileBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        let stem = (doc.workbookName as NSString).deletingPathExtension
        panel.nameFieldStringValue = stem + "-edited.xlsx"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let version = doc.gridVersion
            doc.fileBusy = true
            // The grid stores a typed snapshot of the cells to write; the engine reads it by path.
            doc.web.callAsyncJavaScript("return window.statsDirectGrid.excelSnapshot()", arguments: [:], in: nil, in: .page) { result in
                guard case .success(let value) = result, let info = value as? [String: Any], let snapshotID = info["id"] as? String, let file = SnapshotStore.shared.file(for: snapshotID) else {
                    doc.fileBusy = false
                    if case .failure(let error) = result { self.showError("The workbook could not be read from the grid. " + self.javaScriptMessage(error)) }
                    else { self.showError("The workbook could not be read from the grid.") }
                    return
                }
                var request: [String: Any] = ["action": "save", "path": url.path, "snapshot": file.path]
                if let id = doc.workbookID { request["id"] = id }
                self.gridStatus(doc, "Saving Excel workbook…")
                self.workbookRequest(request) { result in
                    SnapshotStore.shared.forget(snapshotID)
                    doc.fileBusy = false
                    switch result {
                    case .failure(let error): self.gridStatus(doc, "Excel save failed"); self.showError(error.localizedDescription)
                    case .success(let saved):
                        if version == doc.gridVersion { doc.gridDirty = false }
                        let missing = saved["uncachedFormulas"] as? Int ?? 0
                        self.gridStatus(doc, "Saved all worksheets to " + url.lastPathComponent + (missing > 0 ? ". \(missing) formula results require recalculation in Excel." : ""))
                    }
                }
            }
        }
    }
}
