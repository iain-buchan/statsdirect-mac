import Cocoa
import WebKit
import UniformTypeIdentifiers

extension Viewer {
    @objc func openRData() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = ["rds", "rdata", "rda"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.openRDataURL(url)
        }
    }
    func openRDataURL(_ url: URL) {
        guard RRuntime.executable() != nil else {
            RInstaller.shared.ensureInstalled { [weak self] installed in if installed { self?.openRDataURL(url) } }
            return
        }
        let script = root.appendingPathComponent("R/data-files.R")
        status.stringValue = "Opening " + url.lastPathComponent + "…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try RDataFileIO.read(url, script: script) }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error): self.showError(error.localizedDescription)
                case .success(let workbook):
                    let doc = self.newDocument(kind: "grid", title: url.lastPathComponent, url: self.root.appendingPathComponent("Grid/index.html"))
                    doc.workbookName = url.lastPathComponent; doc.pendingWorkbook = workbook
                    doc.rDataFormat = url.pathExtension.lowercased() == "rds" ? "rds" : "RData"
                    self.status.stringValue = "Opened " + url.lastPathComponent
                }
            }
        }
    }
    @objc func saveActiveRDS() { if let doc = active, doc.kind == "grid" { saveRData(doc, format: "rds") } }
    @objc func saveActiveRData() { if let doc = active, doc.kind == "grid" { saveRData(doc, format: "RData") } }
    func saveRData(_ doc: Document, format: String) {
        guard !doc.fileBusy else { return }
        guard RRuntime.executable() != nil else {
            RInstaller.shared.ensureInstalled { [weak self, weak doc] installed in
                guard installed, let self, let doc, self.documents.contains(where: { $0 === doc }) else { return }
                self.saveRData(doc, format: format)
            }
            return
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = (format == "rds" ? ["rds"] : ["rdata", "rda"]).compactMap { UTType(filenameExtension: $0) }
        panel.nameFieldStringValue = (doc.workbookName as NSString).deletingPathExtension + "-edited." + format
        panel.message = format == "rds" ? "Save the current worksheet as one R table." : "Save all worksheets as named R tables."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let version = doc.gridVersion; doc.fileBusy = true
            doc.web.evaluateJavaScript("window.statsDirectGrid.rDataSnapshot(\(format == "rds"))") { value, error in
                guard error == nil, let snapshot = value as? [String: Any], let tables = snapshot["tables"] as? [[String: Any]] else {
                    doc.fileBusy = false; self.showError("The R tables could not be read. " + (error?.localizedDescription ?? "")); return
                }
                let script = self.root.appendingPathComponent("R/data-files.R")
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try RDataFileIO.write(tables, to: url, format: format.lowercased(), script: script) }
                    DispatchQueue.main.async {
                        doc.fileBusy = false
                        switch result {
                        case .failure(let error): self.showError(error.localizedDescription)
                        case .success:
                            if snapshot["canSaveDocument"] as? Bool == true && doc.workbookID == nil {
                                doc.rDataFormat = format; doc.csvSaveName = nil
                                if doc.gridVersion == version { doc.gridDirty = false }
                            }
                            self.gridStatus(doc, "Saved " + String(tables.count) + " R table(s) to " + url.lastPathComponent)
                            self.status.stringValue = "Saved " + url.lastPathComponent
                        }
                    }
                }
            }
        }
    }
}
