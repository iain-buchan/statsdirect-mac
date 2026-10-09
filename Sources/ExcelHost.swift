import Cocoa
import WebKit
import UniformTypeIdentifiers

private typealias WorkbookFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias WorkbookFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
private let workbookQueue = DispatchQueue(label: "StatsDirect.Excel", qos: .userInitiated)

extension Viewer {
    static let excelExtensions = ["xlsx", "xls", "xlsb", "xlsm", "xlt", "xltx", "xltm"]
    private func workbookFunctions() throws -> (invoke: WorkbookFunction, free: WorkbookFreeFunction) {
        if libraryHandle == nil {
            libraryHandle = dlopen(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/StatsDirectEngine.dylib").path, RTLD_NOW | RTLD_LOCAL)
        }
        guard let handle = libraryHandle, let invokeSymbol = dlsym(handle, "statsdirect_workbook"), let freeSymbol = dlsym(handle, "statsdirect_workbook_free") else {
            throw NSError(domain: "StatsDirect.Excel", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not be loaded. Rebuild the viewer."])
        }
        return (unsafeBitCast(invokeSymbol, to: WorkbookFunction.self), unsafeBitCast(freeSymbol, to: WorkbookFreeFunction.self))
    }
    // Runs on the serial workbook queue; uses only the supplied entry points and JSON,
    // never Viewer's main-actor state. Resolve the library functions on the main actor first.
    nonisolated private static func call(_ functions: (invoke: WorkbookFunction, free: WorkbookFreeFunction), _ json: String) throws -> [String: Any] {
        guard let pointer = json.withCString({ functions.invoke($0) }) else { throw NSError(domain: "StatsDirect.Excel", code: 2, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not start."]) }
        let response = String(cString: pointer); functions.free(pointer)
        guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        if let message = object["error"] as? String {
            throw NSError(domain: "StatsDirect.Excel", code: 3, userInfo: [NSLocalizedDescriptionKey: message, "workbookErrorCode": object["code"] as? String ?? ""])
        }
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
    // Validate against the immutable source package before committing a structural grid edit.
    // The grid token also checks every sheet's revision, so edits made during the check
    // cannot be overwritten by the result of an earlier analysis.
    func writeAnalysisFrames(_ request: [String: Any], to doc: Document, completion: @escaping @MainActor (Result<Any, Error>) -> Void) {
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.prepareWriteFrames(request)", arguments: ["request": request], in: nil, in: .page) { prepared in
            guard case .success(let value) = prepared, let info = value as? [String: Any], let token = info["token"] as? String else {
                if case .failure(let error) = prepared { completion(.failure(error)) }
                else { completion(.failure(CocoaError(.fileReadCorruptFile))) }
                return
            }
            @MainActor func commit() {
                guard self.documents.contains(where: { $0 === doc }) else { completion(.failure(CocoaError(.userCancelled))); return }
                doc.web.callAsyncJavaScript("return window.statsDirectGrid.writeFrames(request)", arguments: ["request": ["token": token]], in: nil, in: .page) { result in completion(result) }
            }
            if info["validate"] as? Bool == true {
                guard let id = doc.workbookID else { completion(.failure(CocoaError(.fileReadNoSuchFile))); return }
                self.status.stringValue = "Checking worksheet column insertion…"
                self.workbookRequest(["action": "validateInserts", "id": id, "inserts": info["inserts"] ?? []]) { result in
                    switch result {
                    case .success: commit()
                    case .failure(let error):
                        doc.web.callAsyncJavaScript("window.statsDirectGrid.cancelWriteFrames(token)", arguments: ["token": token], in: nil, in: .page) { _ in completion(.failure(error)) }
                    }
                }
            } else { commit() }
        }
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
        let panel = NSOpenPanel(); panel.allowedContentTypes = Self.excelExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.openExcelURL(url) }
        }
    }
    @objc func openExampleWorkbook() { openExcelURL(root.appendingPathComponent("Examples/test.xlsx")) }
    func openExcelURL(_ url: URL, password: String? = nil) {
        status.stringValue = "Opening \(url.lastPathComponent)…"
        // The engine writes each sheet's cells to a typed snapshot file; the grid fetches them by id.
        var request: [String: Any] = ["action": "open", "path": url.resolvingSymlinksInPath().path, "snapshot": SnapshotStore.shared.directory.path]
        if let password { request["password"] = password }
        workbookRequest(request) { result in
            switch result {
            case .failure(let error):
                if (error as NSError).userInfo["workbookErrorCode"] as? String == "workbookPassword" {
                    self.askWorkbookPassword(url, retry: password != nil)
                } else { self.status.stringValue = "Excel import failed"; self.showError(error.localizedDescription) }
            case .success(var workbook):
                let doc = self.newDocument(kind: "grid", title: url.lastPathComponent, url: self.root.appendingPathComponent("Grid/index.html"))
                doc.workbookID = workbook["id"] as? String
                doc.workbookName = url.lastPathComponent
                doc.workbookSourceURL = url.resolvingSymlinksInPath()
                doc.workbookDataCopy = workbook["dataCopy"] as? Bool == true
                self.stageSnapshots(in: &workbook, for: doc)
                doc.pendingWorkbook = workbook
                self.status.stringValue = "Opened \(url.lastPathComponent)"
            }
        }
    }
    func askWorkbookPassword(_ url: URL, retry: Bool) {
        let alert = NSAlert()
        alert.messageText = retry ? "The workbook password was not accepted" : "Enter the workbook password"
        alert.informativeText = "\(url.lastPathComponent) needs its opening password. The password is used only to open this file and is not saved."
        alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Workbook password"
        field.setAccessibilityLabel("Workbook password")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        status.stringValue = "Waiting for workbook password"
        alert.beginSheetModal(for: window) { response in
            let password = field.stringValue
            field.stringValue = ""
            if response == .alertFirstButtonReturn { self.openExcelURL(url, password: password) }
            else { self.status.stringValue = "Opening cancelled" }
        }
    }
    // Values-only exports must never replace the source, including a selected filesystem alias.
    func isImportedWorkbookSource(_ url: URL, document: Document) -> Bool {
        guard document.workbookDataCopy, let source = document.workbookSourceURL else { return false }
        if source.resolvingSymlinksInPath().path.caseInsensitiveCompare(url.resolvingSymlinksInPath().path) == .orderedSame { return true }
        let a = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let b = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        return a != nil && b != nil && (a as? NSObject)?.isEqual(b) == true
    }
    // Sheets whose cells sit in a snapshot file (written by the engine or by R import) are
    // registered with the snapshot store, which serves them to the grid by id and deletes
    // them once the document has loaded or closes.
    func stageSnapshots(in workbook: inout [String: Any], for doc: Document) {
        workbook["sheets"] = (workbook["sheets"] as? [[String: Any]] ?? []).map { sheet -> [String: Any] in
            var sheet = sheet
            if let path = sheet["snapshot"] as? String {
                let id = SnapshotStore.shared.register(URL(fileURLWithPath: path)); doc.snapshotIDs.append(id)
                sheet["snapshot"] = SnapshotStore.shared.url(for: id)
            }
            return sheet
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
        panel.nameFieldStringValue = stem + (doc.workbookDataCopy ? "-data.xlsx" : "-edited.xlsx")
        if doc.workbookDataCopy { panel.message = "Save the imported values as a new workbook. The original keeps its formulas, formatting, macros and any password protection." }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            guard !self.isImportedWorkbookSource(url, document: doc) else {
                self.showError("Choose a new filename to keep the original workbook intact.")
                return
            }
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
                if let inserts = info["inserts"] as? [[String: Any]], !inserts.isEmpty { request["inserts"] = inserts }
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
