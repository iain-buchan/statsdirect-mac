import Cocoa
import WebKit
import UniformTypeIdentifiers

private typealias WorkbookFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias WorkbookFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
private let workbookQueue = DispatchQueue(label: "StatsDirect.Excel", qos: .userInitiated)

extension Viewer {
    func workbookRequest(_ request: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            let json = String(decoding: data, as: UTF8.self)
            if libraryHandle == nil {
                libraryHandle = dlopen(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/StatsDirectEngine.dylib").path, RTLD_NOW | RTLD_LOCAL)
            }
            guard let handle = libraryHandle, let invokeSymbol = dlsym(handle, "statsdirect_workbook"), let freeSymbol = dlsym(handle, "statsdirect_workbook_free") else {
                throw NSError(domain: "StatsDirect.Excel", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not be loaded. Rebuild the viewer."])
            }
            let invoke = unsafeBitCast(invokeSymbol, to: WorkbookFunction.self)
            let free = unsafeBitCast(freeSymbol, to: WorkbookFreeFunction.self)
            workbookQueue.async {
                let result: Result<[String: Any], Error>
                do {
                    guard let pointer = json.withCString({ invoke($0) }) else { throw NSError(domain: "StatsDirect.Excel", code: 2, userInfo: [NSLocalizedDescriptionKey: "The Excel component could not start."]) }
                    let response = String(cString: pointer); free(pointer)
                    guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
                    if let message = object["error"] as? String { throw NSError(domain: "StatsDirect.Excel", code: 3, userInfo: [NSLocalizedDescriptionKey: message]) }
                    result = .success(object)
                } catch { result = .failure(error) }
                DispatchQueue.main.async { completion(result) }
            }
        } catch { completion(.failure(error)) }
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
        workbookRequest(["action": "open", "path": url.path]) { result in
            switch result {
            case .failure(let error): self.status.stringValue = "Excel import failed"; self.showError(error.localizedDescription)
            case .success(let workbook):
                let doc = self.newDocument(kind: "grid", title: url.lastPathComponent, url: self.root.appendingPathComponent("Grid/index.html"))
                doc.workbookID = workbook["id"] as? String
                doc.workbookName = url.lastPathComponent
                doc.pendingWorkbook = workbook
                self.status.stringValue = "Opened \(url.lastPathComponent)"
            }
        }
    }
    func loadPendingWorkbook(_ doc: Document) {
        guard let workbook = doc.pendingWorkbook, let data = try? JSONSerialization.data(withJSONObject: workbook) else { return }
        doc.web.evaluateJavaScript("window.statsDirectGrid.loadWorkbook(\(String(decoding: data, as: UTF8.self)))") { _, error in
            if let error { self.showError("The worksheet could not be displayed: " + error.localizedDescription) }
            else { doc.pendingWorkbook = nil }
        }
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
            doc.web.evaluateJavaScript("JSON.stringify(window.statsDirectGrid.excelData())") { value, error in
                guard error == nil, let json = value as? String, let data = json.data(using: .utf8), var request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    doc.fileBusy = false; self.showError("The workbook could not be read from the grid."); return
                }
                request["action"] = "save"; request["path"] = url.path
                if let id = doc.workbookID { request["id"] = id }
                self.gridStatus(doc, "Saving Excel workbook…")
                self.workbookRequest(request) { result in
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
