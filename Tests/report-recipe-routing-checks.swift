import Cocoa
import WebKit

// Which R action a result reopened from a saved report or recovered from a notebook is given is its record's to say: the engine's
// answer for the record, by the rule its script writer applies (RRecipes.Find), as the Windows report asks. A follow-on whose recipe
// the shared manifest routes by the analysis it continued ("parentFiles": the principal components' Cronbach, matrix and scores, the
// regression ANOVA, the dose-response follow-ons) has one only after a parent the manifest names: the record's rootOperation or, in
// an older record without one, the analysis its settings identify.
// Codex's 36 fixtures (Tests/Fixtures/RecipeRouting, made on 9 November 2026 against Windows 04aa9501 and kept as it made them): the
// same records as a saved report (routing.html) and as a notebook (routing.ipynb), with the answer expected of each in matrix.json,
// in the same order. Through each import path every result must agree in the imported recipe flag, the writer's hasRecipe, the
// report's rendered R action and the context menu's label. Tests/test_recipe_by_record.py asks the engine the same 36 without the app.
extension ReportExportTests {
    @MainActor static func recipeRouting(_ v: Viewer, output: URL) async throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw NSError(domain: "RecipeRoutingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        struct Fixture: Decodable { let title: String; let expected: Bool }
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/RecipeRouting")
        let cases = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: folder.appendingPathComponent("matrix.json")))
        try require(cases.count == 36 && cases.contains { !$0.expected } && cases.contains { $0.expected }, "the routing matrix holds its 36 cases, with and without a recipe")
        var checked = 0
        for format in ["HTML", "Notebook"] {
            let doc = format == "HTML" ? try await v.importReport(folder.appendingPathComponent("routing.html"))
                                       : try await v.importNotebook(folder.appendingPathComponent("routing.ipynb"))
            guard let entries = doc.reportEntries, entries.count == cases.count else {
                v.remove(doc); throw NSError(domain: "RecipeRoutingTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(format) imported \(doc.reportEntries?.count ?? 0) results, expected \(cases.count)"])
            }
            let deadline = Date().addingTimeInterval(25)
            var modes: [String] = []
            repeat {
                let raw = try? await doc.web.evaluateJavaScript("Array.from(document.querySelectorAll('article.report-entry'), a => a.getAttribute('data-r') || '')")
                modes = raw as? [String] ?? []
                if modes.count == entries.count { break }
                try await Task.sleep(nanoseconds: 60_000_000)
            } while Date() < deadline
            try require(modes.count == entries.count, "\(format): the report rendered \(modes.count) of \(entries.count) results' R actions")
            for (index, (entry, fixture)) in zip(entries, cases).enumerated() {
                let label = "\(format) \(fixture.title)"
                try require(entry.title == fixture.title && entry.record != nil, "\(label): the result or its record was not recovered")
                let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
                    v.analysisRequest(["record": entry.record!], entry: "statsdirect_r_script") { continuation.resume(with: $0) }
                }
                let expectedMode = fixture.expected ? "recipe" : "data", expectedLabel = fixture.expected ? "Continue in R" : "Open Data and Settings in R"
                try require(entry.recipe == fixture.expected && response["hasRecipe"] as? Bool == fixture.expected && modes[index] == expectedMode,
                            "\(label): expected \(fixture.expected), imported \(entry.recipe), writer \(String(describing: response["hasRecipe"])), rendered \(modes[index])")
                doc.reportContext = ["inReport": true, "r": modes[index], "resultId": entry.id]
                let menu = NSMenu(); v.extendReportMenu(menu, for: doc)
                let items = menu.items.filter { ($0.representedObject as? [String: String])?["kind"] == "r" }.map(\.title)
                try require(items == [expectedLabel], "\(label): the menu offered \(items), expected \(expectedLabel)")
                checked += 1
            }
            v.remove(doc)
        }
        print("PASS: \(checked) results of the routing fixtures, reopened from a saved report and recovered from a notebook, take their R label from the record by the analysis they continued: the imported flag, the writer's hasRecipe, the rendered action and the context menu agree"); fflush(stdout)
    }
}
