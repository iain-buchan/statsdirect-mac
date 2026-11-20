import Cocoa
import WebKit

extension Viewer {
    func openWorksheetInR(_ doc: Document, external: Bool) {
        guard doc.kind == "grid", !doc.web.isLoading else { return }
        let version = doc.gridVersion
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.worksheetRImport()", arguments: [:], in: nil, in: .page) { [weak self, weak doc] result in
            guard let self, let doc, self.active === doc, self.window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return }
            do {
                guard let options = try result.get() as? [String: Any] else {
                    throw ConversationRScript.Failure(message: "The worksheet import options could not be read.")
                }
                let entire = WorksheetRImportPrompt.Option(options["entire"] as? [String: Any])
                let selected = WorksheetRImportPrompt.Option(options["selected"] as? [String: Any])
                let sheet = options["sheet"] as? String
                WorksheetRImportPrompt.present(on: self.window, external: external, entire: entire, selected: selected) { [weak self, weak doc] choice in
                        guard let self, let doc, let choice, self.active === doc else { return }
                        if choice.scope == .none {
                            self.openWorksheetRSession("", title: nil, document: doc, external: external)
                        } else if let expected = choice.scope == .entire ? entire : selected {
                            self.importWorksheetInR(doc, version: version, sheet: sheet, expected: expected,
                                                    choice: choice, external: external)
                        }
                    }
            } catch {
                self.showWorksheetRError(error, document: doc)
            }
        }
    }

    private func importWorksheetInR(_ doc: Document, version: Int, sheet: String?,
                                    expected: WorksheetRImportPrompt.Option,
                                    choice: WorksheetRImportPrompt.Selection, external: Bool) {
        let changed = ConversationRScript.Failure(message: "The worksheet changed. Open the R import prompt again.")
        guard doc.gridVersion == version else { showWorksheetRError(changed, document: doc); return }
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.worksheetRImport(scope)",
                                    arguments: ["scope": choice.scope.rawValue], in: nil, in: .page) { [weak self, weak doc] result in
            guard let self, let doc, self.active === doc else { return }
            do {
                guard doc.gridVersion == version else { throw changed }
                guard let data = try result.get() as? [String: Any] else {
                    throw ConversationRScript.Failure(message: "The worksheet data could not be read.")
                }
                guard data["sheet"] as? String == sheet, data["range"] as? String == expected.range,
                      data["rowCount"] as? Int == expected.rowCount,
                      (data["columns"] as? [Any])?.count == expected.columnCount else { throw changed }
                let source = try WorksheetRScript.build(data, headings: choice.headings,
                                                        rFriendlyNames: choice.rFriendlyNames, asList: choice.asList)
                self.openWorksheetRSession(source, title: data["sheet"] as? String ?? doc.title,
                                           document: doc, external: external)
            } catch {
                self.showWorksheetRError(error, document: doc)
            }
        }
    }

    private func openWorksheetRSession(_ source: String, title: String?, document: Document, external: Bool) {
        if external {
            openScriptInExternalR(source, name: title.map { $0 + " Worksheet" } ?? "New R Session",
                                  workingDirectory: InteractiveRConsole.supportFolder.appendingPathComponent("R Sessions"),
                                  document: document)
        } else if InteractiveRConsole.enabled {
            makeRConsole(script: source, title: title, autoRun: !source.isEmpty)
        } else {
            let script = makeRScript(script: source, title: title)
            if !source.isEmpty { script.rPane?.runScript() }
        }
    }

    private func showWorksheetRError(_ error: Error, document: Document) {
        let message = javaScriptMessage(error)
        gridStatus(document, message)
        status.stringValue = message
    }
}
