import Cocoa
import WebKit
import UniformTypeIdentifiers

private typealias AnalysisFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias AnalysisFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

extension Viewer {
    @objc func showChiSquare() {
        newDocument(kind: "analysis", title: nextAnalysisTitle("Chi-square · R × C"), url: root.appendingPathComponent("Grid/chi-square.html"))
    }
    @objc func chiSquareHelp() { openHelp(root.appendingPathComponent("Help/chi_square_tests/rc.htm"), title: "R × C contingency table") }
    func handleAnalysis(_ message: WKScriptMessage) {
        guard message.name == "statsDirectAnalysis", message.frameInfo.isMainFrame,
              let web = message.webView, let doc = document(for: web), doc.kind == "analysis",
              web.url?.standardizedFileURL == root.appendingPathComponent("Grid/chi-square.html").standardizedFileURL,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "help": chiSquareHelp()
        case "changed": doc.gridDirty = true; doc.gridVersion += 1
        case "save": saveAnalysisTable(doc)
        case "copy":
            if let text = body["text"] as? String { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        case "paste":
            guard doc.analysisJobID == nil else { return }
            if let text = NSPasteboard.general.string(forType: .string) { web.evaluateJavaScript("window.statsDirectChiSquare.pasteText(\(jsString(text)))") }
            else { analysisState(doc, false, "The clipboard does not contain text to paste.", error: true) }
        case "run":
            guard let input = body["input"] as? [String: Any] else { return }
            guard !running else { analysisState(doc, false, "Another analysis is running. Please wait for it to finish.", error: true); return }
            let id = UUID().uuidString
            running = true; doc.analysisJobID = id; doc.analysisCancelled = false
            status.stringValue = "Running chi-square r × c…"
            analysisState(doc, true, "Running the StatsDirect engine…")
            analysisRequest(["action": "run", "id": id, "input": input]) { result in
                let cancelled = doc.analysisCancelled
                doc.analysisJobID = nil; self.endRun()
                guard self.documents.contains(where: { $0 === doc }) else { return }
                if doc.operationClosing { self.remove(doc); return }
                switch result {
                case .failure(let error):
                    self.analysisState(doc, false, error.localizedDescription, error: true); self.status.stringValue = "Chi-square analysis failed"
                case .success(let output):
                    if cancelled || output["cancelled"] as? Bool == true {
                        self.analysisState(doc, false, "Calculation cancelled. Your table is unchanged; no report was created.")
                        self.status.stringValue = "Chi-square analysis cancelled"; return
                    }
                    self.analysisState(doc, false, "Analysis complete. Results are in a separate report tab; edit these counts to run again.")
                    self.showChiSquareReport(output)
                }
            }
        case "cancel": cancelAnalysis(doc)
        default: break
        }
    }
    func analysisState(_ doc: Document, _ busy: Bool, _ text: String, error: Bool = false) {
        doc.web.evaluateJavaScript("window.statsDirectChiSquare?.setState(\(busy),\(jsString(text)),\(error))")
    }
    func cancelAnalysis(_ doc: Document) {
        guard let id = doc.analysisJobID, !doc.analysisCancelled else { return }
        doc.analysisCancelled = true
        status.stringValue = "Cancelling chi-square r × c at the next engine checkpoint…"
        analysisRequest(["action": "cancel", "id": id]) { result in
            if case .failure(let error) = result { self.status.stringValue = "Cancellation signal failed: " + error.localizedDescription }
        }
    }
    func analysisRequest(_ request: [String: Any], entry: String = "statsdirect_analysis", completion: @escaping (Result<[String: Any], Error>) -> Void) {
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            let json = String(decoding: data, as: UTF8.self)
            if libraryHandle == nil { libraryHandle = dlopen(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/StatsDirectEngine.dylib").path, RTLD_NOW | RTLD_LOCAL) }
            guard let handle = libraryHandle, let symbol = dlsym(handle, entry), let freeSymbol = dlsym(handle, entry + "_free") else {
                throw NSError(domain: "StatsDirect.Analysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "The analysis host could not be loaded. Rebuild the viewer."])
            }
            let invoke = unsafeBitCast(symbol, to: AnalysisFunction.self), free = unsafeBitCast(freeSymbol, to: AnalysisFreeFunction.self)
            // Cancellation must run independently of the calculation it is cancelling.
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<[String: Any], Error>
                do {
                    guard let pointer = json.withCString({ invoke($0) }) else { throw CocoaError(.executableRuntimeMismatch) }
                    let response = String(cString: pointer); free(pointer)
                    guard let output = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
                    if let error = output["error"] as? String, output["state"] == nil { throw NSError(domain: "StatsDirect.Analysis", code: 2, userInfo: [NSLocalizedDescriptionKey: error]) }
                    result = .success(output)
                } catch { result = .failure(error) }
                DispatchQueue.main.async { completion(result) }
            }
        } catch { completion(.failure(error)) }
    }
    func showChiSquareReport(_ output: [String: Any]) {
        guard let html = output["html"] as? String, let input = output["input"] as? [String: Any],
              let counts = input["counts"] as? [[Double]], let values = output["values"] as? [String: Any] else { showError("The engine returned an incomplete report."); return }
        reportNumber += 1
        let rowLabels = input["rowLabels"] as? [String] ?? counts.indices.map { "Row \($0 + 1)" }
        let columnLabels = input["columnLabels"] as? [String] ?? counts[0].indices.map { "Column \($0 + 1)" }
        let headers = columnLabels.map { "<th>\(htmlEscape($0))</th>" }.joined()
        let rows = counts.enumerated().map { r, row in "<tr><th>\(htmlEscape(rowLabels[r]))</th>" + row.map { "<td>\(number($0))</td>" }.joined() + "</tr>" }.joined()
        let warnings = (output["warnings"] as? [String] ?? []).map { "<p class='note'>\(htmlEscape($0))</p>" }.joined()
        let skipped = output["exactSkipped"] as? Bool == true ? "<p class='note'>The engine skipped exact testing because the total exceeds 100,000 observations.</p>" : ""
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let confidence = (input["cco"] as? Double ?? 0.95) * 100
        let options = ["doExact": "Exact test requested", "show_pc": "Percentages", "xp": "Expected counts", "cs": "Cell chi-square", "xs": "Trend scores", "specify_scores": "Custom scores", "doMonteCarlo": "Monte Carlo simulation"].filter { input[$0.key] as? Bool == true }.map(\.value).sorted().joined(separator: " · ")
        let scores = input["specify_scores"] as? Bool == true ? "<p>Row scores: \(htmlEscape(String(describing: input["rowScores"] ?? "")))<br>Column scores: \(htmlEscape(String(describing: input["columnScores"] ?? "")))</p>" : "<p>Trend scores follow table order: 1, 2, 3, … on each axis.</p>"
        let rPlan = try? RScriptGenerator.generate(operation: "ExactChiRbyCScreen", title: "Chi-square R × C", output: output, resources: root)
        let body = """
        \(reportRAction(rPlan))
        <div class="eyebrow">Analysis / Chi-square / Screen data</div>
        <p class="lead">\(counts.count) × \(counts[0].count) contingency table</p><p class="muted">Report \(reportNumber) · \(stamp)</p>
        <div class="summary"><div><span>Pearson chi-square</span><strong>\(number(values["chio"] as? Double ?? .nan))</strong></div><div><span>P</span><strong>\(number(values["po"] as? Double ?? .nan))</strong></div><div><span>Observations</span><strong>\(number(output["total"] as? Double ?? .nan))</strong></div></div>
        \(warnings)\(skipped)<section class="engine-report">\(html)</section>
        <p><a href="Help/chi_square_tests/rc.htm">R × C contingency table: method and worked example →</a></p>
        <details><summary>Input counts and options used for this report</summary><table><thead><tr><th>Category</th>\(headers)</tr></thead><tbody>\(rows)</tbody></table><p>\(htmlEscape(options)) · \(number(confidence))% confidence</p>\(scores)</details>
        <p class="muted">Calculated by the full StatsDirect 5.0.5 headless engine, operation ExactChiRbyCScreen, using its original HTML report renderer. The input form stays open for further edits.</p>
        """
        let report = newDocument(kind: "report", title: "Report \(reportNumber) · Chi-square R × C", html: page("R × C contingency table", body))
        report.rScriptPlan = rPlan; report.operationName = "ExactChiRbyCScreen"
        status.stringValue = "Chi-square r × c completed · Report \(reportNumber)"
    }
    func saveAnalysisTable(_ doc: Document) {
        let version = doc.gridVersion
        doc.web.evaluateJavaScript("window.statsDirectChiSquare?.csvData()") { value, error in
            guard error == nil, let csv = value as? String else { self.showError("The table could not be exported."); return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "Chi-square counts.csv"
            panel.beginSheetModal(for: self.window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                    if doc.gridVersion == version { doc.gridDirty = false }
                    self.status.stringValue = "Saved counts and category labels to " + url.lastPathComponent
                } catch { self.showError(error.localizedDescription) }
            }
        }
    }
}
