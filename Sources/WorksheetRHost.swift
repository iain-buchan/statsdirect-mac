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
                guard let options = try result.get() as? [String: Any], let sheet = options["sheet"] as? String else {
                    throw ConversationRScript.Failure(message: "The worksheet import options could not be read.")
                }
                let entire = WorksheetRImportPrompt.Option(options["entire"] as? [String: Any])
                let selected = WorksheetRImportPrompt.Option(options["selected"] as? [String: Any])
                WorksheetRImportPrompt.present(on: self.window, external: external, sheet: sheet, entire: entire, selected: selected,
                                               selectedReason: options["selectedReason"] as? String) { [weak self, weak doc] choice in
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

    private func importWorksheetInR(_ doc: Document, version: Int, sheet: String,
                                    expected: WorksheetRImportPrompt.Option,
                                    choice: WorksheetRImportPrompt.Selection, external: Bool) {
        let changed = ConversationRScript.Failure(message: "The worksheet changed. Open the R import prompt again.")
        guard doc.gridVersion == version else { showWorksheetRError(changed, document: doc); return }
        // The format goes too: a list of vectors leaves missing values out, so the grid's size check counts only its
        // non-blank cells.
        doc.web.callAsyncJavaScript("return window.statsDirectGrid.worksheetRImport(scope, {headings: headings, list: list})",
                                    arguments: ["scope": choice.scope.rawValue, "headings": choice.headings, "list": choice.asList],
                                    in: nil, in: .page) { [weak self, weak doc] result in
            guard let self, let doc, self.active === doc else { return }
            do {
                guard doc.gridVersion == version else { throw changed }
                let unreadable = ConversationRScript.Failure(message: "The worksheet data could not be read.")
                guard let data = try result.get() as? [String: Any] else { throw unreadable }
                guard data["sheet"] as? String == sheet, data["range"] as? String == expected.range,
                      WorksheetRScript.integer(data["rowCount"]) == expected.rowCount,
                      WorksheetRScript.integer(data["columnCount"]) == expected.columnCount else { throw changed }
                // One value per data row: the rows sent, less the first when it names the columns.
                let dataRows = expected.rowCount - (choice.headings ? 1 : 0)
                guard let columns = data["columns"] as? [[String: Any]], columns.count == expected.columnCount,
                      columns.allSatisfy({ ($0["values"] as? [Any])?.count == dataRows }) else { throw unreadable }
                let source = try WorksheetRScript.build(data, rFriendlyNames: choice.rFriendlyNames, asList: choice.asList)
                self.openWorksheetRSession(source, title: sheet, document: doc, external: external)
            } catch {
                self.showWorksheetRError(error, document: doc)
            }
        }
    }

    private func openWorksheetRSession(_ source: String, title: String?, document: Document, external: Bool) {
        if external {
            // No echo: R.app's console shows str(worksheet_data) (rule 5.4), not the data being read.
            openScriptInExternalR(source, name: title.map { $0 + " Worksheet" } ?? "New R Session",
                                  workingDirectory: InteractiveRConsole.supportFolder.appendingPathComponent("R Sessions"),
                                  document: document, echo: false)
        } else if InteractiveRConsole.enabled {
            makeRConsole(script: source, title: title, autoRun: !source.isEmpty)
        } else {
            let script = makeRScript(script: source, title: title)
            if !source.isEmpty { script.rPane?.runScript() }
        }
    }

    private func showWorksheetRError(_ error: Error, document: Document) {
        var message = javaScriptMessage(error)
        // WebKit gives an Error thrown in the grid as "Error: <message>"; the grid's own message is shown as it wrote it.
        if (error as NSError).domain == WKError.errorDomain && message.hasPrefix("Error: ") { message.removeFirst(7) }
        gridStatus(document, message)
        status.stringValue = message
    }
}
