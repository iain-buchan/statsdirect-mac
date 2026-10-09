import Cocoa

struct ExcelImportTests {
    @MainActor static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    @MainActor static func passwordSheet(_ v: Viewer) async throws -> (NSWindow, NSSecureTextField) {
        try await ProviderLearningTests.wait { v.window.attachedSheet?.contentView.map { descendants($0).contains { $0 is NSSecureTextField } } == true }
        let sheet = v.window.attachedSheet!
        return (sheet, descendants(sheet.contentView!).compactMap { $0 as? NSSecureTextField }.first!)
    }
    @MainActor static func loaded(_ v: Viewer, _ url: URL) async throws -> Document {
        try await ProviderLearningTests.wait { v.documents.contains { $0.workbookSourceURL == url && $0.pendingWorkbook == nil } }
        return v.documents.last { $0.workbookSourceURL == url }!
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/Excel")
        let initial = v.documents.count
        // Open through the application host, read the served typed snapshots in WebKit,
        // and verify that every loaded value is included in a values-only export.
        for name in ["10x10.xls", "10x10.xlsb", "strict/10x10.xlsx"] {
            let url = root.appendingPathComponent(name)
            v.openExcelURL(url)
            let doc = try await loaded(v, url)
            try check(doc.workbookDataCopy && doc.workbookID != nil, "Expected compatibility import for \(name)")
            let actual = try await v.learningJavaScript(doc, "({cells:statsDirectGrid.excelData().sheets[0].cells,note:document.querySelector('.formula-note')?.textContent})")
            let cells = actual["cells"] as! [[String:Any]]
            try check(cells.count == 71, "All 71 cells must be exported, not only edits: \(name)")
            try check(cells.contains { $0["col"] as? Int == 0 && $0["row"] as? Int == 1 && $0["text"] as? String == "10x10" }, "Original cell positions")
            try check((actual["note"] as? String)?.contains("last Excel save") == true, "Persistent cached-results notice")
            try check(v.isImportedWorkbookSource(url, document: doc), "Source overwrite protection")
            let another = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("statsdirect-excel-export-\(UUID().uuidString).xlsx")
            try check(!v.isImportedWorkbookSource(another, document: doc), "New filename must be available")
            v.remove(doc)
        }
        print("PASS: native XLS/XLSB/Strict XLSX import, snapshot loading, all-cell export and persistent import notice")

        let encrypted = root.appendingPathComponent("agile_AES256_SHA512_CBC_pwd_password.xlsx")
        v.openExcelURL(encrypted)
        let (first, _) = try await passwordSheet(v)
        v.window.endSheet(first, returnCode: .alertSecondButtonReturn)
        try await ProviderLearningTests.wait { v.status.stringValue == "Opening cancelled" && v.window.attachedSheet == nil }
        try check(v.documents.count == initial, "Cancel must not create a partial worksheet")
        v.openExcelURL(encrypted)
        let (wrong, field) = try await passwordSheet(v)
        field.stringValue = "wrong-password"
        v.window.endSheet(wrong, returnCode: .alertFirstButtonReturn)
        try await ProviderLearningTests.wait {
            guard let sheet = v.window.attachedSheet, sheet !== wrong, let view = sheet.contentView else { return false }
            return descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "The workbook password was not accepted" }
        }
        let (retry, secure) = try await passwordSheet(v)
        try check(secure.stringValue.isEmpty, "Wrong password must not remain in the field")
        secure.stringValue = "password" // Public synthetic fixture password, never a user credential.
        v.window.endSheet(retry, returnCode: .alertFirstButtonReturn)
        let doc = try await loaded(v, encrypted)
        let values = try await v.learningJavaScript(doc, "({text:statsDirectGrid.excelData().sheets[0].cells[0].text})")
        try check(values["text"] as? String == "Password: password", "Decrypted worksheet in native grid")
        try check(secure.stringValue.isEmpty && v.documents.count == initial + 1, "Password cleared; exactly one worksheet document")
        // Filesystem aliases must not bypass the original-file protection.
        let alias = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("statsdirect-alias-\(UUID().uuidString).xlsx")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: encrypted)
        defer { try? FileManager.default.removeItem(at: alias) }
        try check(v.isImportedWorkbookSource(alias, document: doc), "Alias overwrite protection")
        v.remove(doc)
        print("PASS: native secure password field, cancel, wrong-password retry, successful decryption, password clearing and source/alias overwrite protection")
    }
}
