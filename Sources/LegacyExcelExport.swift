import Cocoa
import UniformTypeIdentifiers

extension Viewer {
    @objc func exportActiveLegacyExcel() {
        guard let doc = active, doc.kind == "grid", !doc.fileBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "xls")!]
        panel.nameFieldStringValue = (doc.workbookName as NSString).deletingPathExtension + "-data.xls"
        panel.message = "Export all worksheets as an Excel 97–2003 data copy. Values and data types are kept; formulas, formatting, charts and macros stay in the original workbook. XLS is limited to 65,536 rows and 256 columns."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            guard !self.isImportedWorkbookSource(url, document: doc) else { self.showError("Choose a new filename to keep the original intact."); return }
            self.exportLegacyExcel(doc, to: url)
        }
    }
    func exportLegacyExcel(_ doc: Document, to url: URL) {
        guard !doc.fileBusy else { return }; doc.fileBusy = true
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.excelSnapshot(true)", arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let info = value as? [String: Any], let id = info["id"] as? String, let file = SnapshotStore.shared.file(for: id) else {
                doc.fileBusy = false; self.showError("The worksheet could not be read for XLS export."); return
            }
            var request: [String: Any] = ["action": "exportXls", "path": url.path, "snapshot": file.path]
            if let workbook = doc.workbookID { request["id"] = workbook }
            self.workbookRequest(request) { result in
                SnapshotStore.shared.forget(id); doc.fileBusy = false
                switch result {
                case .success: self.noteRecentDocument(url); self.gridStatus(doc, "Exported a data copy to " + url.lastPathComponent)
                case .failure(let error): self.showError(error.localizedDescription)
                }
                // Exporting a data copy does not mark a richer source document saved.
            }
        }
    }
}
