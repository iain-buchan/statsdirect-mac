import Cocoa

extension Viewer {
    func runManagedScript(_ owner: Document, code: String, language: String) {
        guard !documents.contains(where: { $0.scriptOwner === owner && $0.analysisJobID != nil }) else { return }
        let doc = newDocument(kind: "operation", title: owner.title + " · Input", url: root.appendingPathComponent("Grid/operation.html"))
        doc.operationName = "UserScript"; doc.managedScript = code; doc.managedLanguage = language
        doc.scriptOwner = owner; doc.operationSourceID = analysisSourceID
    }
}
