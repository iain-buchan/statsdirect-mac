import Cocoa
import WebKit

@main struct WorksheetAIChecks {
    @MainActor static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ChatGPTTutor.Failure(message: message) }
        print("PASS: " + message)
        fflush(stdout)
    }

    /// What a card and its offer show that must never reach the provider (the mock's CARD_WORDS, the same list). The mock checks every
    /// question's prompt for them, cardsStayLocal the whole request log and the preflight the log of its cases. They are the card's own
    /// fixed texts that occur nowhere else ("Suggested · ", the recommendation's headings, "Use these as separate samples", "Change
    /// sample choice"), and markers of every line that carries what was read or computed from the selected cells, or chosen on the
    /// card: each line of the check (the count with Shapiro–Wilk, the shape and skewness lines above 100 pairs, each sample's count),
    /// each of the 15 recommendation texts Windows' SuggestPairedBranch gives (from its nine returns), the four conflict texts, the six advice texts, the refusals
    /// that describe the cells (a cell that is not numeric, a difference too large to check, Excel errors, stale formula results)
    /// and the offer's label (its "Menu: " line, with the method, sheet, selection and report). requireMarked holds every card and card
    /// offer the suite draws to this list. None of them occurs in what legitimately reaches a request: the instructions, the Help page
    /// sent as reference (raw or as text), the tool descriptions, the method catalogue, or the mock's replies and tool results
    /// ("complete pairs" does, so it is no marker).
    static let cardWords = ["Suggested · ", "Suggested branch", "Review the differences", "Use these as separate samples", "Change sample choice",
                            "Selected columns, if they hold",
                            "Local check found", "Shapiro–Wilk W =", "Shape check ·", "Excess kurtosis", "Column 1: n =", "Column 2: n =",
                            "There are too few complete pairs", "All the paired differences are the same",
                            "the shape checks found no substantial departure", "The shape checks flagged", "The box-plot check flagged",
                            "The skewness check flagged", "The normality check could not assess", "Shapiro–Wilk found",
                            "The local check found",
                            "The large-sample branch recommends", "This branch assumes", "The signed-rank test concerns",
                            "The Help routes large", "The unpaired t test compares means", "compares relative ordering",
                            "is not numeric", "too large to check", "The selection contains Excel errors", "before analysing formula cells",
                            "Menu: "]

    /// The lines a card or a card's offer may show without a card word: the questions, the prompts for a size or a distribution not
    /// yet known, the titles of the choices, and the refusals that name only the selection's shape or a request that could not be
    /// read. None of them says anything read or computed from the cells, or chosen on the card.
    static let plainCardLines: Set<String> = [
        "Were these measurements taken from the same people or units?", "Same people or units", "Separate groups",
        "How many complete pairs are there?", "How many observations are there in each group?",
        "How are the within-pair differences distributed?", "How are the observations distributed within each group?",
        "Look at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive.",
        "Check selected pairs", "Check two sample columns", "Change design",
        "Large sample (more than 100 complete pairs)", "Small or medium · Approximately normal differences", "Non-normal differences",
        "Large samples (more than 100 in each group)", "Small or medium · Approximately normal within groups", "Non-normal distributions within groups",
        "Select two adjacent, visible columns of matched measurements in one worksheet range.",
        "Select the two adjacent, visible sample columns in one worksheet range.",
        "The worksheet could not be read. Try again.", "The measurements to check are not in a recognised form.", "Set design to paired or independent."]
    /// The cards and the card offers requireMarked has held to cardWords.
    @MainActor static var markedCards = 0, markedOffers = 0

    /// Holds the card or the card's offer on screen to cardWords: every line it shows that is not one of plainCardLines must hold a
    /// card word, so that the checks of every request would catch it. The card's paragraphs and the offer's details count line by
    /// line, as the engine gives them separately (each line of the check, the recommendation under its heading, the advice); the
    /// offer's label is one text. Fails naming each line without one.
    @MainActor static func requireMarked(_ pane: WorksheetAIPane, _ what: String) throws {
        pane.view.window?.contentView?.layoutSubtreeIfNeeded()
        func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
        let shown: [NSView] = tree(pane.view).filter { !$0.isHiddenOrHasHiddenAncestor }
        func field(_ id: String) -> NSTextField? { shown.first(where: { $0.identifier?.rawValue == id }) as? NSTextField }
        var lines: [String] = [], label: [String] = []
        let box: NSView? = shown.first(where: { $0.identifier?.rawValue == "worksheet-ai-distribution" })
        if let box { lines += tree(box).compactMap { ($0 as? NSTextField)?.stringValue ?? ($0 as? NSButton)?.title } }
        if let details = field("worksheet-ai-offer-details") {
            lines.append(details.stringValue)
            label = [field("worksheet-ai-confirmation")?.stringValue ?? ""]
        }
        let carried: [String] = lines.flatMap { $0.components(separatedBy: "\n") }.filter { !plainCardLines.contains($0) } + label
        let unmarked: [String] = carried.filter { line in !line.isEmpty && !cardWords.contains(where: line.contains) }
        guard unmarked.isEmpty else {
            throw ChatGPTTutor.Failure(message: what + " shows what was read, computed or chosen on this Mac with no card word to catch it in a request: "
                                       + unmarked.map(\.debugDescription).joined(separator: ", "))
        }
        if box != nil { markedCards += 1 }
        if !label.isEmpty { markedOffers += 1 }
    }

    @MainActor static func wait(_ message: String, until condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChatGPTTutor.Failure(message: message)
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
        let viewer = Viewer()
        app.delegate = viewer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                do { try await run(viewer) }
                catch { print("FAIL: " + error.localizedDescription); exit(1) }
                viewer.closeApproved = true
                app.terminate(nil)
            }
        }
        // Generous for a loaded build Mac: the distribution cards' cases more than doubled the run, and the preflight's 31 cases
        // through the worksheet UI add about a minute more.
        DispatchQueue.global().asyncAfter(deadline: .now() + 900) {
            print("FAIL: Worksheet AI test timed out"); exit(1)
        }
        app.run()
    }

    @MainActor static func run(_ viewer: Viewer) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("worksheet-ai-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("chatgpt-mock")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        viewer.chatGPTTutor.shutdown()
        viewer.chatGPTTutor = ChatGPTTutor(executable: root.appendingPathComponent("Tests/mock-worksheet-ai-server.py"),
                                         storage: storage, resources: viewer.root.appendingPathComponent("Tutor"))
        viewer.chatGPTTutor.changed = { [weak viewer] in viewer?.worksheetAI?.updateControls() }
        defer { viewer.chatGPTTutor.shutdown() }
        viewer.window.setContentSize(NSSize(width: 1350, height: 850))

        let h = WorksheetAIHarness(viewer: viewer, directory: directory, storage: storage, root: root)
        let (first, second) = try await h.sharedReads()
        try await h.methodPicker(first, second)
        let report = try await h.followsWorkbooks(first, second)
        try await h.closeAndQuestionOnly(first, second)
        try await h.methodMarkers()
        try await h.selectionAndOverview(first)
        try await h.clarificationCard(first)
        try await h.stoppedAndRefusedReads(first)
        try await h.headingsAndHeldReads(first)
        try await h.emptyWorkbooks(first)
        let cards = try await h.cardWorkbook()
        try await h.designAndStaleClicks(cards)
        try await h.largePairsAndNarrowDock(cards)
        try await h.shapeChecks(cards)
        try await h.headerRowSetting(cards)
        try await h.unreadableSelections(cards)
        try await h.independentCards(cards)
        try await h.stagedCards(cards)
        try await h.cardsInReplies(cards)
        try await h.cardsStayLocal(first, cards)
        try await h.offersHeldToTheCard(cards)
        try await h.keyboardCards(cards)
        try await h.narrowCards(cards)
        try await h.shortPane(cards)
        try await h.designAndActivation(cards, report)
        try await h.cardNeedsWorkbookInFront(cards, report)
        let (qz, pefr) = try await h.questionOnlyCards()

        // Codex's preflight of the distribution cards through the worksheet UI, with Continue to the report its offer names. It is a
        // function of its own: inside this one, already long, it made the compiler take more than ten minutes.
        try await preflight(viewer, h.pane, storage: storage, root: root, report: report)

        try await h.policyAndCleanup(first, cards, qz, report, pefrToken: pefr.token)
        try check(markedCards > 0 && markedOffers > 0, "on each of the \(markedCards) cards and \(markedOffers) card offers drawn, every line that carries "
                  + "what was read, computed or chosen on this Mac holds a card word")
    }

    // Codex's preflight of the distribution cards (Tests/Fixtures/distribution: base R 4.6.1, 26 paired and 5 independent cases)
    // through the worksheet UI. Every case sits in its own pair of columns of one real worksheet, under headings in row 1 with
    // "First row has column names" ticked (D1); the page's own hooks select each pair, as whole columns or as a rectangle from the
    // headings down, and the card reads it as the pane reads any selection. The pane keeps only the card's text, so the numbers are
    // held to R, at the preflight's tolerance (2e-10 relative, absolute below 1), through the engine's reply to the pane's own request
    // for that same reading, which must be exactly the check the pane drew. The card's text is held to Windows' with W and P as R's
    // values give them; every branch is refused with Windows' feedback or offers its method with Windows' advice, and Change sample
    // choice returns to the same card. Continue then routes a result to the report its offer names: an open one, or a new one.
    @MainActor static func preflight(_ viewer: Viewer, _ pane: WorksheetAIPane, storage: URL, root: URL, report: Document) async throws {
        // The driver's helpers, as run defines them for the rest of this suite.
        func control<T: NSView>(_ id: String, in view: NSView) -> T? {
            if view.identifier?.rawValue == id, let match = view as? T { return match }
            for child in view.subviews {
                if let match: T = control(id, in: child) { return match }
            }
            return nil
        }
        func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
        }
        func label(_ id: String) -> String {
            viewer.window.contentView?.layoutSubtreeIfNeeded()
            return (control(id, in: pane.view) as NSTextField?)?.stringValue ?? ""
        }
        func grid(_ doc: Document, _ script: String) async throws {
            _ = try await doc.web.callAsyncJavaScript(script + "; return true;", arguments: [:], in: nil, contentWorld: .page)
        }
        func text(_ pane: WorksheetAIPane) async -> String {
            (try? await pane.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
        }
        func requestLines() -> [String] {
            ((try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
        }
        // Windows WorksheetAnalysisDataTraffic: the questions and tool results that reached the provider.
        func dataTraffic() -> [String] {
            requestLines().filter { line in
                guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return false }
                return request["method"] as? String == "turn/start" || request["result"] != nil
            }
        }
        // The shown card as Windows' WorksheetActionSnapshot gives it: its kind, its buttons' token, its paragraphs and its choices
        // with their titles.
        struct Card {
            let kind: String, token: String, lines: [String], choices: [String], titles: [String]
            var text: String { (lines + titles).joined(separator: "\n") }
        }
        func card() -> Card? {
            viewer.window.contentView?.layoutSubtreeIfNeeded()
            guard let box: NSView = control("worksheet-ai-distribution", in: pane.view), !box.isHiddenOrHasHiddenAncestor,
                  let kind = pane.distribution?.card.kind.rawValue else { return nil }
            let buttons = views(WorksheetAIChoiceButton.self, in: box)
            return Card(kind: kind, token: buttons.first?.token ?? "", lines: views(NSTextField.self, in: box).map(\.stringValue),
                        choices: buttons.map(\.choice), titles: buttons.map(\.title))
        }
        func feedback(_ text: String, _ message: String) async throws {
            try await wait(message + ": " + label("worksheet-ai-distribution-feedback").debugDescription) {
                label("worksheet-ai-distribution-feedback") == text
            }
            try requireMarked(pane, "The card with its feedback (\(pane.selectionLabel.stringValue))")
        }
        let previous = viewer.active, requestsBefore = requestLines().count
        let fixtureFolder = root.appendingPathComponent("Tests/Fixtures/distribution")
        func fixtureTable(_ name: String) throws -> [[String: String]] {
            let lines = try String(contentsOf: fixtureFolder.appendingPathComponent(name), encoding: .utf8).split(separator: "\n").map(String.init)
            guard let header = lines.first?.components(separatedBy: "\t") else { throw ChatGPTTutor.Failure(message: name + " is empty") }
            return lines.dropFirst().map { line in
                let fields = line.components(separatedBy: "\t")
                var row: [String: String] = [:]
                for (index, column) in header.enumerated() { row[column] = index < fields.count ? fields[index] : "" }
                return row
            }
        }
        struct Fixture {
            let paired: Bool, name: String, index: Int
            let rows: [(first: String, second: String)]
        }
        // The cases in the oracle's order, each with its cells as the oracle wrote them ("" for a missing value).
        var fixtures: [Fixture] = []
        for (file, paired) in [("paired-input.tsv", true), ("independent-input.tsv", false)] {
            var order: [String] = [], cells: [String: [(first: String, second: String)]] = [:]
            for row in try fixtureTable(file) {
                let name = row["case"] ?? ""
                if cells[name] == nil { order.append(name); cells[name] = [] }
                guard Int(row["row"] ?? "") == cells[name]!.count + 1 else { throw ChatGPTTutor.Failure(message: file + " lists the rows of " + name + " out of order") }
                cells[name]!.append((row["first"] ?? "", row["second"] ?? ""))
            }
            for name in order { fixtures.append(Fixture(paired: paired, name: name, index: fixtures.count, rows: cells[name]!)) }
        }
        var expected: [String: [String: String]] = [:]
        for file in ["paired-expected.tsv", "independent-expected.tsv"] { for row in try fixtureTable(file) { expected[row["case"] ?? ""] = row } }
        try check(fixtures.filter(\.paired).count == 26 && fixtures.filter { !$0.paired }.count == 5 && Set(fixtures.map(\.name)) == Set(expected.keys),
                  "the preflight's 26 paired and 5 independent cases each have R's expected values")

        func letters(_ index: Int) -> String {
            var column = index + 1, name = ""
            while column > 0 { column -= 1; name = String(Character(UnicodeScalar(UInt8(65 + column % 26)))) + name; column /= 26 }
            return name
        }
        var fixtureCells: [[String: Any]] = []
        func put(_ col: Int, _ heading: String, _ texts: [String]) {
            fixtureCells.append(["col": col, "row": 0, "text": heading, "kind": "text"])
            for (row, text) in texts.enumerated() where !text.isEmpty { fixtureCells.append(["col": col, "row": row + 1, "text": text, "kind": "number"]) }
        }
        // The oracle's overflow, 1e308 minus -1e308, in the pair after the cases.
        let overflow = Fixture(paired: true, name: "overflow", index: fixtures.count, rows: [("1e+308", "-1e+308")])
        for fixture in fixtures + [overflow] {
            put(2 * fixture.index, fixture.name + " first", fixture.rows.map { $0.first })
            put(2 * fixture.index + 1, fixture.name + " second", fixture.rows.map { $0.second })
        }
        let book = viewer.newDocument(kind: "grid", title: "Preflight fixtures", url: viewer.root.appendingPathComponent("Grid/index.html"))
        book.workbookName = "Preflight fixtures.xlsx"
        book.pendingWorkbook = ["name": "Preflight fixtures", "formulaCount": 0,
                                "sheets": [["name": "Preflight", "rows": 1100, "columns": 2 * overflow.index + 2, "headerRow": true, "cells": fixtureCells]]]
        try await wait("AI Assist did not follow the fixture workbook") {
            pane.workbookID == book.id && book.pendingWorkbook == nil && book.aiWorksheet?.hasData == true && book.aiWorksheet?.headerRow == true
        }
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        let headerOption = "document.querySelector('.worksheet-options input[type=checkbox]')"
        let ticked = try await book.web.evaluateJavaScript(headerOption + ".checked") as? Bool
        let stored = try await book.web.evaluateJavaScript("statsDirectGrid.excelData().sheets[0].cells.length") as? Int
        try check(ticked == true && stored == fixtureCells.count && pane.share.state == .on && pane.confirm.state == .on,
                  "the \(stored ?? 0) cells load into one worksheet, each case in its own pair of columns under its headings, with First row has column names ticked")

        // Windows' mapping and texts (StatsDirectUI/UI/Learning/ScriptAIPane.WorksheetAnalysis.cs Method, Advice, Conflict and
        // SuggestPairedBranch; Learning/conversation.mjs for the choices), and the five methods' titles and menu paths in Analyse.
        let branches = ["large", "normal", "non-normal"]
        let methodFor: [Bool: [String: String]] = [true: ["large": "TPaired", "normal": "TPaired", "non-normal": "Wilcoxon"],
                                                   false: ["large": "ZUnpaired", "normal": "TUnpaired", "non-normal": "MannWhitney"]]
        let adviceFor: [Bool: [String: String]] = [
            true: ["large": "The large-sample branch recommends the paired t test for the mean difference.",
                   "normal": "The paired t test addresses the mean difference. This branch assumes approximately normal differences.",
                   "non-normal": "The signed-rank test concerns a shift in location and assumes roughly symmetric differences. If the aim is specifically to estimate or test the mean difference, consider whether this answers your question."],
            false: ["large": "The Help routes large, well-behaved samples to the two-sample Z test for the difference in means.",
                    "normal": "The unpaired t test compares means. Consider the spread in each group before using an equal-variance result.",
                    "non-normal": "Mann–Whitney compares relative ordering between groups. Use that question to decide whether it fits your goal."]]
        let conflictFor: [Bool: [Bool: String]] = [   // by design (paired), then by size (more than 100)
            true: [true: "The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks.",
                   false: "The local check found at most 100 complete pairs. Choose the branch for the distribution of the differences."],
            false: [true: "The local check found more than 100 observations in each sample. Review their distributions before choosing a method.",
                    false: "The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups."]]
        let branchTitles: [Bool: [String]] = [
            true: ["Large sample (more than 100 complete pairs)", "Small or medium · Approximately normal differences", "Non-normal differences"],
            false: ["Large samples (more than 100 in each group)", "Small or medium · Approximately normal within groups", "Non-normal distributions within groups"]]
        let methodTitles = ["TPaired": "Paired Student t test", "Wilcoxon": "Wilcoxon signed ranks test",
                            "ZUnpaired": "Unpaired two-sample z(normal distribution) test", "MannWhitney": "Mann-Whitney U (two-sample Wilcoxon) test",
                            "TUnpaired": "Unpaired Student t test"]
        let menuPaths = ["TPaired": "Analysis › Parametric › Paired t", "Wilcoxon": "Analysis › Nonparametric › Wilcoxon Signed Ranks",
                         "ZUnpaired": "Analysis › Parametric › Unpaired z", "MannWhitney": "Analysis › Nonparametric › Mann-Whitney",
                         "TUnpaired": "Analysis › Parametric › Unpaired t"]
        let tooLarge = "A paired difference is too large to check. Rescale the measurements and try again."
        let groupQuestions = ["How are the observations distributed within each group?",
                              "Look at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive."]
        // SuggestPairedBranch from the oracle's count, variation, warnings and P: the branch the card suggests and the reason it gives.
        func pairedReason(_ n: Int, varying: Bool, outlier: Bool, skew: Bool, heavy: Bool, p: Double?) -> (branch: String?, reason: String) {
            if n < 3 { return (nil, "There are too few complete pairs to assess the distribution. Check the selected measurements before choosing.") }
            if !varying { return (nil, "All the paired differences are the same, leaving zero variation for the test. Check the selected measurements.") }
            if n > 100 {
                let signals = [("far-out differences", outlier), ("pronounced skew", skew), ("heavy tails", heavy)].filter { $0.1 }.map { $0.0 }
                if signals.isEmpty {
                    return ("large", "There are more than 100 complete pairs and the shape checks found no substantial departure. A paired t test answers the question about the mean difference.")
                }
                let signedRanks = skew
                    ? "Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful."
                    : "Consider Wilcoxon signed ranks for a shift in location if the differences look roughly symmetric."
                return (nil, "The shape checks flagged " + signals.joined(separator: ", ") + ". " + signedRanks
                        + " A paired t test still answers the question about the mean difference. Review any influential differences before choosing.")
            }
            if outlier { return (nil, "The box-plot check flagged an unusually distant difference. Review whether it reflects a data error or strongly affects the mean before choosing.") }
            if skew { return (nil, "The skewness check flagged an uneven shape. Examine the differences before choosing. Signed-rank inference about a shift in location requires roughly symmetric differences.") }
            guard let p else { return (nil, "The normality check could not assess these differences. Look at their shape before choosing.") }
            if p < 0.05 { return ("non-normal", "Shapiro–Wilk found evidence of non-normal differences. Consider Wilcoxon signed-rank if the differences look roughly symmetric and a shift in location answers your question.") }
            return ("normal", "A paired t test answers the question about the mean difference. Shapiro–Wilk found no clear departure from normality, and the shape checks flagged no unusual differences. With this sample, those checks provide limited evidence.")
        }
        // Every text of Windows' rule holds a card word, whether a case below draws it or not: each recommendation SuggestPairedBranch
        // can give (by count, variation, warnings and P), and each advice and conflict text.
        let fixedRuleTexts: [String] = adviceFor.values.flatMap { $0.values } + conflictFor.values.flatMap { $0.values }
        var ruleTexts: Set<String> = Set(fixedRuleTexts)
        for n in [2, 50, 101] {
            for varying in [false, true] {
                for warnings in 0..<8 {
                    for p in [nil, 0.01, 0.5] as [Double?] {
                        ruleTexts.insert(pairedReason(n, varying: varying, outlier: warnings & 1 != 0, skew: warnings & 2 != 0, heavy: warnings & 4 != 0, p: p).reason)
                    }
                }
            }
        }
        let unmarkedRule: [String] = ruleTexts.filter { text in !cardWords.contains(where: text.contains) }.sorted()
        try check(unmarkedRule.isEmpty, "each of the \(ruleTexts.count) recommendation, advice and conflict texts of Windows' rule holds a card word"
                  + (unmarkedRule.isEmpty ? "" : ": not " + unmarkedRule.map(\.debugDescription).joined(separator: ", ")))
        // The preflight's comparison: both unavailable, or within 2e-10 of R's value relative to it (absolute below 1).
        func agrees(_ actual: Double?, _ wanted: Double?) -> Bool {
            guard let actual, let wanted else { return actual == nil && wanted == nil }
            return abs(actual - wanted) <= 2e-10 * max(1, abs(wanted))
        }
        func decimal(_ text: String?) -> Double? { text.flatMap { $0.isEmpty ? nil : Double($0) } }
        // .NET's G4 and G3 for these values are C's %G, as the engine's own test renders them.
        func g4(_ x: Double) -> String { String(format: "%.4G", x) }
        func g3(_ x: Double) -> String { String(format: "%.3G", x) }
        func normality(_ w: Double?, _ p: Double?) -> String {
            guard let w, let p else { return "" }
            return ". Shapiro–Wilk W = \(g4(w)), P = \(g4(p))."
        }

        struct Selected { let caption: String, offer: String, columns: [Int] }
        // Even cases as whole columns (selectColumns), odd ones as a rectangle from the headings to the case's last row (selectCells).
        func selectPair(_ fixture: Fixture) async throws -> Selected {
            let left = 2 * fixture.index, a = letters(left), b = letters(left + 1), bottom = fixture.rows.count + 1, whole = fixture.index % 2 == 0
            let caption = whole ? "Selection: Preflight!\(a):\(b)" : "Selection: Preflight!\(a)1:\(b)\(bottom)"
            try await grid(book, "statsDirectGrid." + (whole ? "selectColumns([[\(left),\(left + 2)]])" : "selectCells({x:\(left),y:0,width:2,height:\(bottom)})"))
            try await wait("The selection label did not show " + caption + " for " + fixture.name) { pane.selectionLabel.stringValue == caption }
            return Selected(caption: caption, offer: whole ? "Columns \(a):\(b)" : "\(a)1:\(b)\(bottom)", columns: [left, left + 1])
        }
        // The card drawn for the live selection: of this kind, read, with the live token and the fingerprint of its reading, and
        // each of its lines that carries data marked (requireMarked).
        func cardFor(_ kind: String, _ what: String) async throws -> Card {
            let live = (try? await book.web.evaluateJavaScript("window.statsDirectGrid.aiSelectionFingerprint()")) as? String
            for _ in 0..<300 {
                if let drawn = card(), drawn.kind == kind, drawn.token == pane.guidanceToken, live != nil, pane.guidanceFingerprint == live,
                   pane.distribution?.card.check != nil {
                    try requireMarked(pane, "The \(kind) card (\(pane.selectionLabel.stringValue))")
                    return drawn
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ChatGPTTutor.Failure(message: what + ": " + (card()?.text.debugDescription ?? "no card") + ", notice " + label("worksheet-ai-notice").debugDescription)
        }
        // Use these as separate samples, done: the independent card drawn again, with a new token and no Check.
        func confirmedCard(_ counting: Card, _ what: String) async throws -> Card {
            for _ in 0..<300 {
                if let drawn = card(), drawn.kind == "independent-interval", drawn.token == pane.guidanceToken, drawn.token != counting.token,
                   pane.distribution?.card.check?.canCheck == false {
                    try requireMarked(pane, "The confirmed independent card (\(pane.selectionLabel.stringValue))")
                    return drawn
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ChatGPTTutor.Failure(message: "Use these as separate samples did not confirm \(what): " + (card()?.text.debugDescription ?? "no card")
                                       + ", feedback " + label("worksheet-ai-distribution-feedback").debugDescription)
        }
        // The pane's own request for the live selection (WorksheetAIPane readCard and measurementCheck): the page's reading of the two
        // selected columns, with the paired differences as a snapshot file, and the engine's check of it, unrounded values included.
        let culture = Locale.current.identifier.components(separatedBy: "@")[0].replacingOccurrences(of: "_", with: "-")
        func engineCheck(paired: Bool, separateSamples: Bool) async throws -> (page: [String: Any], reply: [String: Any]?) {
            let page = try await book.web.callAsyncJavaScript("return await window.statsDirectGrid.aiMeasurementColumns(design)",
                arguments: ["design": paired ? "paired" : "independent"], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
            let snapshot = (page["snapshot"] as? [String: Any])?["id"] as? String
            defer { if let snapshot { SnapshotStore.shared.forget(snapshot) } }
            var read: [String: Any]?
            if page["error"] == nil, paired, let pairs = page["pairs"] as? Int {
                if pairs == 0 { read = ["differences": [Double]()] }
                else if let snapshot, let file = SnapshotStore.shared.file(for: snapshot) { read = ["snapshot": file.path, "pairs": pairs] }
            } else if page["error"] == nil, !paired, let samples = page["samples"] as? [[String: Any]] { read = ["samples": samples] }
            guard let read else { return (page, nil) }
            let request: [String: Any] = ["design": paired ? "paired" : "independent", "culture": culture, "separateSamples": separateSamples, "read": read]
            let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
                viewer.analysisRequest(request, entry: "statsdirect_measurement_check") { continuation.resume(with: $0) }
            }
            return (page, reply)
        }
        // D1: the reading starts below the headings and stops at the case's last value.
        func readRows(_ page: [String: Any], _ fixture: Fixture) -> Bool {
            let last = (fixture.rows.lastIndex { !$0.first.isEmpty || !$0.second.isEmpty } ?? -1) + 2
            return page["headerRow"] as? Bool == true && page["firstRow"] as? Int == 2 && page["lastRow"] as? Int == last
        }
        // A choice on the live card, clicked as the user clicks it; handled once the card is drawn again (the button gone) or an offer shows.
        func press(_ choice: String, _ what: String) async throws {
            guard let button: WorksheetAIChoiceButton = control("worksheet-ai-card-" + choice, in: pane.view), !button.isHiddenOrHasHiddenAncestor,
                  button.isEnabled, button.token == pane.guidanceToken else {
                throw ChatGPTTutor.Failure(message: "The card for \(what) shows no live \(choice) button: " + (card()?.text.debugDescription ?? "no card"))
            }
            button.performClick(nil)
            try await wait("Choosing \(choice) for \(what) was not handled") { button.superview == nil || pane.offer != nil }
        }
        var offers: [String: [String]] = [:], mismatches: [String] = []
        // Every branch of a read card: first each one the oracle does not allow, which must be refused with the card's conflict text and
        // keep its token; then each allowed one, which must offer its method (title, catalogue id, menu path, sheet, selection, report)
        // with the card's check and Windows' advice, after which Change sample choice must return to the same card.
        func branchesOf(_ fixture: Fixture, _ before: Card, _ parsed: WorksheetAIDistribution.Check, allowed: Set<String>,
                        _ selected: Selected) async throws -> (offered: [String], refused: [String], problems: [String]) {
            var offered: [String] = [], refused: [String] = [], problems: [String] = []
            for branch in branches.filter({ !allowed.contains($0) }) + branches.filter({ allowed.contains($0) }) {
                let token = pane.guidanceToken
                try await press(branch, fixture.name)
                guard let offer = pane.offer else {
                    let shown = label("worksheet-ai-distribution-feedback")
                    guard !shown.isEmpty else {
                        throw ChatGPTTutor.Failure(message: "Choosing \(branch) for \(fixture.name) gave neither an offer nor feedback: "
                                                   + (card()?.text.debugDescription ?? "no card") + ", notice " + label("worksheet-ai-notice").debugDescription)
                    }
                    try requireMarked(pane, "The card's feedback on \(branch) for \(fixture.name)")
                    refused.append(branch)
                    if shown != parsed.conflict || card()?.token != token { problems.append("\(branch) refused with \(shown.debugDescription), token kept \(card()?.token == token)") }
                    continue
                }
                let method = methodFor[fixture.paired]![branch]!
                let id = Mirror(reflecting: offer).children.first(where: { $0.label == "methodID" })?.value as? String
                try requireMarked(pane, "The \(branch) offer for \(fixture.name)")
                offered.append(branch)
                offers[fixture.name, default: []].append(branch + " " + (id ?? "?"))
                let destination = viewer.currentReportDestination?.title ?? "New report"
                let confirmation = label("worksheet-ai-confirmation"), details = label("worksheet-ai-offer-details")
                let sample: NSButton? = control("worksheet-ai-change-sample", in: pane.view)
                var wrong: [String] = []
                if offer.methodTitle != methodTitles[method] || id != method { wrong.append("method \(offer.methodTitle) (\(id ?? "no id"))") }
                if confirmation != [methodTitles[method]!, "Menu: " + menuPaths[method]!, "Worksheet: Preflight", "Selection: " + selected.offer,
                                    "Report: " + destination].joined(separator: "\n") { wrong.append("confirmation " + confirmation.debugDescription) }
                if details != (parsed.diagnostics + [adviceFor[fixture.paired]![branch]!]).joined(separator: "\n") { wrong.append("details " + details.debugDescription) }
                if card() != nil || sample?.title != "Change sample choice" || sample?.isHiddenOrHasHiddenAncestor != false { wrong.append("the card or Change sample choice") }
                if !wrong.isEmpty { problems.append("\(branch) offer: " + wrong.joined(separator: "; ")) }
                sample?.performClick(nil)
                let back = try await cardFor(before.kind, "Change sample choice did not return to the card for \(fixture.name) after \(branch)")
                if back.lines != before.lines || back.titles != before.titles || back.choices != before.choices || back.token == token || pane.offer != nil {
                    problems.append("Change sample choice after \(branch) returned " + back.text.debugDescription)
                }
            }
            return (offered, refused, problems)
        }
        // The card the pane drew is the engine's check of the reading, field by field.
        func same(_ parsed: WorksheetAIDistribution.Check, _ reply: [String: Any]) -> Bool {
            guard parsed.diagnostics == (reply["diagnostics"] as? [String] ?? []), parsed.recommendation == reply["recommendation"] as? String,
                  parsed.suggestedBranch == reply["suggestedBranch"] as? String, parsed.largeSample == reply["largeSample"] as? Bool,
                  parsed.conflict == reply["conflict"] as? String, parsed.sizeKnown == reply["sizeKnown"] as? Bool, parsed.canCheck == reply["canCheck"] as? Bool
            else { return false }
            return parsed.methods == (reply["methods"] as? [String: String] ?? [:]) && parsed.advice == (reply["advice"] as? [String: String] ?? [:])
        }
        // Windows' size rule for a read card: the size known, its conflict text, and each branch's method and advice.
        func windows(_ parsed: WorksheetAIDistribution.Check, paired: Bool, large: Bool) -> Bool {
            parsed.largeSample == large && parsed.conflict == conflictFor[paired]![large] && parsed.methods == methodFor[paired]! && parsed.advice == adviceFor[paired]!
        }
        func record(_ fixture: Fixture, _ problems: [String], _ summary: String) throws {
            if problems.isEmpty { try check(true, summary); return }
            print("MISMATCH: preflight \(fixture.name): " + problems.joined(separator: " | "))
            fflush(stdout)
            mismatches.append(fixture.name)
        }

        // One paired card, staged by the assistant, then every paired case selected in turn.
        let pairedFixtures = fixtures.filter(\.paired), independentFixtures = fixtures.filter { !$0.paired }
        _ = try await selectPair(pairedFixtures[0])
        pane.input.string = "FIXTURE_PAIRED_A"
        pane.send()
        _ = try await cardFor("paired-interval", "The staged paired card did not read " + pairedFixtures[0].name)
        try check((await text(pane)).contains("Check the fixture paired card below.") && !pane.isBusy && pane.clarification == nil,
                  "the tool stages one paired card, which reads the first case's columns when the reply completes")
        let quietPaired = dataTraffic()
        for fixture in pairedFixtures {
            let row = expected[fixture.name] ?? [:]
            let selected = try await selectPair(fixture)
            let drawn = try await cardFor("paired-interval", "The card did not read " + fixture.name + " at " + selected.caption)
            guard let parsed = pane.distribution?.card.check else { throw ChatGPTTutor.Failure(message: "The card for \(fixture.name) has no check") }
            let (page, answer) = try await engineCheck(paired: true, separateSamples: false)
            guard let reply = answer else { throw ChatGPTTutor.Failure(message: "The page did not read \(fixture.name): \(page)") }
            var problems: [String] = []
            func expect(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { problems.append(what()) } }
            let n = Int(row["n"] ?? "") ?? -1, large = n > 100, varying = row["varying"] == "TRUE"
            let w = decimal(row["W"]), p = decimal(row["P"])
            let outlier = row["fenceWarning"] == "TRUE", skew = row["skewWarning"] == "TRUE", heavy = row["heavyTailWarning"] == "TRUE"
            let values = reply["values"] as? [String: Any] ?? [:], shape = values["shape"] as? [String: Any]
            expect(readRows(page, fixture), "rows read \(page["firstRow"] ?? "none") to \(page["lastRow"] ?? "none"), header row \(page["headerRow"] ?? "none")")
            expect(values["count"] as? Int == n, "n \(values["count"] ?? "none")")
            expect(agrees(values["w"] as? Double, w) && agrees(values["p"] as? Double, p), "W \(values["w"] ?? "none"), P \(values["p"] ?? "none")")
            expect(values["hasVariation"] as? Bool == varying, "variation \(values["hasVariation"] ?? "none")")
            expect(values["hasPotentialOutlier"] as? Bool == outlier && values["hasSkewSignal"] as? Bool == skew && (shape?["hasHeavyTails"] as? Bool ?? false) == heavy,
                   "warnings: far-out \(values["hasPotentialOutlier"] ?? "none"), skew \(values["hasSkewSignal"] ?? "none"), heavy tails \(shape?["hasHeavyTails"] ?? "none")")
            expect((shape != nil) == !(row["Q1"] ?? "").isEmpty, "shape \(shape.map { "\($0)" } ?? "none")")
            if let shape, !(row["Q1"] ?? "").isEmpty {
                expect(agrees(shape["lowerQuartile"] as? Double, decimal(row["Q1"])) && agrees(shape["upperQuartile"] as? Double, decimal(row["Q3"]))
                       && shape["farOutCount"] as? Int == Int(row["farOut"] ?? "") && agrees(shape["skewness"] as? Double, decimal(row["skewness"]))
                       && agrees(shape["excessKurtosis"] as? Double, decimal(row["excessKurtosis"])), "shape \(shape)")
            }
            let suggested = (row["suggestedBranch"] ?? "").isEmpty ? nil : row["suggestedBranch"]
            let (branch, reason) = pairedReason(n, varying: varying, outlier: outlier, skew: skew, heavy: heavy, p: p)
            expect(branch == suggested, "Windows' rule gives \(branch ?? "no branch") from the oracle's values, which suggest \(suggested ?? "no branch")")
            expect(reply["suggestedBranch"] as? String == suggested && parsed.suggestedBranch == suggested, "suggested \(parsed.suggestedBranch ?? "no branch")")
            // The card as Windows writes it: the count, with W and P as R's values give them; above 100 pairs the shape lines
            // (D3: a skewness at rounding noise is the engine's own); then the reason under its heading.
            var lines = [(n == 1 ? "Local check found 1 complete pair" : "Local check found \(n) complete pairs")
                         + (w != nil ? normality(w, p) : large ? "" : ". Shapiro–Wilk needs at least three finite differences with some variation.")]
            if let farOut = row["farOut"], !farOut.isEmpty {
                lines.append("Shape check · \(farOut) beyond the 3× IQR fences")
                if let skewness = decimal(row["skewness"]), let kurtosis = decimal(row["excessKurtosis"]) {
                    let shown = abs(skewness) < 1e-10 ? (shape?["skewness"] as? Double).map(g3) ?? "none" : g3(skewness)
                    lines.append("Skewness \(shown) · Excess kurtosis \(g3(kurtosis))")
                }
            }
            expect(drawn.lines == lines + [(suggested != nil ? "Suggested branch" : "Review the differences") + "\n" + reason], "card text \(drawn.lines)")
            let titles: [String] = zip(branches, branchTitles[true]!).map { pair in (pair.0 == suggested ? "Suggested · " : "") + pair.1 } + ["Change design"]
            expect(drawn.choices == branches + ["back"] && drawn.titles == titles, "choices \(drawn.titles)")
            // The card the pane drew is the engine's check of this reading, and its size rule is Windows'.
            expect(same(parsed, reply), "the pane's check differs from the engine's reply \(reply)")
            expect(windows(parsed, paired: true, large: large), "size \(parsed.largeSample.map { "\($0)" } ?? "unknown"), its conflict, methods or advice")
            let allowed = Set((row["allowed"] ?? "").components(separatedBy: ","))
            let outcome = try await branchesOf(fixture, drawn, parsed, allowed: allowed, selected)
            problems += outcome.problems
            expect(Set(outcome.offered) == allowed, "offered \(outcome.offered), refused \(outcome.refused), but the oracle allows \(allowed.sorted())")
            let warnings = [("far-out", outlier), ("skew", skew), ("heavy tails", heavy)].filter { $0.1 }.map { $0.0 }
            let alsoCompared = (w != nil ? ", W, P" : "") + (shape != nil && !(row["Q1"] ?? "").isEmpty ? ", quartiles, far-out count, skewness, kurtosis" : "")
            try record(fixture, problems, "preflight \(fixture.name) (paired, \(selected.caption.dropFirst(11))): n \(n)\(alsoCompared) "
                       + (alsoCompared.isEmpty ? "agrees" : "agree") + " with R; warnings "
                       + (warnings.isEmpty ? "none" : warnings.joined(separator: ", ")) + "; suggests \(suggested ?? "no branch"); Windows' card text; "
                       + outcome.refused.map { $0 + " refused" }.joined(separator: ", ") + (outcome.refused.isEmpty ? "" : "; ")
                       + outcome.offered.map { $0 + " offers " + methodFor[true]![$0]! }.joined(separator: ", ") + " with Windows' advice; Change sample choice returns")
        }

        // The oracle's overflow through Check, and D1: with the option unticked, row 1 is read, and refused as the analysis refuses it.
        _ = try await selectPair(overflow)
        let unread = try await cardFor("paired-interval", "The card did not show the overflowing pair unread")
        let refusedOverflow = try await engineCheck(paired: true, separateSamples: false)
        try check(unread.lines.first == "How many complete pairs are there?" && unread.choices.first == "check" && unread.titles.first == "Check selected pairs"
                  && refusedOverflow.page["error"] as? String == tooLarge && refusedOverflow.reply == nil,
                  "the oracle's 1e308 and -1e308 leave the paired card unread, with Check selected pairs")
        try await press("check", "the overflowing pair")
        try await feedback(tooLarge, "Check did not refuse 1e308 minus -1e308")
        try check(card()?.choices.first == "check", "Check refuses 1e308 minus -1e308 with Windows' text, and stays offered")
        let pefr = pairedFixtures[0]
        _ = try await selectPair(pefr)
        let headed = try await cardFor("paired-interval", "The card did not read pefr again")
        try await grid(book, headerOption + ".click()")
        try await wait("The page did not report First row has column names unticked") { book.aiWorksheet?.headerRow == false }
        let unheaded = try await cardFor("paired-interval", "Unticking First row has column names did not read pefr again")
        try await press("check", "pefr without its headings")
        try await feedback("Cell A1: ‘pefr first’ is not numeric. Correct it or use * for a missing value. If row 1 holds column names, tick “First row has column names”.",
                           "Check did not refuse pefr's heading read as data")
        try await grid(book, headerOption + ".click()")
        try await wait("The page did not report First row has column names ticked") { book.aiWorksheet?.headerRow == true }
        let reheaded = try await cardFor("paired-interval", "Ticking First row has column names did not read pefr again")
        try check(unheaded.lines.first == "How many complete pairs are there?" && reheaded.lines == headed.lines && reheaded.token != headed.token,
                  "the headings are read as data only with First row has column names unticked, when Check names cell A1 and the setting")

        // Continue with an open report as the current destination: the card's offer names it, Continue opens the analysis for the
        // selected columns with it as the destination, and running it adds the result to that report and to no other.
        let savedDefaults = UserDefaults.standard.object(forKey: "analysisDefaults")
        defer { UserDefaults.standard.set(savedDefaults, forKey: "analysisDefaults") }
        UserDefaults.standard.set(["use-default-ci": true, "default-ci": "95", "selectGroupsByIdentifier": false], forKey: "analysisDefaults")
        // The data an analysis ran on, as the engine recorded its inputs (as Tests/analysis-workflow-driver.swift reads them).
        func dataColumns(_ run: Document) async throws -> [[Any]] {
            guard let job = run.completedJobID else { return [] }
            let history = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
                viewer.analysisRequest(["action": "poll", "id": job], entry: "statsdirect_operation") { continuation.resume(with: $0) }
            }
            let data = (history["history"] as? [[String: Any]] ?? []).first(where: { $0["name"] as? String == "data" })?["value"] as? [String: Any]
            return (data?["columns"] as? [[String: Any]] ?? []).map { $0["values"] as? [Any] ?? [] }
        }
        // A recorded input column's usable values: the form records the cells' texts, an empty or * cell being missing.
        func numbers(_ values: [Any]) -> [Double] {
            values.compactMap { value in (value as? String).flatMap { Double($0) } ?? (value as? NSNumber)?.doubleValue }.filter { $0.isFinite && $0 != -Double.greatestFiniteMagnitude }
        }
        func cellValues(_ fixture: Fixture) -> [[Double]] {
            [fixture.rows.compactMap { Double($0.first) }, fixture.rows.compactMap { Double($0.second) }]
        }
        func continued(_ what: String, destination: String) async throws -> Document {
            let before = viewer.documents.count
            (control("worksheet-ai-continue", in: pane.view) as NSButton?)?.performClick(nil)
            try await wait("Continue did not open " + what) { viewer.documents.count == before + 1 && viewer.active?.kind == "operation" }
            let run = viewer.active!
            try await wait("The \(what) form did not show its report destination") {
                let shown = (try? await run.web.evaluateJavaScript("document.querySelector('main header p')?.textContent ?? ''")) as? String
                return run.operationSourceSnapshot != nil && shown == "Report destination: " + destination
            }
            return run
        }
        func finished(_ run: Document, _ what: String, until done: () -> Bool) async throws {
            for _ in 0..<600 {
                if run.completedJobID != nil && done() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            let page = (try? await run.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
            throw ChatGPTTutor.Failure(message: what + " did not reach its report: " + String(page.prefix(600)).debugDescription)
        }
        let routed = viewer.makeReport()
        viewer.tabs.selectTabViewItem(book.item)
        try await wait("AI Assist did not return to the fixture workbook") { viewer.active === book && pane.workbookID == book.id }
        _ = try await cardFor("paired-interval", "The card did not keep pefr while the report opened")
        try await press("normal", "pefr")
        guard let routedOffer = pane.offer else { throw ChatGPTTutor.Failure(message: "Small or medium did not offer the paired t test for pefr") }
        try check(viewer.currentReportDestination === routed && routedOffer.reportTitle == routed.title
                  && label("worksheet-ai-confirmation").hasSuffix("\nSelection: Columns A:B\nReport: " + routed.title),
                  "with \(routed.title) open as the current report, the card's paired t offer for pefr names it")
        let others = viewer.documents.filter { $0.reportEntries != nil && $0 !== routed }.map { ($0, $0.reportEntries?.count ?? 0) }
        let quietRouting = dataTraffic()
        let pairedRun = try await continued("the paired t test", destination: routed.title)
        try check(pairedRun.operationName == "TPaired" && pairedRun.operationSourceID == book.id
                  && pairedRun.operationReportDestination == .existing(id: routed.id, title: routed.title)
                  && pairedRun.operationSourceSnapshot?["selection"] as? [Int] == [0, 1] && pane.offer == nil && pane.distribution == nil,
                  "Continue opens the paired t test for pefr's two selected columns with \(routed.title) as its destination, and retires the card")
        try await wait("The paired t test did not offer Run") {
            (try? await pairedRun.web.evaluateJavaScript("!!document.querySelector('.paired-inputs button[type=submit]:not(:disabled)')")) as? Bool == true
        }
        _ = try await pairedRun.web.evaluateJavaScript("document.querySelector('.paired-inputs button[type=submit]').click(); true")
        try await finished(pairedRun, "The paired t result") { routed.reportEntries?.count == 1 }
        let pairedColumns = try await dataColumns(pairedRun), pairedEntry = routed.reportEntries![0]
        let pairedValues = pairedColumns.map(numbers), untouched = others.allSatisfy { $0.0.reportEntries?.count == $0.1 }
        let reportCount = viewer.documents.filter { $0.reportEntries != nil }.count, routingQuiet = dataTraffic() == quietRouting
        let routedRight = pairedEntry.operation == "TPaired" && pairedEntry.body.contains("56.111111") && pairedValues == cellValues(pefr)
            && pairedValues.map(\.count) == [9, 9] && untouched && reportCount == others.count + 1 && routingQuiet
        try check(routedRight, "running it on pefr's nine pairs adds the paired t result (mean difference 56.111111) to \(routed.title) and to no other report, and sends nothing"
                  + (routedRight ? "" : " (operation \(pairedEntry.operation), mean difference shown \(pairedEntry.body.contains("56.111111")), values \(pairedValues),"
                  + " other reports unchanged \(untouched), reports \(reportCount) for \(others.count) others, quiet \(routingQuiet); data \(String(describing: pairedColumns).prefix(300)))"))
        viewer.remove(pairedRun)
        try check(dataTraffic() == quietPaired, "checking the paired cases, their branches, offers and the analysis sends nothing to the provider")

        // One independent card, staged by the assistant, then every independent case, confirmed as separate samples first.
        viewer.tabs.selectTabViewItem(book.item)
        try await wait("AI Assist did not return to the fixture workbook after the paired t test") { viewer.active === book && pane.workbookID == book.id && !pane.isBusy }
        _ = try await selectPair(independentFixtures[0])
        pane.input.string = "FIXTURE_INDEPENDENT_A"
        pane.send()
        _ = try await cardFor("independent-interval", "The staged independent card did not count " + independentFixtures[0].name)
        try check((await text(pane)).contains("Check the fixture independent card below.") && !pane.isBusy && pane.clarification == nil,
                  "the tool stages one independent card, which counts the first independent case when the reply completes")
        let quietIndependent = dataTraffic()
        for fixture in independentFixtures {
            let row = expected[fixture.name] ?? [:]
            let selected = try await selectPair(fixture)
            let counting = try await cardFor("independent-interval", "The card did not count " + fixture.name + " at " + selected.caption)
            guard let unconfirmed = pane.distribution?.card.check else { throw ChatGPTTutor.Failure(message: "The card for \(fixture.name) has no check") }
            var problems: [String] = []
            func expect(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { problems.append(what()) } }
            let n1 = Int(row["n1"] ?? "") ?? -1, n2 = Int(row["n2"] ?? "") ?? -1, large = row["large"] == "TRUE"
            let w1 = decimal(row["W1"]), p1 = decimal(row["P1"]), w2 = decimal(row["W2"]), p2 = decimal(row["P2"])
            let counted = ["Column 1: n = \(n1)" + normality(w1, p1), "Column 2: n = \(n2)" + normality(w2, p2)]
            expect(counting.lines == ["Selected columns, if they hold the two samples separately:"] + counted + groupQuestions
                   && counting.choices == ["check"] + branches + ["back"] && counting.titles == ["Use these as separate samples"] + branchTitles[false]! + ["Change design"]
                   && unconfirmed.largeSample == nil && unconfirmed.conflict == nil,
                   "before Use these as separate samples \(counting.lines), \(counting.titles)")
            try await press("check", fixture.name)
            let drawn = try await confirmedCard(counting, fixture.name)
            guard let parsed = pane.distribution?.card.check else { throw ChatGPTTutor.Failure(message: "The confirmed card for \(fixture.name) has no check") }
            let (page, answer) = try await engineCheck(paired: false, separateSamples: true)
            guard let reply = answer else { throw ChatGPTTutor.Failure(message: "The page did not read \(fixture.name): \(page)") }
            let values = reply["values"] as? [String: Any] ?? [:]
            let a = values["first"] as? [String: Any] ?? [:], b = values["second"] as? [String: Any] ?? [:]
            expect(readRows(page, fixture), "rows read \(page["firstRow"] ?? "none") to \(page["lastRow"] ?? "none"), header row \(page["headerRow"] ?? "none")")
            expect(a["count"] as? Int == n1 && agrees(a["w"] as? Double, w1) && agrees(a["p"] as? Double, p1), "column 1 \(a)")
            expect(b["count"] as? Int == n2 && agrees(b["w"] as? Double, w2) && agrees(b["p"] as? Double, p2), "column 2 \(b)")
            expect(drawn.lines == counted + groupQuestions && drawn.choices == branches + ["back"] && drawn.titles == branchTitles[false]! + ["Change design"],
                   "card \(drawn.lines), \(drawn.titles)")
            expect(same(parsed, reply) && parsed.recommendation == nil && parsed.suggestedBranch == nil, "the pane's check differs from the engine's reply \(reply)")
            expect(windows(parsed, paired: false, large: large), "size \(parsed.largeSample.map { "\($0)" } ?? "unknown"), its conflict, methods or advice")
            let allowed = Set((row["allowedWhenSeparate"] ?? "").components(separatedBy: ","))
            let outcome = try await branchesOf(fixture, drawn, parsed, allowed: allowed, selected)
            problems += outcome.problems
            expect(Set(outcome.offered) == allowed, "offered \(outcome.offered), refused \(outcome.refused), but the oracle allows \(allowed.sorted())")
            try record(fixture, problems, "preflight \(fixture.name) (independent, \(selected.caption.dropFirst(11))): n \(n1) and \(n2)"
                       + (w1 != nil || w2 != nil ? " with W and P" : "") + " agree with R; \(large ? "" : "not ")large once confirmed as separate samples; Windows' card text; "
                       + outcome.refused.map { $0 + " refused" }.joined(separator: ", ") + (outcome.refused.isEmpty ? "" : "; ")
                       + outcome.offered.map { $0 + " offers " + methodFor[false]![$0]! }.joined(separator: ", ") + " with Windows' advice; Change sample choice returns")
        }
        try check(dataTraffic() == quietIndependent, "checking the independent cases, their branches and offers sends nothing to the provider")
        let named = ["pefr", "small_bimodal", "normal_101", "large_skewed", "uneven_missing", "n101_n101"]
        try check(named.allSatisfy { offers[$0] != nil } && expected["large_skewed"]?["suggestedBranch"] == "",
                  "the offers name Windows' methods with its advice: " + named.map { $0 + " (" + (offers[$0] ?? []).joined(separator: ", ") + ")" }.joined(separator: ", ")
                  + ", large_skewed suggesting no branch")

        // Continue with no report open: the offer says New report, and the result goes to a new report.
        viewer.remove(routed)
        if viewer.documents.contains(where: { $0 === report }) { viewer.remove(report) }
        viewer.tabs.selectTabViewItem(book.item)
        try await wait("AI Assist did not return to the fixture workbook with no report open") {
            viewer.active === book && pane.workbookID == book.id && viewer.currentReportDestination == nil
        }
        guard let uneven = independentFixtures.first(where: { $0.name == "uneven_missing" }) else { throw ChatGPTTutor.Failure(message: "No uneven_missing case") }
        let unevenSelection = try await selectPair(uneven)
        let unevenCount = try await cardFor("independent-interval", "The card did not count uneven_missing again")
        try await press("check", "uneven_missing")
        _ = try await confirmedCard(unevenCount, "uneven_missing")
        try await press("normal", "uneven_missing")
        guard let newOffer = pane.offer else { throw ChatGPTTutor.Failure(message: "Small or medium did not offer the unpaired t test for uneven_missing") }
        try check(newOffer.reportTitle == "New report" && label("worksheet-ai-confirmation").hasSuffix("\nSelection: " + unevenSelection.offer + "\nReport: New report"),
                  "with no report open, the card's unpaired t offer for uneven_missing says New report")
        let quietNew = dataTraffic()
        let unpairedRun = try await continued("the unpaired t test", destination: "New report")
        try check(unpairedRun.operationName == "TUnpaired" && unpairedRun.operationSourceID == book.id && unpairedRun.operationReportDestination == .new
                  && unpairedRun.operationSourceSnapshot?["selection"] as? [Int] == unevenSelection.columns && pane.offer == nil && pane.distribution == nil,
                  "Continue opens the unpaired t test for uneven_missing's two selected columns with a new report as its destination")
        try await finished(unpairedRun, "The unpaired t result") { viewer.documents.contains { $0.reportEntries?.count == 1 } }
        let created = viewer.documents.filter { $0.reportEntries != nil }
        let unpairedColumns = try await dataColumns(unpairedRun)
        let unpairedValues = unpairedColumns.map(numbers), newQuiet = dataTraffic() == quietNew
        let newDestination = created.count == 1 && unpairedRun.operationReportDestination == .existing(id: created[0].id, title: created[0].title)
        let newRight = newDestination && created[0].reportEntries?.first?.operation == "TUnpaired" && unpairedValues == cellValues(uneven)
            && unpairedValues == [[1, 2, 4, 6, 8], [0, 1, 2]] && newQuiet
        try check(newRight, "running it on uneven_missing's 5 and 3 values puts the unpaired t result in a new report, \(created.first?.title ?? "none"), and sends nothing"
                  + (newRight ? "" : " (reports \(created.map(\.title)), destination \(String(describing: unpairedRun.operationReportDestination)),"
                  + " operation \(created.first?.reportEntries?.first?.operation ?? "none"), values \(unpairedValues), quiet \(newQuiet);"
                  + " data \(String(describing: unpairedColumns).prefix(300)))"))
        viewer.remove(unpairedRun)
        for made in created { viewer.remove(made) }

        viewer.remove(book)
        if let previous, viewer.documents.contains(where: { $0 === previous }) {
            viewer.tabs.selectTabViewItem(previous.item)
            if previous.kind == "grid" { try await wait("AI Assist did not return to the workbook open before the fixtures") { pane.workbookID == previous.id } }
        }
        let traffic = requestLines()[requestsBefore...].joined(separator: "\n")
        try check(!(cardWords + fixtures.flatMap { [$0.name + " first", $0.name + " second"] }).contains(where: traffic.contains),
                  "no request carries a fixture's heading or any card's wording")
        try check(mismatches.isEmpty, "every one of the preflight's 26 paired and 5 independent cases agrees with R and Windows through the worksheet UI"
                  + (mismatches.isEmpty ? "" : ": mismatched " + mismatches.joined(separator: ", ")))
    }
}

/// What every part of the worksheet AI run shares: the app, the mock's folder, and the helpers run once defined inline. Each
/// part is a function of its own: as one async function of about 300 suspension points, run took the Swift compiler more
/// than four minutes, almost all of it lowering that one coroutine.
@MainActor final class WorksheetAIHarness {
    let viewer: Viewer
    let directory: URL
    let storage: URL
    let root: URL
    /// AI Assist, once the worksheet toolbar has opened it (it is never replaced).
    var pane: WorksheetAIPane { viewer.worksheetAI! }
    let checkbox = "document.querySelector('.worksheet-options input[type=checkbox]').click()"
    let unpaired = "Select two adjacent, visible columns of matched measurements in one worksheet range."
    let chooseLine = "Were these measurements taken from the same people or units?"

    init(viewer: Viewer, directory: URL, storage: URL, root: URL) {
        self.viewer = viewer; self.directory = directory; self.storage = storage; self.root = root
    }

    func check(_ condition: Bool, _ message: String) throws { try WorksheetAIChecks.check(condition, message) }
    func wait(_ message: String, until condition: () async -> Bool) async throws {
        try await WorksheetAIChecks.wait(message, until: condition)
    }

    func openWorkbook(in folder: String, value: String) async throws -> Document {
        let location = directory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let file = location.appendingPathComponent("Fictional.xlsx")
        let path = file.resolvingSymlinksInPath()
        try FileManager.default.copyItem(at: viewer.root.appendingPathComponent("Examples/test.xlsx"), to: file)
        viewer.openExcelURL(file)
        try await wait("Workbook did not open from " + folder) {
            guard let doc = viewer.active, doc.openedFileURL?.resolvingSymlinksInPath() == path,
                  doc.pendingWorkbook == nil, !doc.web.isLoading else { return false }
            return (try? await doc.web.evaluateJavaScript("!!window.statsDirectGrid")) as? Bool == true
        }
        let doc = viewer.active!
        _ = try await doc.web.callAsyncJavaScript("""
            statsDirectGrid.setCellText({col:0,row:0,text:'Score'});
            statsDirectGrid.setCellText({col:0,row:1,text:value});
            return true;
            """, arguments: ["value": value], in: nil, contentWorld: .page)
        try await wait("Workbook edits did not settle") { doc.gridVersion >= 2 }
        return doc
    }
    func toolbar(_ doc: Document, _ id: String) async throws {
        _ = try await doc.web.evaluateJavaScript("document.querySelector('[data-command=\(id)]').click()")
    }
    func text(_ pane: WorksheetAIPane) async -> String {
        (try? await pane.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
    }
    func control<T: NSView>(_ id: String, in view: NSView) -> T? {
        if view.identifier?.rawValue == id, let match = view as? T { return match }
        for child in view.subviews {
            if let match: T = control(id, in: child) { return match }
        }
        return nil
    }
    // Windows pull request 40, engine-independent part: the live selection, the Data used receipt (headings, Stop
    // and failure), Reply in progress, the clarifying card, the structure-only overview and the empty-workbook choices.
    func grid(_ doc: Document, _ script: String) async throws {
        _ = try await doc.web.callAsyncJavaScript(script + "; return true;", arguments: [:], in: nil, contentWorld: .page)
    }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: storage.appendingPathComponent(name).path) }
    // A stack view detaches a hidden control only at its next layout pass, so "not shown" is hidden or absent.
    func shown(_ id: String) -> Bool {
        let found: NSView? = control(id, in: pane.view)
        return found?.isHiddenOrHasHiddenAncestor == false
    }
    // The receipt under the latest reply only: its Data used lines, and whether it says no cells were read.
    func lastReceipt() async -> (lines: [String], none: Bool) {
        let value = (try? await pane.transcript.web.evaluateJavaScript("""
            (() => { const rows = document.querySelectorAll('article.assistant'), last = rows[rows.length - 1];
              return last ? {lines: [...last.querySelectorAll(':scope > details[data-receipt] li')].map(item => item.textContent),
                             none: !!last.querySelector(':scope > .data-used-none')} : {lines: [], none: false}; })()
            """)) as? [String: Any]
        return ((value?["lines"] as? [String]) ?? [], value?["none"] as? Bool == true)
    }
    func assistantRows() async -> Int {
        (try? await pane.transcript.web.evaluateJavaScript("document.querySelectorAll('article.assistant').length")) as? Int ?? -1
    }
    // The distribution cards' checks. What reached the provider: every request, and the questions and tool results
    // among them (Windows WorksheetAnalysisDataTraffic).
    func requestLines() -> [String] {
        ((try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }
    func dataTraffic() -> [String] {
        requestLines().filter { line in
            guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return false }
            return request["method"] as? String == "turn/start" || request["result"] != nil
        }
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }
    func label(_ id: String) -> String {
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        return (control(id, in: pane.view) as NSTextField?)?.stringValue ?? ""
    }
    // The shown card as Windows' WorksheetActionSnapshot gives it: its kind, its buttons' token, its paragraphs and its
    // choices with their titles.
    struct Card {
        let kind: String, token: String, lines: [String], choices: [String], titles: [String]
        var text: String { (lines + titles).joined(separator: "\n") }
    }
    func card() -> Card? {
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        guard let box: NSView = control("worksheet-ai-distribution", in: pane.view), !box.isHiddenOrHasHiddenAncestor,
              let kind = pane.distribution?.card.kind.rawValue else { return nil }
        let buttons = views(WorksheetAIChoiceButton.self, in: box)
        return Card(kind: kind, token: buttons.first?.token ?? "", lines: views(NSTextField.self, in: box).map(\.stringValue),
                    choices: buttons.map(\.choice), titles: buttons.map(\.title))
    }
    // Windows WaitForWorksheetEvidence: the card of this kind, drawn with the live token and its selection read, holding
    // every piece of evidence and none of `absent`, and each of its lines that carries data marked (requireMarked). A failure
    // shows the card as it stood.
    @discardableResult func waitCard(_ kind: String, _ evidence: [String], _ message: String, absent: [String] = []) async throws -> Card {
        for _ in 0..<300 {
            if let shown = card(), shown.kind == kind, shown.token == pane.guidanceToken, pane.guidanceFingerprint != nil,
               evidence.allSatisfy(shown.text.contains), !absent.contains(where: shown.text.contains) {
                try WorksheetAIChecks.requireMarked(pane, "The \(kind) card (\(pane.selectionLabel.stringValue))")
                return shown
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChatGPTTutor.Failure(message: message + ": " + (card()?.text.debugDescription ?? "no card"))
    }
    // Windows ClickWorksheetAction: the live card's button, clicked as the user would.
    func click(_ choice: String) throws {
        guard let button: WorksheetAIChoiceButton = control("worksheet-ai-card-" + choice, in: pane.view),
              !button.isHiddenOrHasHiddenAncestor, button.token == pane.guidanceToken else {
            throw ChatGPTTutor.Failure(message: "The card shows no live \(choice) button")
        }
        button.performClick(nil)
    }
    func feedback(_ text: String, _ message: String) async throws {
        try await wait(message + ": " + label("worksheet-ai-distribution-feedback").debugDescription) {
            label("worksheet-ai-distribution-feedback") == text
        }
        try WorksheetAIChecks.requireMarked(pane, "The card with its feedback (\(pane.selectionLabel.stringValue))")
    }
    // The offer of a method chosen on a card: its confirmation and the card's check and advice beneath it, each line that carries
    // data marked (requireMarked).
    func offered(_ title: String) async throws -> String {
        var shown = ""
        for _ in 0..<300 {
            if pane.offer?.methodTitle == title {
                shown = label("worksheet-ai-confirmation") + "\n" + label("worksheet-ai-offer-details")
                if shown.hasPrefix(title) {
                    try WorksheetAIChecks.requireMarked(pane, "The \(title) offer (\(pane.selectionLabel.stringValue))")
                    return shown
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChatGPTTutor.Failure(message: "The \(title) offer did not appear: offer \(pane.offer?.methodTitle ?? "none"), notice "
                                   + label("worksheet-ai-notice").debugDescription + ", card " + (card()?.text.debugDescription ?? "none"))
    }
    func button(_ title: String) -> NSButton? {
        views(NSButton.self, in: pane.view).first { $0.title == title && !$0.isHiddenOrHasHiddenAncestor }
    }
    func select(_ doc: Document, _ script: String, _ caption: String) async throws {
        try await grid(doc, "statsDirectGrid." + script)
        try await wait("The selection label did not show " + caption) { pane.selectionLabel.stringValue == caption }
    }

    /// AI Assist pressed in the worksheet toolbar with the pane already open, as the user does to get back to the composer:
    /// once the pane has asked the page for its state, and a reading that would follow has had time to land, the card must
    /// be exactly as it was, with its token, its text, its feedback and its check (Windows keeps a card whose selection is
    /// unchanged, ScriptAIPane.WorksheetAnalysis.cs:296, and its test WorksheetAnalysis.cs:432-434).
    func keptThroughToolbar(_ doc: Document, _ what: String) async throws {
        guard let before = card(), let reading = pane.distribution?.card.check else {
            throw ChatGPTTutor.Failure(message: "No read card before AI Assist was pressed for " + what)
        }
        let feedback: String = label("worksheet-ai-distribution-feedback")
        viewer.window.makeFirstResponder(nil)
        try await toolbar(doc, "worksheetAI")
        try await wait("AI Assist in the toolbar did not reach the open pane") { viewer.window.firstResponder === pane.input }
        try await grid(doc, "0")                          // after the pane's own request for the page's state
        try await Task.sleep(for: .milliseconds(1000))     // a reading the engine would make lands well within this
        let after: Card? = card(), now: WorksheetAIDistribution.Check? = pane.distribution?.card.check
        let kept: Bool = after?.token == before.token && after?.text == before.text && after?.choices == before.choices
            && label("worksheet-ai-distribution-feedback") == feedback && now?.largeSample == reading.largeSample
            && now?.canCheck == reading.canCheck && pane.guidanceToken == before.token && pane.offer == nil
        try check(kept, "AI Assist pressed in the toolbar with the pane open keeps " + what
                  + (kept ? "" : ": card \(after?.text.debugDescription ?? "none"), token kept \(after?.token == before.token)"))
    }

    /// A branch of the other size chosen again on the card as it stands: refused with the card's feedback, the card and its
    /// token kept, and no offer.
    func refusedAgain(_ choice: String, _ conflict: String, _ message: String) async throws {
        guard let before = card(), let button: WorksheetAIChoiceButton = control("worksheet-ai-card-" + choice, in: pane.view),
              !button.isHiddenOrHasHiddenAncestor, button.token == pane.guidanceToken else {
            throw ChatGPTTutor.Failure(message: "The card shows no live \(choice) button")
        }
        button.performClick(nil)
        try await wait("Choosing \(choice) again was not handled") { button.superview == nil || pane.offer != nil }
        try check(pane.offer == nil && label("worksheet-ai-distribution-feedback") == conflict && card()?.token == before.token, message)
    }

    /// The live card's button given the keyboard focus, as Tab gives it with Full Keyboard Access, then pressed as Space presses
    /// it. False when this Mac's buttons cannot take the focus; the button is pressed all the same.
    func pressWithFocus(_ choice: String) throws -> Bool {
        guard let button: WorksheetAIChoiceButton = control("worksheet-ai-card-" + choice, in: pane.view),
              !button.isHiddenOrHasHiddenAncestor, button.token == pane.guidanceToken else {
            throw ChatGPTTutor.Failure(message: "The card shows no live \(choice) button")
        }
        return pressWithFocus(button)
    }

    /// Any shown button of the pane (the offer's Continue or Cancel) given the keyboard focus and pressed, as above.
    func pressWithFocus(_ button: NSButton) -> Bool {
        let focused: Bool = viewer.window.makeFirstResponder(button) && viewer.window.firstResponder === button
        button.performClick(nil)
        return focused
    }

    /// Whether the first choice of the card now drawn has the keyboard focus.
    func focusOnFirstChoice() -> Bool {
        guard let responder = viewer.window.firstResponder as? WorksheetAIChoiceButton, let shown = card() else { return false }
        return responder.choice == shown.choices.first && responder.token == pane.guidanceToken && !responder.isHiddenOrHasHiddenAncestor
    }

    /// A check of where the keyboard focus went (Windows moves it to the first button of whatever replaces a card that held it,
    /// Learning/conversation.mjs:112 and :227). Buttons take the focus only with Full Keyboard Access, so without it the check
    /// is reported and skipped, as the earlier focus checks are. The focus then goes back to the composer.
    func checkFocus(_ focusable: Bool, _ condition: Bool, _ message: String) throws {
        if focusable { try check(condition, message) }
        else { print("INFO: buttons do not take keyboard focus here (Full Keyboard Access is off); not exercised: " + message) }
        viewer.window.makeFirstResponder(pane.input)
    }
}

extension WorksheetAIHarness {
    func sharedReads() async throws -> (Document, Document) {
        let first = try await openWorkbook(in: "Workbook A", value: "142741")
        try await toolbar(first, "worksheetAI")
        try await wait("Worksheet toolbar did not open AI Assist") { viewer.worksheetAI?.workbookID == first.id }
        try check(pane.share.state == .off && pane.confirm.state == .off, "worksheet sharing starts off")
        let second = try await openWorkbook(in: "Workbook B", value: "281593")
        try check(pane.workbookID == second.id && pane.share.state == .off, "opening a workbook follows it without authorising it")
        let workbookLabel: NSTextField? = control("worksheet-ai-workbook", in: pane.view)
        let labelB = workbookLabel?.stringValue ?? ""
        try check(labelB.contains("Fictional.xlsx") && labelB.contains("Workbook B") && !labelB.contains("Workbook A"),
                  "the sharing label distinguishes same-named Excel files by folder")
        try JSONSerialization.data(withJSONObject: ["A": first.id, "B": second.id])
            .write(to: storage.appendingPathComponent("workbooks.json"))
        _ = try await viewer.chatGPTTutor.signIn()
        try await viewer.chatGPTTutor.refreshAccount()

        for (doc, name) in [(first, "A"), (second, "B")] {
            viewer.tabs.selectTabViewItem(doc.item)
            try check(workbookLabel?.stringValue.contains("Workbook " + name) == true,
                      "switching to workbook \(name) displays its folder")
            try check(pane.share.state == .off && pane.confirm.state == .off, "each workbook needs its own approval")
            pane.share.performClick(nil)
            try check(!pane.sendButton.isEnabled, "worksheet sharing requires confirmation")
            pane.confirm.performClick(nil)
            pane.input.string = "READ_" + name
            pane.send()
            try await wait("The mock could not read its approved workbook " + name) {
                guard !pane.isBusy else { return false }
                return (await text(pane)).contains("Synthetic workbook \(name) data checked.")
            }
        }
        try check(true, "the mock verified bidirectional workbook-data isolation and exact approved cells")
        return (first, second)
    }

    func methodPicker(_ first: Document, _ second: Document) async throws {
        let folded = try await pane.transcript.web.evaluateJavaScript("!!document.querySelector('details[data-r-block]:not([open])')") as? Bool
        try check(folded == true, "suggested R code is collapsed in the worksheet reply")
        _ = try await pane.transcript.web.evaluateJavaScript("""
            document.querySelector('details[data-r-block]').open = true;
            document.querySelector('[data-code=r]').click();
            """)
        try await wait("Open in R did not create a review tab") { viewer.active?.rConsolePane != nil }
        let review = viewer.active!
        try check(review.rConsolePane?.sourceText.contains("mean(2:4)") == true && review.rConsolePane?.hasWorkspace == false
                  && pane.workbookID == second.id,
                  "Open in R creates an unexecuted review tab without retargeting the worksheet dock")
        viewer.remove(review)
        viewer.tabs.selectTabViewItem(second.item)
        let count = viewer.documents.count
        _ = try await second.web.evaluateJavaScript("window.statsDirectGrid.editCommand('selectAll', '')")
        pane.chooseMethod.performClick(nil)
        try await wait("Choose a method did not open the native Analyse catalogue") {
            (try? await second.web.evaluateJavaScript("!!document.getElementById('worksheet-analysis-search')")) as? Bool == true
        }
        _ = try await second.web.evaluateJavaScript("""
            const field = document.getElementById('worksheet-analysis-search');
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, 'paired t');
            field.dispatchEvent(new Event('input', {bubbles:true}));
            """)
        try await wait("Paired t did not appear in the method picker") {
            (try? await second.web.evaluateJavaScript("!!document.querySelector('[data-worksheet-command=TPaired]')")) as? Bool == true
        }
        _ = try await second.web.evaluateJavaScript("document.querySelector('[data-worksheet-command=TPaired]').click()")
        try await wait("The method picker did not create a local confirmation") { pane.offer != nil }
        try check(viewer.documents.count == count, "choosing a method waits for Continue before opening an analysis")
        let confirmation: NSTextField? = control("worksheet-ai-confirmation", in: pane.view)
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        try check(confirmation?.stringValue.contains("Menu: Analysis › Parametric") == true,
                  "the inline confirmation gives the method's menu path")
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        if let proceed {
            let action = pane.view.convert(proceed.bounds, from: proceed)
            let history = pane.view.convert(pane.transcript.view.bounds, from: pane.transcript.view)
            let above = pane.view.isFlipped ? action.maxY <= history.minY : action.minY >= history.maxY
            try check(above && !proceed.isHiddenOrHasHiddenAncestor,
                      "Continue appears above the transcript beside the worksheet controls")
        } else { throw ChatGPTTutor.Failure(message: "The visible Continue button was not found") }
        // Ended from code, as a workbook switch or a new question ends it, an offer passes no keyboard focus on, even from
        // Continue; nor does Cancel pressed with the mouse while the focus is elsewhere (with the keyboard, see independentCards).
        let codeFocus: Bool = proceed.map { viewer.window.makeFirstResponder($0) && viewer.window.firstResponder === $0 } ?? false
        pane.cancelAnalysis()
        try checkFocus(codeFocus, pane.offer == nil && viewer.window.firstResponder !== pane.helpChoose,
                       "an offer ended from code passes no keyboard focus on to the general choices, even from Continue")
        pane.prepareAnalysis("TPaired")
        try await wait("The paired t test was not offered again") { pane.offer != nil }
        viewer.window.makeFirstResponder(nil)
        button("Cancel")?.performClick(nil)
        try check(pane.offer == nil && viewer.window.firstResponder === viewer.window,
                  "Cancel pressed with the mouse ends the offer and leaves the keyboard focus where it was")
    }

    func followsWorkbooks(_ first: Document, _ second: Document) async throws -> Document {
        viewer.tabs.selectTabViewItem(second.item)
        pane.input.string = "Keep this draft for B"
        viewer.tabs.selectTabViewItem(first.item)
        try check(pane.share.state == .on && pane.confirm.state == .on, "returning restores the workbook's approval")
        pane.input.string = "FINISH_A"
        pane.send()
        try await wait("The fixture did not start a read in A") {
            (await text(pane)).contains("Reading A after the switch.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        try Data().write(to: storage.appendingPathComponent("finish-stream"))
        try await wait("A's reply did not finish before following B") { !pane.isBusy && pane.workbookID == second.id }
        try check(pane.input.string == "Keep this draft for B", "natural reply completion follows the most recent workbook")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("A did not keep its completed response") {
            (await text(pane)).contains("Synthetic workbook A data checked after switching.")
        }
        try check(true, "a streamed data read after switching stays scoped to the original approved workbook")
        pane.input.string = "STOP_A"
        pane.send()
        try await wait("The fixture did not stream in A") {
            guard pane.isBusy else { return false }
            return (await text(pane)).contains("Streaming for A.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        let report = viewer.makeReport()
        try check(pane.workbookID == first.id && pane.isBusy, "a report and a new workbook do not retarget a streaming reply")
        pane.stop()
        try await wait("Stop did not switch to the pending workbook") { !pane.isBusy && pane.workbookID == second.id }
        try check(pane.input.string == "Keep this draft for B", "following the last workbook restores its own draft")
        let restored = await text(pane)
        try check(!restored.contains("Streaming for A."), "the stopped partial reply stays in its original transcript")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("The stopped reply was lost") { (await text(pane)).contains("Reply stopped before completion") }
        return report
    }

    func closeAndQuestionOnly(_ first: Document, _ second: Document) async throws {
        pane.input.string = "CLOSE_A"
        pane.send()
        try await wait("The fixture did not start the reply to close") {
            (await text(pane)).contains("Close-test stream for A.")
        }
        viewer.tabs.selectTabViewItem(second.item)
        pane.hide()
        try await wait("Closing the pane did not interrupt the reply and reject a late read") {
            !pane.isBusy && FileManager.default.fileExists(atPath: storage.appendingPathComponent("close-read-rejected").path)
        }
        try check(!pane.visible && pane.workbookID == first.id, "closing the dock stops sharing without switching the hidden conversation")
        try await toolbar(second, "worksheetAI")
        try await wait("The reopened dock did not follow the active workbook") { pane.visible && pane.workbookID == second.id }
        try check(!(await text(pane)).contains("Close-test stream for A."), "the reopened dock does not show the other workbook's partial reply")
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("Closing the dock lost the original stopped reply") {
            let transcript = await text(pane)
            return transcript.contains("Close-test stream for A.") && transcript.contains("Reply stopped before completion")
        }
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        let questionHint: NSTextField? = control("worksheet-ai-question-only-hint", in: pane.view)
        try check(questionHint?.isHiddenOrHasHiddenAncestor == false
                  && questionHint?.stringValue.localizedCaseInsensitiveContains("full question each time") == true,
                  "question-only mode explains that each send needs the full question")
        pane.input.string = "QUESTION_ONLY"
        pane.send()
        try await wait("Question-only mode did not send a clean payload") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("General guidance without workbook data.")
        }
        try check(true, "question-only payload omits workbook, data tools and earlier chat")
        let questionOnlyReceipt = await lastReceipt()
        try check(questionOnlyReceipt.none && questionOnlyReceipt.lines.isEmpty, "a reply that read no cells says so under it")
    }

    func methodMarkers() async throws {
        // Markers wherever a real reply puts them: after a sentence, in a list item, in backticks; never inside code.
        let cases: [(String, String, [String])] = [
            ("Use this.\n[[method:TPaired]]\nThen check.", "Use this.\n\nThen check.", ["TPaired"]),
            ("I haven't run the test. [[method:TPaired]]", "I haven't run the test.", ["TPaired"]),
            ("Try [[method:TPaired]] or `[[method:Wilcoxon]]` here.", "Try or here.", ["TPaired", "Wilcoxon"]),
            ("- [[method:TPaired]]\n  1. `[[method:Wilcoxon]]`\n> [[method:TPaired]]", "\n\n", ["TPaired", "Wilcoxon", "TPaired"]),
            ("[[method:TPaired]] is the paired test", " is the paired test", ["TPaired"]),
            ("```r\n# [[method:TPaired]]\n```\n[[method:Wilcoxon]]", "```r\n# [[method:TPaired]]\n```\n", ["Wilcoxon"]),
            ("~~~~\n[[method:TPaired]]\n~~~\n[[method:TPaired]]\n~~~~\nafter [[method:Wilcoxon]]", "~~~~\n[[method:TPaired]]\n~~~\n[[method:TPaired]]\n~~~~\nafter", ["Wilcoxon"]),
            ("1. ```r\n   x <- '[[method:TPaired]]'\n   ```\n[[method:TPaired]]", "1. ```r\n   x <- '[[method:TPaired]]'\n   ```\n", ["TPaired"]),
            ("Inline ```code``` then [[method:TPaired]]", "Inline ```code``` then", ["TPaired"]),
            ("No marker: [[method:]] [[method:T Paired]] [method:TPaired]", "No marker: [[method:]] [[method:T Paired]] [method:TPaired]", [])
        ]
        for (reply, shown, ids) in cases {
            let read = WorksheetAIMarkers.read(reply)
            guard read.text == shown, read.ids == ids else {
                throw ChatGPTTutor.Failure(message: "Method markers misread in \(reply.debugDescription): \(read.text.debugDescription) \(read.ids)")
            }
        }
        try check(true, "method markers are read after a sentence, in a list item and in backticks, and never inside code (\(cases.count) cases)")
        pane.input.string = "INLINE_MARKER"
        pane.send()
        try await wait("The reply with markers inside its text did not arrive") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Marker reply for the paired design.")
        }
        let markerReply = await text(pane)
        let paired: NSButton? = control("TPaired", in: pane.view), plot: NSButton? = control("BoxWhiskerPlot", in: pane.view)
        let code = try await pane.transcript.web.evaluateJavaScript(
            "document.querySelector('article.assistant:last-of-type code').textContent") as? String
        try check(!markerReply.contains("[[method:") && markerReply.contains("Marker reply for the paired design.")
                  && markerReply.contains("shows the pairs")
                  && paired?.isHiddenOrHasHiddenAncestor == false && plot?.isHiddenOrHasHiddenAncestor == false
                  && code?.contains("# [[method:TPaired]] stays in code") == true,
                  "a marker inside a sentence or in backticks is not shown, still offers its method, and code keeps its text")
    }

    func selectionAndOverview(_ first: Document) async throws {
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A") { pane.workbookID == first.id && !pane.isBusy }
        let beforeHeading = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:1,row:0,text:'Qzheading'})")
        try await wait("The heading edit did not settle") { first.gridVersion > beforeHeading }

        try await grid(first, "statsDirectGrid.selectCells({x:1,y:2,width:1,height:1})")
        try await wait("The selection label did not show the current cell") {
            pane.selectionLabel.stringValue == "Current cell: Parametric!B3" && !pane.selectionLabel.isHidden
        }
        try check(true, "the pane's label follows the current cell")
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:1,width:2,height:4})")
        try await wait("The selection label did not show the selected range") { pane.selectionLabel.stringValue == "Selection: Parametric!A2:B5" }
        try check(true, "the pane's label shows a selected range in A1 notation")
        try await grid(first, "statsDirectGrid.clearSelection()")
        try await wait("Clearing the selection did not hide the label") { pane.selectionLabel.isHidden }
        try check(true, "with nothing selected the label is hidden")

        // Share A again: the earlier question-only check turned its sharing off.
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        try check(pane.replyActivity.isHidden, "no reply indicator while AI Assist is idle")
        pane.input.string = "OVERVIEW_A"
        pane.send()
        try check(pane.isBusy && !pane.replyActivity.isHidden && pane.replyActivity.stringValue == "Reply in progress…" && pane.stopButton.isEnabled,
                  "Reply in progress… appears beside Stop as soon as a question is sent")
        try await wait("The overview reply did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Overview checked for A.")
        }
        try check(pane.replyActivity.isHidden, "Reply in progress… goes when the reply completes")
        try check(exists("overview-checked"), "the shared overview gives sheets, extents, column letters and the selection, but no headings or cell values")
        let overviewRead = try JSONSerialization.jsonObject(with: Data(contentsOf: storage.appendingPathComponent("overview-read.json"))) as? [String: Any]
        let headings = overviewRead?["headerRow"] as? Bool == true
        try check(headings && (overviewRead?["titles"] as? [String]) == ["Score", "Qzheading"],
                  "the row-1 headings travel only as the titles of a bounded read")
        let overviewLines = await lastReceipt().lines
        try check(overviewLines == ["Fictional.xlsx · Parametric · A1:B1 (headings), A2:B3 (part of the worksheet’s used range)"],
                  "Data used lists the range read and the headings sent as titles: \(overviewLines)")
        let summary = try await pane.transcript.web.evaluateJavaScript("document.querySelector('article > details[data-receipt] > summary').textContent") as? String
        try check(summary == "Data used", "the receipt is a Data used disclosure under the reply")
    }

    func clarificationCard(_ first: Document) async throws {
        pane.input.string = "CLARIFY_A"
        pane.send()
        try await wait("The clarifying question did not appear") { !pane.isBusy && pane.clarification != nil }
        let question: NSTextField? = control("worksheet-ai-clarification-question", in: pane.view)
        let means: NSButton? = control("worksheet-ai-choice-means", in: pane.view), unsure: NSButton? = control("worksheet-ai-choice-unsure", in: pane.view)
        let general: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
        try check(question?.stringValue == "What would you like to find out?" && means?.title == "Compare means" && unsure?.title == "I’m not sure"
                  && means?.isHiddenOrHasHiddenAncestor == false && general?.isHiddenOrHasHiddenAncestor != false,
                  "the assistant's clarifying question shows its fixed answers below the reply, in place of the general choices"
                  + " (\(question?.stringValue ?? "no question"); \(means?.title ?? "no means"); \(unsure?.title ?? "no unsure"); general shown: \(general?.isHiddenOrHasHiddenAncestor == false))")
        try await wait("The card's selection was not read") { pane.guidanceFingerprint != nil }
        // A click that arrives before the page reports a new selection, which it does once the selection settles.
        let earlyToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:1,y:1,width:1,height:2})")
        let early = await pane.answerClarification("means", token: earlyToken)
        let earlyTranscript = await text(pane)
        try check(!early && pane.clarification != nil && !pane.isBusy && !earlyTranscript.contains("I want to compare means."),
                  "a click delivered before the page reports a new selection is refused against the live grid")
        // Five areas read "A1,B1,C1,D1,…", so a change to the fifth leaves the caption, and the page, quiet.
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,4].map(x => ({x, y:0, width:1, height:1}))})")
        try await wait("The five-area selection was not shown") { pane.selectionLabel.stringValue == "Selection: Parametric!A1,B1,C1,D1,…" }
        try await wait("The card's selection was not read again") { pane.guidanceFingerprint != nil }
        let captionToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,5].map(x => ({x, y:0, width:1, height:1}))})")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == captionToken, "the page reports nothing for a change its short caption does not show")
        let hidden = await pane.answerClarification("means", token: captionToken)
        try check(!hidden && pane.clarification != nil && !pane.isBusy, "a click after a change the caption does not show is refused against the live grid")
        // Sparse whole rows: 2, 3, 6 and 2, 4, 6 share the caption "2:6 (some rows)" but not the fingerprint.
        try await grid(first, "statsDirectGrid.selectRows([[1,3],[5,6]])")
        try await wait("The sparse rows were not shown") { pane.selectionLabel.stringValue == "Selection: Parametric!2:6 (some rows)" }
        try await wait("The card's selection was not read for the sparse rows") { pane.guidanceFingerprint != nil }
        let rowsToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectRows([[1,2],[3,4],[5,6]])")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == rowsToken, "the page reports nothing when sparse rows change under the same caption")
        let sparse = await pane.answerClarification("means", token: rowsToken)
        try check(!sparse && pane.clarification != nil, "a click after sparse rows changed under the same caption is refused against the live grid")
        // The header-row setting changes what a read sends without advancing any revision. The page reports it, as a
        // distribution card must be read again, and the live grid would refuse the click anyway.
        try await wait("The card's selection was not read after the sparse-row refusal") { pane.guidanceFingerprint != nil }
        let headerToken = pane.guidanceToken
        try await grid(first, "document.querySelector('.worksheet-options input[type=checkbox]').click()")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken != headerToken, "the page reports a change of the header-row setting, which draws the card again")
        let afterToggle = await pane.answerClarification("means", token: headerToken)
        try check(!afterToggle && pane.clarification != nil, "a click after the header-row setting changed is refused against the live grid")
        try await grid(first, "document.querySelector('.worksheet-options input[type=checkbox]').click()")
        let headerRestored = try await first.web.evaluateJavaScript("document.querySelector('.worksheet-options input[type=checkbox]').checked") as? Bool
        try check(headerRestored == true, "the header-row setting is back on for the reads that follow")
        let staleToken = pane.guidanceToken
        try await grid(first, "statsDirectGrid.selectCells({x:0,y:1,width:1,height:3})")
        try await wait("A selection change did not retire the card's token") { pane.guidanceToken != staleToken }
        let afterSelection = await pane.answerClarification("means", token: staleToken)
        try check(!afterSelection && pane.clarification != nil && !pane.isBusy,
                  "a late click on the card drawn before the selection changed is refused")
        let editToken = pane.guidanceToken, beforeEdit = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:2,row:4,text:'5'})")
        try await wait("An edit did not retire the card's token") { first.gridVersion > beforeEdit && pane.guidanceToken != editToken }
        let afterEdit = await pane.answerClarification("means", token: editToken)
        try check(!afterEdit && pane.clarification != nil, "a late click on the card drawn before an edit is refused")
        try await wait("The card's selection was not read after the edit") { pane.guidanceFingerprint != nil }
        // Keyboard focus on an answer stays on it when the card is drawn again. Buttons take focus only with Full
        // Keyboard Access, so without it the check is reported and skipped.
        let focusTarget: NSButton? = control("worksheet-ai-choice-ordered", in: pane.view)
        if let focusTarget, viewer.window.makeFirstResponder(focusTarget), viewer.window.firstResponder === focusTarget {
            let focusToken = pane.guidanceToken
            try await grid(first, "statsDirectGrid.selectCells({x:2,y:2,width:1,height:1})")
            try await wait("A selection change did not draw the card again") { pane.guidanceToken != focusToken }
            let responder = viewer.window.firstResponder as? WorksheetAIChoiceButton
            try check(responder?.choice == "ordered" && responder?.token == pane.guidanceToken && responder !== focusTarget,
                      "keyboard focus stays on the same answer when the card is drawn again")
            try await wait("The card's selection was not read after the redraw") { pane.guidanceFingerprint != nil }
        } else {
            print("INFO: answer buttons do not take keyboard focus here (Full Keyboard Access is off); focus across a redraw not exercised")
        }
        let current: NSButton? = control("worksheet-ai-choice-means", in: pane.view)
        current?.performClick(nil)
        try await wait("The chosen answer was not sent") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Means noted.")
        }
        try check((await text(pane)).contains("I want to compare means.") && pane.clarification == nil,
                  "choosing an answer sends its sentence with the conversation and retires the card")
    }

    func stoppedAndRefusedReads(_ first: Document) async throws {
        pane.input.string = "READ_STOP_A"
        pane.send()
        try await wait("The fixture did not read before stopping") { exists("read-served") }
        pane.stop()
        try check(!pane.isBusy || pane.replyActivity.stringValue == "Stopping…", "Stop shows that the reply is stopping")
        try await wait("Stop did not end the reply") { !pane.isBusy }
        try check(pane.replyActivity.isHidden, "Reply in progress… goes when the reply is stopped")
        let readLine = "Fictional.xlsx · Parametric · A1 (headings), A2 (part of the worksheet’s used range)"
        let stoppedLines = await lastReceipt().lines
        try check((await text(pane)).contains("[Reply stopped before any text.]") && stoppedLines == [readLine],
                  "a reply stopped after a read but before any text keeps its Data used receipt: \(stoppedLines)")
        try check(pane.input.string == "READ_STOP_A", "after Stop the question waits in the composer, as on Windows")

        // Stopped after a sent read and some streamed text: the partial text keeps the receipt.
        pane.input.string = "READ_TEXT_STOP_A"
        pane.send()
        try await wait("The fixture did not stream after its read") {
            guard exists("text-streamed") else { return false }
            return (await text(pane)).contains("Partial text after a read.")
        }
        pane.stop()
        try await wait("Stop did not end the streamed reply") { !pane.isBusy }
        let streamedLines = await lastReceipt().lines
        try check((await text(pane)).contains("[Reply stopped before completion.]") && streamedLines == [readLine],
                  "a reply stopped after a read and some text keeps its partial text and its receipt: \(streamedLines)")

        pane.input.string = "READ_FAIL_A"
        pane.send()
        try await wait("The failed reply did not end") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("[No reply was received.]")
        }
        let failedLines = await lastReceipt().lines
        try check(failedLines == [readLine] && pane.input.string == "READ_FAIL_A",
                  "a reply that fails after a read keeps its receipt and returns the question to the composer: \(failedLines)")
        pane.input.string = ""

        // Codex's boundary: two cells within the grid's character limit whose result exceeds the tutor's byte limit.
        let beforeBig = first.gridVersion
        _ = try await first.web.callAsyncJavaScript("""
            const cell = '\\\\'.repeat(20000);
            statsDirectGrid.setCellText({col:3,row:1,text:cell});
            statsDirectGrid.setCellText({col:3,row:2,text:cell});
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        try await wait("The large cells did not settle") { first.gridVersion >= beforeBig + 2 }
        pane.input.string = "READ_BIG_A"
        pane.send()
        try await wait("The refused read did not end its reply") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Big read refused.")
        }
        let big = await lastReceipt()
        try check(big.lines.isEmpty && big.none, "a read the tutor refuses as too large never appears in Data used: \(big.lines)")

        // A read that was sent, then one refused as too large, in one reply: only the first counts, in Data used and in
        // the R data that Open in R gives the reply's code.
        pane.input.string = "READ_MIX_A"
        pane.send()
        try await wait("The mixed reply did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Mixed reads.")
        }
        let mixed = await lastReceipt()
        try check(mixed.lines == [readLine], "after a sent read and a refused one, Data used lists only the sent read: \(mixed.lines)")
        _ = try await pane.transcript.web.evaluateJavaScript("""
            (() => { const rows = document.querySelectorAll('article.assistant'), last = rows[rows.length - 1];
              last.querySelector('details[data-r-block]').open = true; last.querySelector('[data-code=r]').click(); return true; })()
            """)
        try await wait("Open in R did not open the mixed reply's code") { viewer.active?.rConsolePane != nil && viewer.active !== first }
        let mixedReview = viewer.active!
        let mixedSource = mixedReview.rConsolePane?.sourceText ?? ""
        try check(mixedSource.contains("142741") && !mixedSource.contains(String(repeating: "\\", count: 100)),
                  "Open in R carries the sent read's values and none of the refused read's")
        viewer.remove(mixedReview)
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A after Open in R") { pane.workbookID == first.id }
    }

    func headingsAndHeldReads(_ first: Document) async throws {
        let readLine = "Fictional.xlsx · Parametric · A1 (headings), A2 (part of the worksheet’s used range)"
        // A real heading that reads like the stand-in still counts (Codex's recheck); a blank one does not (the node
        // and receipt-rule checks).
        let beforeHeadings = first.gridVersion
        try await grid(first, "statsDirectGrid.setCellText({col:2,row:0,text:'Column C'})")
        try await wait("The heading edit did not settle") { first.gridVersion > beforeHeadings }
        pane.input.string = "READ_PLACEHOLDER_A"
        pane.send()
        try await wait("The heading read did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Placeholder heading read.")
        }
        let placeholder = await lastReceipt().lines
        try check(placeholder == ["Fictional.xlsx · Parametric · C1 (headings), C2 (part of the worksheet’s used range)"],
                  "a heading that reads \"Column C\" is listed as sent: \(placeholder)")

        // The same boundary without a provider: a read waits until the tutor reports its result sent, as it does not
        // when Stop comes first or the result is refused.
        let direct = ScriptAIContext(viewer: viewer, script: nil, workbook: first, usesSessionConsent: false, worksheetAssist: true) { true }
        let held = try await direct.call("statsdirect_read_data", ["documentId": first.id, "columns": [0], "firstRow": 2, "lastRow": 2])
        try check(direct.reads.isEmpty && direct.rData.isEmpty,
                  "a read made but not reported sent adds neither a Data used line nor R data")
        direct.delivered("statsdirect_read_data", held)
        direct.delivered("statsdirect_read_data", held)
        direct.delivered("statsdirect_workspace", held)
        let heldID = held["datasetId"] as? String ?? "missing"
        try check(WorksheetAIRead.ranges(columns: [3, 0, 1], headingColumns: [0, 3], firstRow: 2, lastRow: 5)
                  == ["A1 (headings)", "D1 (headings)", "A2:B5", "D2:D5"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": true,
                                              "columns": [["index": 0, "title": "Before"], ["index": 2, "title": "Column C"]]],
                                             used: nil, headings: [0], workbook: "W.xlsx")?.ranges == ["A1 (headings)", "A2:A3", "C2:C3"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": true,
                                              "columns": [["index": 0, "title": "Before"], ["index": 2, "title": "Column C"]]],
                                             used: nil, headings: [0, 2], workbook: "W.xlsx")?.ranges == ["A1 (headings)", "C1 (headings)", "A2:A3", "C2:C3"]
                  && ScriptAIContext.receipt(["sheet": "S", "firstRow": 2, "lastRow": 3, "headerRow": false,
                                              "columns": [["index": 0, "title": "Column A"]]],
                                             used: nil, headings: [0], workbook: "W.xlsx")?.ranges == ["A2:A3"],
                  "receipts group adjacent columns and list the headings whose cells hold text, whatever their text")
        try check(direct.reads.map(\.line) == [readLine] && direct.rData.components(separatedBy: heldID).count == 2 && direct.rData.contains("142741"),
                  "once reported sent, the read joins Data used and the R data, once")

        let rowsBefore = await assistantRows()
        pane.input.string = "HOLD_A"
        pane.send()
        try await wait("The held question did not reach the fixture") {
            (try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8))?.contains("HOLD_A") == true
        }
        pane.stop()
        try await wait("Stop did not end the held reply") { !pane.isBusy }
        try check(await assistantRows() == rowsBefore && pane.replyActivity.isHidden, "Stop before any read or text adds no reply and no receipt")
        let log = (try? String(contentsOf: storage.appendingPathComponent("requests.jsonl"), encoding: .utf8)) ?? ""
        try check(!log.isEmpty && !log.contains("Data used") && !log.contains("(headings)") && !log.contains("part of the worksheet"),
                  "no receipt reaches the provider in any request, including the shared follow-ups after it")
    }

    func emptyWorkbooks(_ first: Document) async throws {
        viewer.newWorksheet()
        guard let blank = viewer.documents.last(where: { $0.kind == "grid" && $0.openedFileURL == nil }) else {
            throw ChatGPTTutor.Failure(message: "The new worksheet was not created")
        }
        try await wait("The empty workbook's choices did not appear") {
            let example: NSButton? = control("worksheet-ai-open-example", in: pane.view)
            return pane.workbookID == blank.id && blank.pendingWorkbook == nil && example?.isHiddenOrHasHiddenAncestor == false
        }
        let workbookHelp: NSButton? = control("worksheet-ai-workbook-help", in: pane.view)
        let browse: NSButton? = control("worksheet-ai-choose-method", in: pane.view)
        try check((await text(pane)).contains("This workbook is empty.") && workbookHelp?.isHiddenOrHasHiddenAncestor == false
                  && browse?.isHiddenOrHasHiddenAncestor != false && !shown("worksheet-ai-help-choose"),
                  "an empty workbook offers the example workbook and the workbook Help instead of method guidance")
        try checkAccessibility("an empty workbook's choices", group: "Getting started with a workbook")
        try await grid(blank, "statsDirectGrid.setCellText({col:0,row:0,text:'7'})")
        try await wait("Data did not bring back the general choices") {
            let guide: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
            return guide?.isHiddenOrHasHiddenAncestor == false
        }
        let titled: NSButton? = control("worksheet-ai-help-choose", in: pane.view), chooser: NSButton? = control("worksheet-ai-choose-method", in: pane.view)
        try check(!(await text(pane)).contains("This workbook is empty.") && titled?.title == "Help me choose a method"
                  && chooser?.title == "Choose a method" && chooser?.isHiddenOrHasHiddenAncestor == false,
                  "a workbook with data offers Help me choose a method and Choose a method")
        let guide: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
        guide?.performClick(nil)
        try await wait("Help me choose a method did not send its question") {
            guard !pane.isBusy else { return false }
            let shown = await text(pane)
            return shown.contains("Help me choose a statistical method.") && shown.contains("General guidance without workbook data.")
        }
        try check((await text(pane)).contains("General guidance · No worksheet cells read for this reply"),
                  "Help me choose a method asks in question-only mode, which sends nothing about the workbook and reads no cells")

        viewer.newWorksheet()
        guard let blank2 = viewer.documents.last(where: { $0.kind == "grid" && $0.openedFileURL == nil && $0 !== blank }) else {
            throw ChatGPTTutor.Failure(message: "The second new worksheet was not created")
        }
        try await wait("The second empty workbook's choices did not appear") {
            let example: NSButton? = control("worksheet-ai-open-example", in: pane.view)
            return pane.workbookID == blank2.id && blank2.pendingWorkbook == nil && example?.isHiddenOrHasHiddenAncestor == false
        }
        (control("worksheet-ai-open-example", in: pane.view) as NSButton?)?.performClick(nil)
        try await wait("Open example workbook did not open test.xlsx in AI Assist") {
            guard let example = viewer.documents.last(where: { $0.kind == "grid" && $0.workbookName == "test.xlsx" }),
                  example.pendingWorkbook == nil, pane.workbookID == example.id else { return false }
            let choices: NSButton? = control("worksheet-ai-help-choose", in: pane.view)
            return choices?.isHiddenOrHasHiddenAncestor == false
        }
        try check(true, "Open example workbook opens test.xlsx, which AI Assist follows with its general choices")
        viewer.tabs.selectTabViewItem(blank2.item)
        try await wait("AI Assist did not follow the empty workbook again") {
            let help: NSButton? = control("worksheet-ai-workbook-help", in: pane.view)
            return pane.workbookID == blank2.id && help?.isHiddenOrHasHiddenAncestor == false
        }
        (control("worksheet-ai-workbook-help", in: pane.view) as NSButton?)?.performClick(nil)
        try await wait("Workbook help did not open the workbook topic") {
            viewer.helpPane.visible && viewer.helpPane.web.url?.path.hasSuffix("basics/worksheet.htm") == true
        }
        try check(!pane.visible, "Workbook help opens the workbook topic in the dock in place of AI Assist")
        viewer.tabs.selectTabViewItem(first.item)
        try await toolbar(first, "worksheetAI")
        try await wait("AI Assist did not reopen on workbook A") { pane.visible && pane.workbookID == first.id }
    }

    func cardWorkbook() async throws -> Document {
        // Windows 5.3.22's distribution decision cards (Windows pull requests 40 to 42): the study-design question and the
        // paired and independent interval cards, which the engine checks on this Mac. The texts are the Windows cards' and
        // tests' (W:tests/Learning/WorksheetAnalysis.cs); the engine's own test holds their numbers to R 4.6.1.
        var cells: [[String: Any]] = []
        func column(_ col: Int, _ heading: String, _ values: [String]) {
            cells.append(["col": col, "row": 0, "text": heading, "kind": "text"])
            for (row, text) in values.enumerated() {
                cells.append(["col": col, "row": row + 1, "text": text, "kind": Double(text) == nil ? "text" : "number"])
            }
        }
        func texts(_ values: [Int]) -> [String] { values.map(String.init) }
        let spread = Array(-5...5) + [1000]                        // Windows' D1:E13: one far-out difference in 12
        let symmetric = Array(repeating: -1, count: 25) + Array(repeating: 0, count: 51) + Array(repeating: 1, count: 25)
        func rate(_ middle: Int) -> [Int] {                        // one far-out difference in 1,000 or 1,001 pairs
            zip(-3...3, [16, 94, 234, middle, 234, 94, 16]).flatMap { Array(repeating: $0.0, count: $0.1) } + [8]
        }
        column(0, "Other Before", texts(spread.map { 20 + $0 })); column(1, "Other After", texts(spread.map { _ in 20 }))
        column(6, "Boundary before", texts((1...101).map { $0 + $0 % 5 }) + ["102"]); column(7, "Boundary after", texts(Array(1...101)))
        column(9, "Heavy before", texts(symmetric + [-4, 4])); column(10, "Heavy after", texts(Array(repeating: 0, count: 103)))
        column(12, "Outlier before", texts(symmetric + [30])); column(13, "Outlier after", texts(Array(repeating: 0, count: 102)))
        column(18, "Rate before", texts(rate(311))); column(19, "Rate after", texts(Array(repeating: 0, count: 1000)))
        column(21, "Rate before", texts(rate(312))); column(22, "Rate after", texts(Array(repeating: 0, count: 1001)))
        column(24, "Group X", texts(Array(2...8))); column(25, "Group Y", texts([1, 3, 5, 7]))
        column(27, "Large X", texts(Array(2...102))); column(28, "Large Y", texts(Array(stride(from: 1, through: 203, by: 2))))
        column(30, "Uneven X", texts(Array(2...102))); column(31, "Uneven Y", texts([1, 3, 5, 7]))
        column(36, "Big before", ["1e+308"]); column(37, "Big after", ["-1e+308"])
        column(39, "Text before", ["1", "2", "3", "abc", "5"]); column(40, "Text after", ["1", "1", "1", "1", "1"])
        for (row, pair) in zip([11, 14, 17, 22, 23], [10, 11, 15, 20, 19]).enumerated() {   // numbers in row 1 too
            cells += [["col": 42, "row": row, "text": String(pair.0), "kind": "number"], ["col": 43, "row": row, "text": String(pair.1), "kind": "number"]]
        }
        let cards = viewer.newDocument(kind: "grid", title: "Card checks", url: viewer.root.appendingPathComponent("Grid/index.html"))
        cards.workbookName = "Card checks.xlsx"
        cards.pendingWorkbook = ["name": "Card checks", "formulaCount": 0,
                                 "sheets": [["name": "Cards", "rows": 1100, "columns": 44, "headerRow": true, "cells": cells]]]
        try await wait("AI Assist did not follow the card workbook") {
            pane.workbookID == cards.id && cards.pendingWorkbook == nil && cards.aiWorksheet?.hasData == true
        }
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        return cards
    }

    func designAndStaleClicks(_ cards: Document) async throws {
        // The tool without a design: Windows' study-design question, then Same people or units checks the selection at once.
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        pane.input.string = "DESIGN_A"
        pane.send()
        let design = try await waitCard("choose", [chooseLine], "The study-design question did not appear")
        try check(design.choices == ["paired", "independent"] && design.titles == ["Same people or units", "Separate groups"]
                  && pane.clarification == nil && pane.guidance.accessibilityLabel() == "Study design" && !shown("worksheet-ai-help-choose"),
                  "the tool without a design shows Windows' study-design question in place of the general choices")
        let designReceipt = await lastReceipt()
        try check(designReceipt.none && designReceipt.lines.isEmpty, "offering a card reads no cells, and the reply says so")
        let quiet = dataTraffic()
        // Pressed with the keyboard, as each choice of this part is: the focus moves on to whatever replaces it.
        let designFocus: Bool = try pressWithFocus("paired")
        let four = try await waitCard("paired-interval", ["Local check found 4 complete pairs. Shapiro–Wilk W = 0.9929, P = 0.9719.", "Suggested branch"],
                                      "Same people or units did not check Y1:Z8 as pairs")
        try check(four.titles == ["Large sample (more than 100 complete pairs)", "Suggested · Small or medium · Approximately normal differences",
                                  "Non-normal differences", "Change design"] && four.token != design.token
                  && pane.guidance.accessibilityLabel() == "Paired interval measurements" && dataTraffic() == quiet,
                  "Same people or units checks the selection on this Mac at once, suggests a branch and sends nothing")
        try checkFocus(designFocus, focusOnFirstChoice(), "the keyboard focus on Same people or units moves to the paired card's first choice once its reading is drawn")

        // Stale clicks (Windows' WorksheetAnalysis.cs:432-448): a selection change before the page reports it, then an edit.
        try await grid(cards, "statsDirectGrid.selectCells({x:0,y:0,width:2,height:13})")
        let earlyBranch = await pane.answerCard("normal", token: four.token)
        try check(!earlyBranch && pane.offer == nil, "a branch clicked before the page reports a new selection is refused against the live grid")
        // The page's report comes once the selection settles, and reads the card again too; an edit before it would put
        // the report off until after the edit.
        try await wait("The page did not report A1:B13") { pane.selectionLabel.stringValue == "Selection: Cards!A1:B13" }
        let twelve = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.3371, P = 1.396E-06.",
            "Review the differences\nThe box-plot check flagged an unusually distant difference. Review whether it reflects a data error or strongly affects the mean before choosing."],
            "A1:B13 was not checked")
        try check(twelve.token != four.token && !twelve.choices.contains("check") && !twelve.titles.contains { $0.hasPrefix("Suggested · ") },
                  "the card is read again for the new selection, so a stale click cannot skip its box-plot warning")
        let beforeCardEdit = cards.gridVersion
        try await grid(cards, "statsDirectGrid.setCellText({col:0,row:12,text:'26'})")
        try await wait("The edit did not retire the card's token") { cards.gridVersion > beforeCardEdit && pane.guidanceToken != twelve.token }
        let edited = await pane.answerCard("normal", token: twelve.token)
        let six = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757.",
                                                         "Suggested · Small or medium · Approximately normal differences"], "The edited pairs were not checked again")
        try check(!edited && six.token != twelve.token, "an edit checks the selection again, and a click on the card drawn before it is refused")

        // A branch offers its method with the card's check and Windows' advice; Change sample choice comes back to the card.
        let branchFocus: Bool = try pressWithFocus("normal")
        let pairedOffer = try await offered("Paired Student t test")
        let sample: NSButton? = control("worksheet-ai-change-sample", in: pane.view)
        let designButton: NSButton? = control("worksheet-ai-change-design", in: pane.view)
        try check(pairedOffer.contains("Menu: Analysis › Parametric › Paired t") && pairedOffer.contains("Selection: A1:B13")
                  && pairedOffer.contains("Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757.\nThe paired t test addresses the mean difference. This branch assumes approximately normal differences.")
                  && card() == nil && sample?.title == "Change sample choice" && sample?.isHiddenOrHasHiddenAncestor == false
                  && designButton?.isHiddenOrHasHiddenAncestor == true,
                  "Small or medium offers the paired t test with the card's check and Windows' advice, in place of the card, with Change sample choice and not "
                  + "Change design (Learning/conversation.mjs:221-222)")
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        try checkFocus(branchFocus, proceed != nil && viewer.window.firstResponder === proceed, "the keyboard focus on a branch moves to Continue, the first button of its offer")
        let sampleFocus: Bool = sample.map { viewer.window.makeFirstResponder($0) && viewer.window.firstResponder === $0 } ?? false
        sample?.performClick(nil)
        let returned = try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."],
                                          "Change sample choice did not return to the card")
        try check(pane.offer == nil && returned.token != six.token, "Change sample choice returns to the card as it was, with a new token")
        try checkFocus(sampleFocus, focusOnFirstChoice(), "the keyboard focus on Change sample choice moves to the first choice of the card it returns to")
    }

    func largePairsAndNarrowDock(_ cards: Document) async throws {
        // More than 100 pairs: the shape checks instead of Shapiro–Wilk; the size conflict; Wilcoxon still offered (PR 41).
        try await select(cards, "selectCells({x:6,y:0,width:2,height:103})", "Selection: Cards!G1:H103")
        let large = try await waitCard("paired-interval", ["Local check found 101 complete pairs\nShape check · 0 beyond the 3× IQR fences\nSkewness 0.0175 · Excess kurtosis -1.3",
            "Suggested branch\nThere are more than 100 complete pairs and the shape checks found no substantial departure. A paired t test answers the question about the mean difference."],
            "G1:H103 was not checked as 101 pairs")
        try check(large.titles == ["Suggested · Large sample (more than 100 complete pairs)", "Small or medium · Approximately normal differences",
                                   "Non-normal differences", "Change design"] && !large.text.contains("W ="),
                  "above 100 pairs the card gives Windows' shape checks without Shapiro–Wilk and suggests the large-sample branch")
        try click("normal")
        try await feedback("The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks.",
                           "Small or medium above 100 pairs gave no feedback")
        try check(pane.offer == nil && card()?.token == large.token, "a branch of the other size gets Windows' feedback on the card, which keeps its token")
        try await keptThroughToolbar(cards, "the paired card for G1:H103 and its conflict feedback")
        try click("non-normal")
        let wilcoxon = try await offered("Wilcoxon signed ranks test")
        try check(wilcoxon.contains("Menu: Analysis › Nonparametric › Wilcoxon Signed Ranks")
                  && wilcoxon.contains("The signed-rank test concerns a shift in location and assumes roughly symmetric differences. If the aim is specifically to estimate or test the mean difference, consider whether this answers your question."),
                  "Wilcoxon signed ranks stays available above 100 pairs, with Windows' advice")
        _ = await pane.changeSample()
        try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "Change sample choice did not return to the 101 pairs")
        try check(label("worksheet-ai-distribution-feedback").isEmpty, "the card comes back without its earlier feedback")
        try click("large")
        let largeOffer = try await offered("Paired Student t test")
        try check(largeOffer.contains("The large-sample branch recommends the paired t test for the mean difference."),
                  "the large-sample branch offers the paired t test with Windows' advice")
        _ = await pane.changeSample()
        try await select(cards, "selectCells({x:6,y:0,width:2,height:101})", "Selection: Cards!G1:H101")
        try await waitCard("paired-interval", ["Local check found 100 complete pairs. Shapiro–Wilk W = 0.8876, P = 3.853E-07.",
            "Suggested branch\nShapiro–Wilk found evidence of non-normal differences. Consider Wilcoxon signed-rank if the differences look roughly symmetric and a shift in location answers your question.",
            "Suggested · Non-normal differences"], "G1:H101 was not checked as 100 pairs")
        try check(true, "at exactly 100 pairs Shapiro–Wilk still decides, and suggests the non-normal branch")

        // In the narrowest dock the split allows (its delegate, HelpPane, stops the divider 340 points from the right edge),
        // the card's widest title is wider than the pane's content: it wraps within the pane instead of widening it.
        let split = viewer.workspaceSplit, dock = pane.view.frame.width
        split.setPosition(split.bounds.width - 300 - split.dividerThickness, ofDividerAt: 0)
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        let cardButtons = views(WorksheetAIChoiceButton.self, in: pane.view)
        let widest = cardButtons.map { $0.cell?.cellSize.width ?? 0 }.max() ?? 0
        let fitted = cardButtons.allSatisfy { button in
            let frame = pane.view.convert(button.bounds, from: button)
            let title = button.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: button.frame.width, height: 10_000)).height ?? .infinity
            return frame.minX >= -0.5 && frame.maxX <= pane.view.bounds.width + 0.5 && button.frame.height >= title - 0.5
        }
        let paragraphs = views(NSTextField.self, in: control("worksheet-ai-distribution", in: pane.view) ?? NSView()).allSatisfy { field in
            (field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: 10_000)).height ?? .infinity) <= field.frame.height + 0.5
        }
        let measured = cardButtons.map { button in
            "\(button.choice) \(pane.view.convert(button.bounds, from: button)) title \(button.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: button.frame.width, height: 10_000)) ?? .zero)"
        }
        let narrow = cardButtons.count == 4 && pane.view.frame.width < dock && pane.view.frame.width - 20 < widest && fitted && paragraphs
        try check(narrow, "in the narrowest dock the card's titles and text wrap within the pane instead of widening it"
                  + (narrow ? "" : " (pane \(pane.view.frame.width), widest title \(widest), fitted \(fitted), paragraphs \(paragraphs): \(measured))"))
        split.setPosition(split.bounds.width - dock - split.dividerThickness, ofDividerAt: 0)
        viewer.window.contentView?.layoutSubtreeIfNeeded()
    }

    func shapeChecks(_ cards: Document) async throws {
        // Heavy tails, and a far-out difference with skew: no branch suggested, and Wilcoxon still offered.
        try await select(cards, "selectCells({x:9,y:0,width:2,height:104})", "Selection: Cards!J1:K104")
        let heavy = try await waitCard("paired-interval", ["Local check found 103 complete pairs\nShape check · 0 beyond the 3× IQR fences\nSkewness 0 · Excess kurtosis 5.61",
            "Review the differences\nThe shape checks flagged heavy tails. Consider Wilcoxon signed ranks for a shift in location if the differences look roughly symmetric. A paired t test still answers the question about the mean difference. Review any influential differences before choosing."],
            "J1:K104 was not checked")
        try check(!heavy.titles.contains { $0.hasPrefix("Suggested · ") }, "heavy tails above 100 pairs suggest no branch")
        // Keyboard focus on a choice stays on it when the card is read and drawn again. Buttons take focus only with
        // Full Keyboard Access, so without it the check is reported and skipped.
        let cardFocus: WorksheetAIChoiceButton? = control("worksheet-ai-card-non-normal", in: pane.view)
        let focusable = cardFocus.map { viewer.window.makeFirstResponder($0) && viewer.window.firstResponder === $0 } ?? false
        try await select(cards, "selectCells({x:12,y:0,width:2,height:103})", "Selection: Cards!M1:N103")
        try await waitCard("paired-interval", ["Local check found 102 complete pairs\nShape check · 1 beyond the 3× IQR fences\nSkewness 9.15 · Excess kurtosis 86.7",
            "The shape checks flagged far-out differences, pronounced skew, heavy tails. Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful. A paired t test still answers the question about the mean difference. Review any influential differences before choosing."],
            "M1:N103 was not checked")
        if focusable {
            let responder = viewer.window.firstResponder as? WorksheetAIChoiceButton
            try check(responder?.choice == "non-normal" && responder?.token == pane.guidanceToken && responder !== cardFocus,
                      "keyboard focus stays on the same choice when the card is read and drawn again")
        } else {
            print("INFO: card buttons do not take keyboard focus here (Full Keyboard Access is off); focus across a redraw not exercised")
        }
        try click("non-normal")
        _ = try await offered("Wilcoxon signed ranks test")
        _ = await pane.changeSample()
        try check(true, "a far-out difference with skew and heavy tails still leaves Wilcoxon signed ranks to choose")
        try await select(cards, "selectCells({x:18,y:0,width:2,height:1001})", "Selection: Cards!S1:T1001")
        try await waitCard("paired-interval", ["Local check found 1000 complete pairs\nShape check · 1 beyond the 3× IQR fences\nSkewness 0.241 · Excess kurtosis 1.11",
                                               "The shape checks flagged far-out differences. Consider Wilcoxon signed ranks"], "S1:T1001 was not checked")
        try await select(cards, "selectCells({x:21,y:0,width:2,height:1002})", "Selection: Cards!V1:W1002")
        try await waitCard("paired-interval", ["Local check found 1001 complete pairs\nShape check · 1 beyond the 3× IQR fences",
                                               "Suggested · Large sample (more than 100 complete pairs)"], "V1:W1002 was not checked")
        try check(true, "one far-out difference flags 1,000 pairs but not 1,001 (Windows' 0.1% rule)")
    }

    func headerRowSetting(_ cards: Document) async throws {
        // "First row has column names" decides whether row 1 is checked, as it does for the analysis; a heading read as
        // data is refused as the analysis would refuse it, naming the cell and the setting.
        try await select(cards, "selectCells({x:42,y:0,width:2,height:5})", "Selection: Cards!AQ1:AR5")
        let headed = try await waitCard("paired-interval", ["Local check found 4 complete pairs. Shapiro–Wilk W = 0.8634, P = 0.2725."], "AQ1:AR5 was not checked without row 1")
        try await grid(cards, checkbox)
        let toggled = await pane.answerCard("normal", token: headed.token)
        try await waitCard("paired-interval", ["Local check found 5 complete pairs. Shapiro–Wilk W = 0.9609, P = 0.814."], "Row 1 was not checked with the setting off")
        try check(!toggled, "turning off First row has column names checks row 1 too, and a click on the card drawn before is refused")
        try await select(cards, "selectCells({x:0,y:0,width:2,height:13})", "Selection: Cards!A1:B13")
        try await waitCard("paired-interval", ["How many complete pairs are there?\nHow are the within-pair differences distributed?\nLook at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive.",
                                               "Check selected pairs"], "A heading read as data did not leave the card unread")
        try click("check")
        try await feedback("Cell A1: ‘Other Before’ is not numeric. Correct it or use * for a missing value. If row 1 holds column names, tick “First row has column names”.",
                           "Check did not name the heading cell")
        try check(card()?.choices.first == "check", "Check refuses a heading read as data, naming the cell and the setting, and stays offered")
        let beforeHeader = dataTraffic()
        try await grid(cards, checkbox)
        try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."], "Ticking the setting did not check the pairs")
        try check(label("worksheet-ai-distribution-feedback").isEmpty && dataTraffic() == beforeHeader,
                  "ticking the setting checks the pairs again on this Mac, without the feedback, and sends nothing")
    }

    func unreadableSelections(_ cards: Document) async throws {
        // Selections that cannot be read leave the card unread; Check gives Windows' text, which each new selection clears.
        for (script, caption) in [("selectCells({x:0,y:0,width:1,height:1})", "Current cell: Cards!A1"),
                                  ("selectCells({x:0,y:0,width:3,height:13})", "Selection: Cards!A1:C13"),
                                  ("selectCells({x:0,y:0,width:1,height:13,stack:[{x:1,y:0,width:1,height:13}]})", "Selection: Cards!A1:A13,B1:B13"),
                                  ("selectRows([[0,13]])", "Selection: Cards!1:13")] {
            try await select(cards, script, caption)
            try await waitCard("paired-interval", ["How many complete pairs are there?", "Check selected pairs"], caption + " did not leave the card unread",
                               absent: [unpaired])
            try click("check")
            try await feedback(unpaired, caption + " was not refused")
        }
        try check(true, "a single cell, three columns, two areas and whole rows are refused with Windows' text, which each new selection clears")
        try await select(cards, "selectCells({x:36,y:0,width:2,height:2})", "Selection: Cards!AK1:AL2")
        try await waitCard("paired-interval", ["How many complete pairs are there?"], "AK1:AL2 did not leave the card unread", absent: [unpaired])
        try click("check")
        try await feedback("A paired difference is too large to check. Rescale the measurements and try again.", "The overflow was not refused")
        try await select(cards, "selectCells({x:39,y:0,width:2,height:6})", "Selection: Cards!AN1:AO6")
        try await waitCard("paired-interval", ["How many complete pairs are there?"], "AN1:AO6 did not leave the card unread", absent: ["too large"])
        try click("check")
        try await feedback("Cell AN5: ‘abc’ is not numeric. Correct it or use * for a missing value.", "Text in a pair was not refused")
        try await keptThroughToolbar(cards, "the paired card for AN1:AO6 and its Check feedback")
        try check(true, "Check refuses a difference too large to check and text in a pair, with the cell named, as the analysis would")
        // Five areas read "A1,B1,C1,D1,…", so a change to the fifth leaves the caption, and the page, quiet.
        try await select(cards, "selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,4].map(x => ({x, y:0, width:1, height:1}))})", "Selection: Cards!A1,B1,C1,D1,…")
        let areas = try await waitCard("paired-interval", ["How many complete pairs are there?"], "Five areas did not leave the card unread", absent: ["Cell AN5"])
        try await grid(cards, "statsDirectGrid.selectCells({x:0,y:0,width:1,height:1,stack:[1,2,3,5].map(x => ({x, y:0, width:1, height:1}))})")
        try await Task.sleep(for: .milliseconds(400))
        try check(pane.guidanceToken == areas.token, "the page reports nothing for a change its short caption does not show")
        let unseen = await pane.answerCard("check", token: areas.token)
        try check(!unseen && pane.guidanceToken != areas.token, "a click after a change the caption does not show is refused against the live grid, and the card is read again")
    }

    func independentCards(_ cards: Document) async throws {
        // Change design, and the independent card: counts first, then Windows' confirmation of separate samples.
        try await waitCard("paired-interval", ["Change design"], "The card was not read again after the refused click")
        try click("back")
        let chosen = try await waitCard("choose", [chooseLine], "Change design did not return to the study-design question")
        try check(!chosen.text.contains("How many complete pairs"), "Change design returns to the study-design question without the evidence")
        try click("independent")
        try await waitCard("independent-interval", ["How many observations are there in each group?\nHow are the observations distributed within each group?", "Check two sample columns"],
                           "Separate groups did not give the unread independent card")
        try click("check")
        try await feedback("Select the two adjacent, visible sample columns in one worksheet range.", "The independent Check was not refused")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        let counts = try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:\nColumn 1: n = 7. Shapiro–Wilk W = 0.978, P = 0.9493.\nColumn 2: n = 4. Shapiro–Wilk W = 0.9929, P = 0.9719.\nHow are the observations distributed within each group?\nLook at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive."],
                                        "Y1:Z8 was not counted as two samples")
        try check(counts.choices == ["check", "large", "normal", "non-normal", "back"]
                  && counts.titles == ["Use these as separate samples", "Large samples (more than 100 in each group)", "Small or medium · Approximately normal within groups",
                                       "Non-normal distributions within groups", "Change design"]
                  && pane.guidance.accessibilityLabel() == "Independent interval measurements",
                  "the independent card counts each column and asks to use them as separate samples")
        try click("check")
        let separate = try await waitCard("independent-interval", ["Column 1: n = 7. Shapiro–Wilk W = 0.978, P = 0.9493."], "Use these as separate samples did not confirm them",
                                          absent: ["Selected columns, if they hold"])
        try check(!separate.choices.contains("check") && separate.token != counts.token, "Use these as separate samples confirms the counts, with a new token")
        try click("large")
        try await feedback("The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.",
                           "Large samples at 7 and 4 gave no feedback")
        try await keptThroughToolbar(cards, "the independent card for Y1:Z8, its confirmation of separate samples and its conflict feedback")
        try await refusedAgain("large", "The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.",
                               "Large samples is still refused for the 7 and 4 observations confirmed as separate samples, as on Windows")
        try click("non-normal")
        let mannWhitney = try await offered("Mann-Whitney U (two-sample Wilcoxon) test")
        try check(mannWhitney.contains("Menu: Analysis › Nonparametric › Mann-Whitney")
                  && mannWhitney.contains("Mann–Whitney compares relative ordering between groups. Use that question to decide whether it fits your goal."),
                  "the non-normal branch offers Mann–Whitney with Windows' advice")
        _ = await pane.changeSample()
        let kept = try await waitCard("independent-interval", ["Column 1: n = 7"], "Change sample choice did not return to the samples", absent: ["Selected columns, if they hold"])
        try check(!kept.choices.contains("check"), "Change sample choice keeps the confirmation of separate samples while the selection is unchanged")
        try await select(cards, "selectCells({x:0,y:0,width:1,height:1})", "Current cell: Cards!A1")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:", "Use these as separate samples"],
                           "A new selection did not ask again whether the columns are separate samples")
        try check(true, "a new selection asks again whether the columns hold separate samples")
        try await select(cards, "selectCells({x:27,y:0,width:2,height:103})", "Selection: Cards!AB1:AC103")
        pane.input.string = "INDEPENDENT_A"
        pane.send()
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 102", "Use these as separate samples"], "The tool did not stage the independent card for AB1:AC103")
        let independentReply = await text(pane)
        try check(independentReply.contains("Check the independent card below.") && pane.clarification == nil,
                  "the tool with design independent stages the independent card, which counts the selection when the reply completes")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 102"], "AB1:AC103 was not confirmed", absent: ["Selected columns, if they hold"])
        try click("normal")
        try await feedback("The local check found more than 100 observations in each sample. Review their distributions before choosing a method.",
                           "Small or medium at 101 and 102 gave no feedback")
        try click("large")
        let zTest = try await offered("Unpaired two-sample z(normal distribution) test")
        try check(zTest.contains("Menu: Analysis › Parametric › Unpaired z")
                  && zTest.contains("The Help routes large, well-behaved samples to the two-sample Z test for the difference in means."),
                  "more than 100 in each sample offers the z test with Windows' advice")
        _ = await pane.changeSample()
        try await select(cards, "selectCells({x:30,y:0,width:2,height:102})", "Selection: Cards!AE1:AF102")
        try await waitCard("independent-interval", ["Column 1: n = 101\nColumn 2: n = 4. Shapiro–Wilk W = 0.9929, P = 0.9719."], "AE1:AF102 was not counted")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 101"], "AE1:AF102 was not confirmed", absent: ["Selected columns, if they hold"])
        try click("large")
        try await feedback("The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.",
                           "Large samples at 101 and 4 gave no feedback")
        try check(true, "the large-sample branch needs more than 100 in each sample")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        try await waitCard("independent-interval", ["Use these as separate samples"], "Y1:Z8 was not counted again")
        try click("check")
        try await waitCard("independent-interval", ["Column 1: n = 7"], "Y1:Z8 was not confirmed again", absent: ["Selected columns, if they hold"])
        try click("normal")
        let unpairedT = try await offered("Unpaired Student t test")
        try check(unpairedT.contains("Menu: Analysis › Parametric › Unpaired t")
                  && unpairedT.contains("The unpaired t test compares means. Consider the spread in each group before using an equal-variance result."),
                  "Small or medium offers the unpaired t test with Windows' advice")
        // Pressed with the keyboard, Cancel passes the focus to the first of the general choices, which replace the offer and its card.
        let cancelFocus: Bool = button("Cancel").map(pressWithFocus) ?? false
        try await wait("Cancel did not return to the general choices") { pane.offer == nil && shown("worksheet-ai-help-choose") }
        try check(pane.distribution == nil && card() == nil, "Cancel dismisses the offer and the card it came from")
        try checkFocus(cancelFocus, viewer.window.firstResponder === pane.helpChoose,
                       "the keyboard focus on Cancel moves to Help me choose a method, the first of the general choices")
    }

    func stagedCards(_ cards: Document) async throws {
        // A design, with Windows' validation and one staged card a reply; then a method that is not available.
        try await select(cards, "selectCells({x:0,y:0,width:2,height:13})", "Selection: Cards!A1:B13")
        pane.input.string = "PAIRED_A"
        pane.send()
        try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."], "The paired card was not staged and checked")
        let pairedReply = await text(pane)
        try check(pane.clarification == nil && pairedReply.contains("Check the paired card below."),
                  "the tool refuses a bad design, an extra argument and a second card, and stages one paired card")
        guard let unavailable = viewer.worksheetCommands.firstIndex(where: { $0.id == "Wilcoxon" }) else {
            throw ChatGPTTutor.Failure(message: "Wilcoxon is not in the Analyse catalogue")
        }
        viewer.worksheetCommands[unavailable].disabled = true
        let unavailableFocus: Bool = try pressWithFocus("non-normal")
        try await wait("An unavailable method did not clear the card") {
            pane.distribution == nil && label("worksheet-ai-notice") == "That method is unavailable. Choose another method in Analyse."
        }
        viewer.worksheetCommands[unavailable].disabled = false
        try check(pane.offer == nil, "a branch whose method is unavailable clears the card with Windows' text")
        try checkFocus(unavailableFocus, viewer.window.firstResponder === pane.helpChoose,
                       "the keyboard focus on a branch whose method is unavailable moves to Help me choose a method, the first of the general choices")
        pane.input.string = "CLARIFY_THEN_CARD_A"
        pane.send()
        try await wait("The clarifying question did not appear") { !pane.isBusy && pane.clarification != nil }
        try check(pane.distribution == nil && card() == nil, "after a clarifying question, the reply's card tool is refused: one card a reply")
    }

    func cardsInReplies(_ cards: Document) async throws {
        // Hidden while a reply runs; read when it completes, not when it was staged; dropped by Stop and by a new send.
        pane.input.string = "HOLD_CARD_A"
        pane.send()
        try await wait("The card reply did not stage its card") {
            guard exists("card-staged") else { return false }
            return (await text(pane)).contains("Card staged; reply still running.")
        }
        try check(pane.isBusy && card() == nil && !shown("worksheet-ai-help-choose"), "no card or choices show while the reply runs")
        try await grid(cards, "statsDirectGrid.selectCells({x:6,y:0,width:2,height:103})")
        try await wait("The selection label did not follow during the reply") { pane.selectionLabel.stringValue == "Selection: Cards!G1:H103" }
        try Data().write(to: storage.appendingPathComponent("card-release"))
        try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "The completed reply's card was not read")
        try check(!pane.isBusy, "the card staged during a reply is read when the reply completes")
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        try check(card()?.kind == "paired-interval" && pane.share.state == .off, "changing the sharing options keeps the card, which sends nothing")
        pane.share.performClick(nil)
        pane.confirm.performClick(nil)
        let rowsBeforeHold = await assistantRows(), holds = requestLines().filter { $0.contains("HOLD_A") }.count
        pane.input.string = "HOLD_A"
        pane.send()
        try check(card() == nil, "a new question hides the card at once")
        try await wait("The held question did not reach the fixture") { requestLines().filter { $0.contains("HOLD_A") }.count > holds }
        pane.stop()
        try await wait("Stop did not end the held reply") { !pane.isBusy }
        let rowsAfterHold = await assistantRows()
        try check(pane.distribution == nil && card() == nil && rowsAfterHold == rowsBeforeHold, "after Stop the card does not come back")
        pane.input.string = "STOP_CARD_A"
        pane.send()
        try await wait("The card reply did not stream before Stop") {
            guard exists("stop-card-staged") else { return false }
            return (await text(pane)).contains("Card staged before Stop.")
        }
        pane.stop()
        try await wait("Stop did not end the card reply") { !pane.isBusy && shown("worksheet-ai-help-choose") }
        let stoppedCard = await text(pane)
        try check(pane.distribution == nil && stoppedCard.contains("[Reply stopped before completion.]"), "a card staged by a stopped reply is dropped")
    }

    func cardsStayLocal(_ first: Document, _ cards: Document) async throws {
        // The card never travels: no card wording in any request, and no card choice in the conversation (Windows :120-126).
        pane.input.string = "AFTER_CARD_A"
        pane.send()
        try await wait("The follow-up did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("Follow-up without the card.")
        }
        let cardLog = requestLines().joined(separator: "\n")
        try check(!WorksheetAIChecks.cardWords.contains(where: cardLog.contains),
                  "no request carries a card's wording, and the follow-up's conversation holds no card choice")

        // A new conversation, hiding the dock and switching workbook each retire the card.
        for retire in ["New conversation", "Close", "workbook"] {
            pane.input.string = "DESIGN_A"
            pane.send()
            try await waitCard("choose", [chooseLine], "The study-design question did not appear before " + retire)
            switch retire {
            case "New conversation": button("New conversation")?.performClick(nil)
            case "Close":
                pane.hide()
                try await toolbar(cards, "worksheetAI")
                try await wait("AI Assist did not reopen on the card workbook") { pane.visible && pane.workbookID == cards.id }
            default:
                viewer.tabs.selectTabViewItem(first.item)
                try await wait("AI Assist did not follow workbook A") { pane.workbookID == first.id }
                viewer.tabs.selectTabViewItem(cards.item)
                try await wait("AI Assist did not return to the card workbook") { pane.workbookID == cards.id }
            }
            try check(pane.distribution == nil && card() == nil, retire == "workbook" ? "switching workbook retires the card" : retire + " retires the card")
        }
    }

    /// An offer chosen on a card stands on the card's reading (Windows binds its proposal to the card's selection and version,
    /// frmSpreadsheetGear.WorksheetAnalysis.cs:18-35): a change of "First row has column names" after the branch, or of the
    /// selection before the offer is prepared, refuses it as Windows refuses a target that changed (ScriptAIPane.WorksheetAnalysis.cs
    /// :393-398 and :405-410): the offer and its card go, the notice gives the offer's text, the general choices come back with
    /// the keyboard focus that was on the card or the offer, and nothing opens or is sent.
    func offersHeldToTheCard(_ cards: Document) async throws {
        // What a refusal leaves: no offer and no card, the general choices, and nothing opened.
        func cleared(_ documents: Int) -> Bool {
            pane.offer == nil && pane.distribution == nil && card() == nil && shown("worksheet-ai-help-choose")
                && viewer.documents.count == documents && viewer.active === cards
        }
        try await select(cards, "selectCells({x:42,y:0,width:2,height:5})", "Selection: Cards!AQ1:AR5")
        pane.input.string = "PAIRED_A"
        pane.send()
        let headed: String = "Local check found 4 complete pairs. Shapiro–Wilk W = 0.8634, P = 0.2725."
        try await waitCard("paired-interval", [headed], "The paired card was not staged for AQ1:AR5")
        try click("normal")
        _ = try await offered("Paired Student t test")
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        let continueFocus: Bool = proceed.map { viewer.window.makeFirstResponder($0) && viewer.window.firstResponder === $0 } ?? false
        let documents: Int = viewer.documents.count, quiet: [String] = dataTraffic()
        try await grid(cards, checkbox)
        try await wait("The page did not report First row has column names unticked") { cards.aiWorksheet?.headerRow == false }
        pane.showNotice("")
        proceed?.performClick(nil)
        try await wait("Continue after the header toggle was not refused: notice \(label("worksheet-ai-notice").debugDescription)") {
            label("worksheet-ai-notice") == WorksheetAICardChanged.message && pane.offer == nil
        }
        try check(cleared(documents) && dataTraffic() == quiet,
                  "Continue after First row has column names was unticked is refused as on Windows: the offer and its card go, the notice gives the offer's text, the general choices come back, and nothing opens or is sent")
        try checkFocus(continueFocus, viewer.window.firstResponder === pane.helpChoose,
                       "the keyboard focus on a refused Continue moves to Help me choose a method, the first of the general choices")
        try await grid(cards, checkbox)
        try await wait("The page did not report First row has column names ticked") { cards.aiWorksheet?.headerRow == true }
        pane.input.string = "PAIRED_A"
        pane.send()
        try await waitCard("paired-interval", [headed], "The paired card was not staged again for AQ1:AR5")

        // The selection changed between the branch click and the offer's preparation, which the page reports only once it
        // settles: made inside the very page call that captures the selection for the offer, by wrapping it once.
        _ = try await cards.web.callAsyncJavaScript("""
            const grid = window.statsDirectGrid, original = grid.worksheetAISelection;
            grid.worksheetAISelection = () => {
              grid.worksheetAISelection = original; window.statsDirectTestMoved = true;
              grid.selectCells({x:0,y:0,width:2,height:13}); return original();
            };
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        let raced: [String] = dataTraffic(), opened: Int = viewer.documents.count
        pane.showNotice("")
        let raceFocus: Bool = try pressWithFocus("normal")
        try await wait("An offer for a selection changed under the card was not refused: notice \(label("worksheet-ai-notice").debugDescription)") {
            label("worksheet-ai-notice") == WorksheetAICardChanged.message
        }
        let moved = try await cards.web.evaluateJavaScript("window.statsDirectTestMoved === true") as? Bool
        try await wait("The page did not report A1:B13") { pane.selectionLabel.stringValue == "Selection: Cards!A1:B13" }
        try check(moved == true && cleared(opened) && dataTraffic() == raced,
                  "an offer whose selection changed between the branch click and its preparation is refused as on Windows: the card goes, the notice gives the offer's text, the general choices come back, and nothing opens or is sent")
        try checkFocus(raceFocus, viewer.window.firstResponder === pane.helpChoose,
                       "the keyboard focus on a branch whose offer is refused as it is prepared moves to Help me choose a method, the first of the general choices")
        pane.input.string = "PAIRED_A"
        pane.send()
        try await waitCard("paired-interval", ["Local check found 12 complete pairs. Shapiro–Wilk W = 0.9669, P = 0.8757."], "The paired card was not staged for A1:B13")

        // An error preparing the offer clears the card, with the error in the notice line, and the focus that was on the branch
        // moves to the first of the general choices.
        pane.showNotice("")
        cards.fileBusy = true
        let errorFocus: Bool = try pressWithFocus("normal")
        try await wait("An error preparing the offer did not clear the card") {
            pane.distribution == nil && label("worksheet-ai-notice") == WorksheetAICardChanged.message
        }
        cards.fileBusy = false
        try check(pane.offer == nil && card() == nil && shown("worksheet-ai-help-choose"), "an error preparing the offer clears the card and shows the error in the notice line")
        try checkFocus(errorFocus, viewer.window.firstResponder === pane.helpChoose,
                       "the keyboard focus on a branch whose offer cannot be prepared moves to Help me choose a method, the first of the general choices")
    }

    func cardNeedsWorkbookInFront(_ cards: Document, _ report: Document) async throws {
        // The card is offered only with the workbook in front (Windows: the grid must be the active window).
        viewer.tabs.selectTabViewItem(report.item)
        pane.input.string = "NO_CARD_A"
        pane.send()
        try await wait("The shared question without the workbook in front did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("No card offered.")
        }
        pane.sharingButton.performClick(nil)
        pane.share.performClick(nil)
        pane.input.string = "NO_CARD_QO"
        pane.send()
        try await wait("The question-only question without the workbook in front did not finish") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).components(separatedBy: "No card offered.").count == 3
        }
        try check(pane.workbookID == cards.id, "with another document in front, neither mode offers the card's tool")
    }

    func questionOnlyCards() async throws -> (Document, WorksheetAIHarness.Card) {
        // Question only (Windows guidance-only): the card's tool alone, completed on this Mac, and nothing about the
        // workbook in any request. The PEFR values of the example workbook, shifted, under private names.
        var privateCells: [[String: Any]] = [["col": 0, "row": 0, "text": "Qzbefore", "kind": "text"], ["col": 1, "row": 0, "text": "Qzafter", "kind": "text"]]
        for (row, pair) in zip([312, 242, 340, 388, 296, 254, 391, 402, 290], [300, 201, 232, 312, 220, 256, 328, 330, 231]).enumerated() {
            privateCells += [["col": 0, "row": row + 1, "text": String(100_000 + pair.0), "kind": "number"],
                             ["col": 1, "row": row + 1, "text": String(100_000 + pair.1), "kind": "number"]]
        }
        let secret = ["QZPRIVATE_BOOK", "QZPRIVATE_SHEET", "Qzbefore", "Qzafter", "100312", "100300", "Local check found", "W = 0.9393",
                      "W = 0.919", "W = 0.8906"]
        try JSONSerialization.data(withJSONObject: secret).write(to: storage.appendingPathComponent("private.json"))
        let qz = viewer.newDocument(kind: "grid", title: "QZPRIVATE_BOOK", url: viewer.root.appendingPathComponent("Grid/index.html"))
        qz.workbookName = "QZPRIVATE_BOOK.xlsx"
        qz.pendingWorkbook = ["name": "QZPRIVATE_BOOK", "formulaCount": 0,
                              "sheets": [["name": "QZPRIVATE_SHEET", "rows": 100, "columns": 8, "headerRow": true, "cells": privateCells]]]
        try await wait("AI Assist did not follow the private workbook") {
            pane.workbookID == qz.id && qz.pendingWorkbook == nil && qz.aiWorksheet?.hasData == true
        }
        try await select(qz, "selectColumns([[0,2]])", "Selection: QZPRIVATE_SHEET!A:B")
        let start = requestLines().count
        pane.input.string = "PAIRED_QO"
        pane.send()
        let local = try await waitCard("paired-interval", ["Local check found 9 complete pairs. Shapiro–Wilk W = 0.9393, P = 0.5746.",
            "Suggested branch\nA paired t test answers the question about the mean difference. Shapiro–Wilk found no clear departure from normality, and the shape checks flagged no unusual differences. With this sample, those checks provide limited evidence."],
            "The question-only card did not check the whole columns")
        let localReply = await text(pane)
        try check(local.titles == ["Large sample (more than 100 complete pairs)", "Suggested · Small or medium · Approximately normal differences",
                                   "Non-normal differences", "Change design"] && localReply.contains("Decision card offered without workbook data."),
                  "question only offers exactly the card's tool, answers every refused call with Windows' guidance-only texts (the help text for a tool not offered), and the card checks whole columns A:B to their last values")
        let quietQuestion = dataTraffic()
        try click("large")
        try await feedback("The local check found at most 100 complete pairs. Choose the branch for the distribution of the differences.", "Large sample at 9 pairs gave no feedback")
        try click("normal")
        let questionOffer = try await offered("Paired Student t test")
        try check(questionOffer.contains("Selection: Columns A:B")
                  && questionOffer.contains("The paired t test addresses the mean difference. This branch assumes approximately normal differences."),
                  "in question-only mode a branch offers its method on this Mac")
        _ = await pane.changeSample()
        try await waitCard("paired-interval", ["Local check found 9 complete pairs."], "Change sample choice did not return in question-only mode")
        try click("back")
        try await waitCard("choose", [chooseLine], "Change design did not work in question-only mode")
        try click("independent")
        try await waitCard("independent-interval", ["Selected columns, if they hold the two samples separately:\nColumn 1: n = 9. Shapiro–Wilk W = 0.919, P = 0.3843.\nColumn 2: n = 9. Shapiro–Wilk W = 0.8906, P = 0.2023."],
                           "Separate groups did not count the private columns")
        try click("check")
        try await waitCard("independent-interval", ["Column 2: n = 9. Shapiro–Wilk W = 0.8906, P = 0.2023."], "Use these as separate samples did not work in question-only mode",
                           absent: ["Selected columns, if they hold"])
        try click("back")
        try await waitCard("choose", [chooseLine], "Change design did not return again")
        try click("paired")
        try await waitCard("paired-interval", ["Local check found 9 complete pairs."], "Same people or units did not check the private pairs again")
        try click("non-normal")
        _ = try await offered("Wilcoxon signed ranks test")
        let documents = viewer.documents.count
        pane.continueAnalysis()
        try await wait("Continue did not open Wilcoxon signed ranks") { viewer.documents.count == documents + 1 && viewer.active?.kind == "operation" }
        let operation = viewer.active!
        try check(operation.operationName == "Wilcoxon" && operation.operationSourceID == qz.id && pane.offer == nil && pane.distribution == nil
                  && dataTraffic() == quietQuestion,
                  "Continue opens the chosen method for the private workbook on this Mac, retires the card and sends nothing")
        viewer.remove(operation)
        // A question-only question after the card's choices, while the private list holds: nothing of the card may go with it.
        viewer.tabs.selectTabViewItem(qz.item)
        try await wait("AI Assist did not return to the private workbook") { pane.workbookID == qz.id && !pane.isBusy }
        pane.input.string = "QZ_AFTER_CARDS"
        pane.send()
        try await wait("The question after the private card's choices was not answered") {
            guard !pane.isBusy else { return false }
            return (await text(pane)).contains("General guidance without workbook data.")
        }
        try check(pane.distribution == nil && pane.offer == nil, "a question-only question after the private card's choices is answered with no card")
        let questionLog = requestLines()[start...].joined(separator: "\n")
        try check(!secret.contains(where: questionLog.contains), "no question-only request carries the workbook, its sheet, headings, cells or the card's wording")

        // The example workbook's PEFR columns, whole (Windows' A:B case): nine pairs, as Windows and R give them.
        guard let example = viewer.documents.last(where: { $0.kind == "grid" && $0.workbookName == "test.xlsx" }) else {
            throw ChatGPTTutor.Failure(message: "The example workbook is not open")
        }
        try JSONSerialization.data(withJSONObject: ["PEFR Before", "PEFR After", "test.xlsx", "Local check found"]).write(to: storage.appendingPathComponent("private.json"))
        viewer.tabs.selectTabViewItem(example.item)
        try await wait("AI Assist did not follow the example workbook") { pane.workbookID == example.id }
        try await select(example, "selectColumns([[0,2]])", "Selection: Parametric!A:B")
        pane.input.string = "PAIRED_QO"
        pane.send()
        let pefr = try await waitCard("paired-interval", ["Local check found 9 complete pairs. Shapiro–Wilk W = 0.9393, P = 0.5746.",
                                                          "Suggested · Small or medium · Approximately normal differences"], "The example's PEFR columns were not checked")
        try check(!pefr.choices.contains("check"), "the example's PEFR columns A:B give Windows' 9 pairs, W = 0.9393 and P = 0.5746 (R 4.6.1: 0.939305, 0.574604)")
        return (qz, pefr)
    }

    func policyAndCleanup(_ first: Document, _ cards: Document, _ qz: Document, _ report: Document, pefrToken: String) async throws {
        // A policy that disables AI hides the card and refuses its clicks. Setting it can end the ChatGPT connection, so it comes last.
        UserDefaults.standard.set(true, forKey: "DisableOnlineTutor")
        pane.updateControls()
        let disabledClick = await pane.answerCard("normal", token: pefrToken)
        try check(card() == nil && !disabledClick, "a policy that disables AI hides the card and refuses its clicks")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
        try? FileManager.default.removeItem(at: storage.appendingPathComponent("private.json"))
        viewer.remove(qz)
        viewer.remove(cards)
        viewer.tabs.selectTabViewItem(first.item)
        try await wait("AI Assist did not return to workbook A after the card checks") { pane.workbookID == first.id }
        if viewer.documents.contains(where: { $0 === report }) { viewer.remove(report) }   // the preflight's routing closes it to leave no report open
        viewer.tabs.selectTabViewItem(first.item)
        try await toolbar(first, "worksheetLearn")
        try await wait("Learn did not open from the toolbar") { viewer.active?.kind == "learn" }
        try check(pane.workbookID == first.id, "Learning opens from the toolbar without retargeting worksheet AI")
        UserDefaults.standard.set(true, forKey: "DisableOnlineTutor")
        pane.updateControls()
        try check(!pane.sendButton.isEnabled && !pane.share.isEnabled, "managed online AI disable blocks worksheet sending and sharing")
        UserDefaults.standard.set(false, forKey: "DisableOnlineTutor")
    }
}

// The cards with the keyboard and in a narrow window: Codex's preflight checklist asks for both in the Mac build
// (distribution-preflight/README.md:11).
extension WorksheetAIHarness {
    /// Whether the run prints the routes Tab takes through the pane (pass --keyboard-report after the app's path to
    /// Scripts/test-worksheet-ai.sh).
    var keyboardReport: Bool { CommandLine.arguments.contains("--keyboard-report") }

    /// Keyboard navigation (System Settings ▸ Keyboard), on for this process only while it is set. With it off, as on this Mac, AppKit
    /// lets a view take part in Tab only when it needs its window to be key to take keys (needsPanelToBecomeKey: text and web views),
    /// so no button does; with it on, every enabled, shown button does. While this is set the driver gives NSButton that answer,
    /// and otherwise leaves the question to AppKit. The system setting is neither read nor changed.
    nonisolated(unsafe) static var keyboardNavigation = false
    nonisolated(unsafe) static var keyboardNavigationHooked = false
    func keyboardNavigation(_ on: Bool) {
        if !Self.keyboardNavigationHooked {
            Self.keyboardNavigationHooked = true
            let selector = #selector(getter: NSView.needsPanelToBecomeKey)
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            let appKit = unsafeBitCast(class_getMethodImplementation(NSButton.self, selector), to: Getter.self)
            let answer: @convention(block) (AnyObject) -> Bool = { button in WorksheetAIHarness.keyboardNavigation || appKit(button, selector) }
            let implementation = imp_implementationWithBlock(answer)
            if let own = class_getInstanceMethod(NSButton.self, selector), own != class_getInstanceMethod(NSControl.self, selector) {
                method_setImplementation(own, implementation)
            } else {
                class_addMethod(NSButton.self, selector, implementation, "B@:")
            }
        }
        Self.keyboardNavigation = on
    }

    /// A key pressed and released as a person's reaches the window, built as Tests/help-pane-driver.swift:246 builds its Tab, with the
    /// characters the system gives: under Shift, Tab's backtab in charactersIgnoringModifiers too, from which AppKit takes the
    /// direction. WebKit takes the focus and hands it on in its own time, so a press that leaves the focus in a web view waits.
    func press(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) async {
        let window: NSWindow = viewer.window
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                window.sendEvent(event)
            }
        }
        try? await Task.sleep(for: .milliseconds(window.firstResponder is WKWebView ? 400 : 10))
    }
    static let backtab = String(UnicodeScalar(UInt8(0x19)))
    /// Tab (keyCode 48), Shift-Tab (back) and their Control forms, which leave a text view whose Tab types a tab.
    func tab(back: Bool = false, control: Bool = false) async {
        var modifiers: NSEvent.ModifierFlags = back ? [.shift] : []
        if control { modifiers.insert(.control) }
        await press(48, back ? Self.backtab : "\t", modifiers)
    }
    /// Space (keyCode 49), which presses the focused button.
    func space() async { await press(49, " ") }

    /// Where the keyboard focus is, as the routes name it.
    func focusName(_ responder: NSResponder?) -> String {
        guard let responder else { return "nothing" }
        if responder === viewer.window { return "the window" }
        if responder === pane.input { return "the composer" }
        if responder === pane.transcript.web { return "the transcript" }
        if let web = responder as? WKWebView {
            return viewer.documents.first(where: { $0.web === web }).map { "the page of " + $0.title } ?? "a web page"
        }
        if let button = responder as? NSButton { return "[" + button.title + "]" }
        if let view = responder as? NSView, let id = view.identifier?.rawValue, !id.isEmpty { return id }
        return String(describing: type(of: responder))
    }

    /// The pane's controls a keyboard user meets, in its visual order (its stack top to bottom, each row leading to trailing): its
    /// buttons, the composer and the transcript, the shown ones only.
    func paneControls() -> [NSView] {
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        var found: [NSView] = []
        func walk(_ view: NSView) {
            guard !view.isHidden, view.window != nil else { return }
            if view is NSButton || view === pane.input || view === pane.transcript.web { found.append(view); return }
            if let stack = view as? NSStackView { stack.arrangedSubviews.forEach(walk) }
            else if let scroll = view as? NSScrollView { if let document = scroll.documentView { walk(document) } }
            else { view.subviews.forEach(walk) }
        }
        pane.view.subviews.forEach(walk)
        return found
    }

    /// The buttons a keyboard user must reach in the pane as it stands, in its visual order: the card's choices, the general choices,
    /// the offer's buttons and the clarifying question's answers, each group with what is shown of it.
    func keyboardTargets() -> [(group: String, buttons: [NSView])] {
        let controls = paneControls()
        func inside(_ id: String) -> [NSView] {
            guard let box: NSView = control(id, in: pane.view) else { return [] }
            return controls.filter { $0.isDescendant(of: box) }
        }
        let choices: [NSButton] = [pane.openExample, pane.workbookHelp, pane.helpChoose, pane.chooseMethod]
        let general: [NSView] = controls.filter { control in choices.contains { $0 === control } }
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        let offer: [NSView] = proceed?.superview?.superview.map { panel in controls.filter { $0.isDescendant(of: panel) } } ?? []
        let groups: [(group: String, buttons: [NSView])] = [("card", inside("worksheet-ai-distribution")), ("general choices", general),
                                                              ("offer", offer), ("clarification", inside("worksheet-ai-clarification"))]
        return groups.filter { !$0.buttons.isEmpty }
    }

    /// Where Tab, or Shift-Tab with `back`, takes the focus from `start`, press by press, until it stays or comes round again. From the
    /// composer, whose Tab types a tab, Control-Tab (Control-Shift-Tab) is pressed instead, as a keyboard user leaves a text view;
    /// anything typed is taken out again.
    func route(from start: NSView, back: Bool = false, presses: Int = 40) async -> (steps: [String], visited: [NSResponder]) {
        _ = viewer.window.makeFirstResponder(start)
        var current: NSResponder? = viewer.window.firstResponder
        var visited: [NSResponder] = current.map { [$0] } ?? []
        var steps: [String] = [], inPage = 0
        for _ in 0..<presses {
            let inComposer = current === pane.input, draft = pane.input.string
            await tab(back: back, control: inComposer)
            if inComposer { pane.input.string = draft }
            let now = viewer.window.firstResponder
            let key = (inComposer ? "Control-" : "") + (back ? "Shift-Tab" : "Tab")
            if now === current, now is WKWebView, inPage < 3 { inPage += 1; continue }
            if inPage > 0 { steps.append(key + " pressed \(inPage + 1) times in the page" + (now === current ? "" : " then")) }
            inPage = 0
            if now === current { steps.append(key + " stays"); break }
            steps.append(key + " → " + focusName(now))
            guard let now, !visited.contains(where: { $0 === now }) else { steps.append("(round again)"); break }
            visited.append(now)
            current = now
        }
        return (steps, visited)
    }

    /// The keyboard's routes through the pane as it stands: Tab in the composer; from each control before the choices, in the pane's
    /// visual order, the route Tab takes and how many of each group's buttons it meets; and Shift-Tab back from each group's last
    /// button. Printed with --keyboard-report.
    @discardableResult
    func measureKeyboard(_ state: String) async -> [String] {
        let setting = Self.keyboardNavigation ? "Keyboard navigation on (this process)" : "Keyboard navigation as set on this Mac (off)"
        let controls = paneControls(), targets = keyboardTargets()
        let end = controls.firstIndex { $0 === pane.transcript.web }.map { $0 + 1 }
            ?? controls.firstIndex { $0.isDescendant(of: pane.guidance) } ?? controls.count
        var lines: [String] = []
        let draft = pane.input.string
        _ = viewer.window.makeFirstResponder(pane.input)
        pane.input.string = ""
        await tab()
        let typed = pane.input.string, kept = viewer.window.firstResponder === pane.input
        lines.append("in the composer Tab " + (typed == "\t" && kept ? "types a tab and keeps the focus"
                                                : "gives \(typed.debugDescription) and the focus to \(focusName(viewer.window.firstResponder))"))
        pane.input.string = draft
        for start in controls[..<end] where (start as? NSControl)?.isEnabled != false {
            let (steps, visited) = await route(from: start)
            let met = targets.map { "\($0.group) \($0.buttons.filter { button in visited.contains { $0 === button } }.count)/\($0.buttons.count)" }
            lines.append("from \(focusName(start)): " + (steps.isEmpty ? "no press" : steps.joined(separator: ", ")) + " · reached " + met.joined(separator: ", "))
        }
        for group in targets {
            guard let last = group.buttons.last else { continue }
            let (steps, _) = await route(from: last, back: true)
            lines.append("back from \(focusName(last)): " + steps.joined(separator: ", "))
        }
        if keyboardReport { for line in lines { print("KEYBOARD: \(setting) · \(state) · " + line) } }
        fflush(stdout)
        _ = viewer.window.makeFirstResponder(pane.input)
        return lines
    }

    /// Space pressed on the focused button and the keyboard focus put at once on `elsewhere`, before anything the press began has run:
    /// the user moving on while a card is read or comes back.
    func spaceThenFocus(_ elsewhere: NSResponder) {
        let window: NSWindow = viewer.window
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                            isARepeat: false, keyCode: 49) {
                window.sendEvent(event)
            }
        }
        window.makeFirstResponder(elsewhere)
    }
}

extension WorksheetAIHarness {
    /// The keyboard in the pane, in each state it must get through (the study-design question, the paired card, the offer, the
    /// general choices and the clarifying question), then the keyboard alone from a card to its method, and focus the user moves
    /// elsewhere. Tab reached nothing in the pane before it linked its controls (linkKeyViews): it joins the window after the
    /// window has made its key view loop.
    func keyboardCards(_ cards: Document) async throws {
        if keyboardReport {
            let window: NSWindow = viewer.window
            print("KEYBOARD: the window: key \(window.isKeyWindow), autorecalculatesKeyViewLoop \(window.autorecalculatesKeyViewLoop), initial first responder "
                  + focusName(window.initialFirstResponder) + ", the composer's next key view " + focusName(pane.input.nextKeyView))
        }
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        pane.input.string = "DESIGN_A"
        pane.send()
        _ = try await waitCard("choose", [chooseLine], "The study-design question did not appear for the keyboard's routes")
        try await checkRoutes("the study-design question", "card")
        try click("paired")
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "The paired card did not appear for the keyboard's routes")
        try await checkRoutes("the paired card", "card")
        try click("normal")
        _ = try await offered("Paired Student t test")
        try await checkRoutes("the offer", "offer")
        button("Cancel")?.performClick(nil)
        try await wait("Cancel did not bring back the general choices for the keyboard's routes") { pane.offer == nil && shown("worksheet-ai-help-choose") }
        try await checkRoutes("the general choices", "general choices")
        pane.input.string = "CLARIFY_THEN_CARD_A"
        pane.send()
        try await wait("The clarifying question did not appear for the keyboard's routes") { !pane.isBusy && pane.clarification != nil }
        try await checkRoutes("the clarifying question", "clarification")
        try await keyboardOnlyPath(cards)
        try await focusMovedElsewhere(cards)
    }

    /// The routes in the pane as it stands. With Keyboard navigation off, as on this Mac, Tab passes over buttons as it does on every
    /// Mac: Tab types a tab in the composer, and from New conversation Tab reaches the composer, whose Control-Tab reaches the
    /// transcript. With it on, Tab from New conversation meets every enabled control of the pane in visual order (Control-Tab out of
    /// the composer), the buttons of the card, the general choices, the offer or the clarifying question among them; from each
    /// control before the choices it meets every one that follows; and Shift-Tab from the last retraces the route to the first.
    func checkRoutes(_ state: String, _ group: String) async throws {
        if keyboardReport { for on in [false, true] { keyboardNavigation(on); await measureKeyboard(state) } }
        keyboardNavigation(false)
        defer { keyboardNavigation(false); viewer.window.makeFirstResponder(pane.input) }
        guard let first = paneControls().first else { throw ChatGPTTutor.Failure(message: "The pane shows no control for the keyboard") }
        let draft = pane.input.string
        pane.input.string = ""
        viewer.window.makeFirstResponder(pane.input)
        await tab()
        let typed = pane.input.string == "\t" && viewer.window.firstResponder === pane.input
        pane.input.string = draft
        let plain = await route(from: first)
        let passed = plain.visited.count == 3 && plain.visited[1] === pane.input && plain.visited[2] === pane.transcript.web
        try check(typed && passed, "\(state), Keyboard navigation off as on this Mac: Tab types a tab in the composer, and from New conversation Tab passes over "
                  + "the buttons to the composer, whose Control-Tab reaches the transcript" + (typed && passed ? "" : ": " + plain.steps.joined(separator: ", ")))
        keyboardNavigation(true)
        let controls = paneControls().filter { ($0 as? NSControl)?.isEnabled != false }
        let buttons = keyboardTargets().first(where: { $0.group == group })?.buttons ?? []
        func same(_ visited: [NSResponder], _ expected: ArraySlice<NSView>) -> Bool {
            visited.count == expected.count && zip(visited, expected).allSatisfy { $0 === $1 }
        }
        let forward = await route(from: controls[0])
        let end = controls.firstIndex { $0 === pane.transcript.web }.map { $0 + 1 } ?? controls.count
        var stopped: [String] = []
        for index in 1..<end {
            let from = await route(from: controls[index])
            if !same(from.visited, controls[index...]) { stopped.append("from \(focusName(controls[index])): " + from.steps.joined(separator: ", ")) }
        }
        let back = await route(from: controls[controls.count - 1], back: true)
        let reached = !buttons.isEmpty && buttons.allSatisfy { button in forward.visited.contains { $0 === button } }
        let inOrder = same(forward.visited, controls[...]), retraced = same(back.visited, ArraySlice(controls.reversed()))
        try check(reached && inOrder && stopped.isEmpty && retraced,
                  "\(state), Keyboard navigation on: Tab from New conversation meets the pane's \(controls.count) controls in visual order, every one of the "
                  + "\(buttons.count) buttons of the \(group) among them (Control-Tab out of the composer); from each of the \(end - 1) other controls "
                  + "before the choices Tab meets every one that follows; Shift-Tab retraces the route"
                  + (reached && inOrder && stopped.isEmpty && retraced ? "" : ": Tab " + forward.steps.joined(separator: ", ") + "; Shift-Tab "
                     + back.steps.joined(separator: ", ") + (stopped.isEmpty ? "" : "; " + stopped.joined(separator: "; "))))
    }

    /// The keyboard alone, from a card to its method, with Keyboard navigation on: from the composer, Control-Tab and Tab to the
    /// study-design question's first answer and Space; the paired card is read with the focus on its first choice (as the mouse path
    /// in designAndStaleClicks); Tab to the suggested branch and Space; the offer comes with the focus on Continue; Tab past Cancel to
    /// Change sample choice and Shift-Tab back to Continue (Change sample choice follows Continue and Cancel, on its own row); Tab to it
    /// again and Space: the card comes back with the focus on its first choice; Tab and Space on the branch again, and Space on
    /// Continue: the method opens for the selection with the report its offer names, as the preflight's mouse path checks.
    func keyboardOnlyPath(_ cards: Document) async throws {
        keyboardNavigation(true)
        defer { keyboardNavigation(false) }
        func focused(_ choice: String) -> Bool {
            (viewer.window.firstResponder as? WorksheetAIChoiceButton).map { $0.choice == choice && $0.token == pane.guidanceToken && !$0.isHiddenOrHasHiddenAncestor } ?? false
        }
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        pane.input.string = "DESIGN_A"
        pane.send()
        _ = try await waitCard("choose", [chooseLine], "The study-design question did not appear for the keyboard alone")
        viewer.window.makeFirstResponder(pane.input)
        var presses: [String] = []
        while !focused("paired"), presses.count < 12 {
            let control = viewer.window.firstResponder === pane.input
            await tab(control: control)
            presses.append((control ? "Control-Tab → " : "Tab → ") + focusName(viewer.window.firstResponder))
        }
        try check(focused("paired"), "with the keyboard alone, from the composer " + presses.joined(separator: ", ") + " reaches the study-design question's first answer")
        await space()
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Space on Same people or units did not read the paired card")
        try check(focusOnFirstChoice(), "Space on Same people or units reads the paired card with the focus on its first choice")
        await tab()
        let onBranch = focused("normal")
        await space()
        let offer = try await offered("Paired Student t test")
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view), sample: NSButton? = control("worksheet-ai-change-sample", in: pane.view)
        try check(onBranch && proceed != nil && viewer.window.firstResponder === proceed && offer.contains("Selection: Y1:Z8"),
                  "Tab moves to the suggested branch, and Space on it offers the paired t test with the focus on Continue")
        await tab(); await tab()
        let onSample = sample != nil && viewer.window.firstResponder === sample
        await tab(back: true); await tab(back: true)
        try check(onSample && viewer.window.firstResponder === proceed, "Tab reaches Change sample choice past Cancel, and Shift-Tab goes back to Continue")
        await tab(); await tab()
        await space()
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Space on Change sample choice did not return to the card")
        try check(pane.offer == nil && focusOnFirstChoice(), "Space on Change sample choice returns to the card with the focus on its first choice")
        await tab()
        await space()
        _ = try await offered("Paired Student t test")
        let destination = viewer.currentReportDestination, before = viewer.documents.count
        let named = destination?.title ?? "New report"
        try check(viewer.window.firstResponder === proceed && pane.offer?.reportTitle == named,
                  "Space on the branch again offers the method with the focus on Continue and \(named) as its report")
        await space()
        try await wait("Space on Continue did not open the paired t test") { viewer.documents.count == before + 1 && viewer.active?.kind == "operation" }
        let run = viewer.active!
        try await wait("The paired t test opened with the keyboard did not show its report destination") {
            let shown = (try? await run.web.evaluateJavaScript("document.querySelector('main header p')?.textContent ?? ''")) as? String
            return run.operationSourceSnapshot != nil && shown == "Report destination: " + named
        }
        let routed = run.operationName == "TPaired" && run.operationSourceID == cards.id
            && run.operationReportDestination == (destination.map { .existing(id: $0.id, title: $0.title) } ?? .new)
            && run.operationSourceSnapshot?["selection"] as? [Int] == [24, 25] && pane.offer == nil && pane.distribution == nil
        try check(routed, "Space on Continue opens the paired t test for Y1:Z8's two columns with \(named) as its destination, as the mouse path does, and retires the card"
                  + (routed ? "" : " (operation \(run.operationName ?? "none"), destination \(String(describing: run.operationReportDestination)), selection "
                     + String(describing: run.operationSourceSnapshot?["selection"]) + ")"))
        // Windows' dialog takes the keyboard once Continue has retired its confirmation (ScriptAIPane.WorksheetAnalysis.cs:393-397).
        try check(viewer.window.firstResponder === run.web, "the paired t test opened with Space on Continue has the keyboard focus, as Windows' dialog takes it, "
                  + "not the pane's next control: " + focusName(viewer.window.firstResponder))
        viewer.remove(run)
        viewer.tabs.selectTabViewItem(cards.item)
        try await wait("AI Assist did not return to the card workbook after the keyboard's method") { viewer.active === cards && pane.workbookID == cards.id }
    }

    /// Focus the user puts elsewhere while a card is read, or while the card comes back after Change sample choice, is left there
    /// (Keyboard navigation on): the pane passes on only the focus a card or the offer had, or that AppKit moved on as the offer went.
    func focusMovedElsewhere(_ cards: Document) async throws {
        keyboardNavigation(true)
        defer { keyboardNavigation(false); viewer.window.makeFirstResponder(pane.input) }
        pane.input.string = "DESIGN_A"
        pane.send()
        _ = try await waitCard("choose", [chooseLine], "The study-design question did not appear for the focus moved elsewhere")
        guard let answer: WorksheetAIChoiceButton = control("worksheet-ai-card-paired", in: pane.view), viewer.window.makeFirstResponder(answer) else {
            throw ChatGPTTutor.Failure(message: "Same people or units did not take the keyboard focus")
        }
        spaceThenFocus(pane.input)
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Space on Same people or units did not read the paired card")
        try check(viewer.window.firstResponder === pane.input,
                  "Space on Same people or units with the focus then put in the composer before the card is read: the focus stays in the composer")
        try click("normal")
        _ = try await offered("Paired Student t test")
        guard let sample: NSButton = control("worksheet-ai-change-sample", in: pane.view), viewer.window.makeFirstResponder(sample) else {
            throw ChatGPTTutor.Failure(message: "Change sample choice did not take the keyboard focus")
        }
        spaceThenFocus(cards.web)
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Space on Change sample choice did not return to the card")
        try check(pane.offer == nil && viewer.window.firstResponder === cards.web,
                  "Space on Change sample choice with the focus then put on the worksheet before the card comes back: the focus stays on the worksheet")
    }
}

extension WorksheetAIHarness {
    /// An accessibility element's role, its label, title and value, its children and its parent, for the views, elements and
    /// windows AppKit gives the pane's tree.
    func accessibility(_ element: Any) -> (role: String, words: [String], children: [Any], parent: Any?) {
        func words(_ label: String?, _ title: String?, _ value: Any?) -> [String] {
            var words: [String] = []
            if let label, !label.isEmpty { words.append("label " + label.debugDescription) }
            if let title, !title.isEmpty { words.append("title " + title.debugDescription) }
            if let value = value as? String, !value.isEmpty { words.append("value " + value.debugDescription) }
            if let value = value as? NSAttributedString, value.length > 0 { words.append("value " + value.string.debugDescription) }
            return words
        }
        if let view = element as? NSView {
            return (view.accessibilityRole()?.rawValue ?? "?", words(view.accessibilityLabel(), view.accessibilityTitle(), view.accessibilityValue()),
                    view.accessibilityChildren() ?? [], view.accessibilityParent())
        }
        if let item = element as? NSAccessibilityElement {
            return (item.accessibilityRole()?.rawValue ?? "?", words(item.accessibilityLabel(), item.accessibilityTitle(), item.accessibilityValue()),
                    item.accessibilityChildren() ?? [], item.accessibilityParent())
        }
        if let cell = element as? NSCell {
            return (cell.accessibilityRole()?.rawValue ?? "?", words(cell.accessibilityLabel(), cell.accessibilityTitle(), cell.accessibilityValue()),
                    cell.accessibilityChildren() ?? [], cell.accessibilityParent())
        }
        if let window = element as? NSWindow {
            return (window.accessibilityRole()?.rawValue ?? "?", words(window.accessibilityLabel(), window.accessibilityTitle(), nil), [], nil)
        }
        return (String(describing: type(of: element)), [], [], nil)
    }

    /// What the pane shows to accessibility from `element` down: each element's role and its label, title or value.
    func accessibilityTree(_ element: Any, depth: Int = 0) -> [String] {
        let shown = accessibility(element)
        var lines = [String(repeating: "  ", count: depth) + shown.role + (shown.words.isEmpty ? "" : " " + shown.words.joined(separator: ", "))]
        if depth < 4 { for child in shown.children { lines += accessibilityTree(child, depth: depth + 1) } }
        return lines
    }

    /// The pane's shown buttons and text fields at the size it has: what cannot be seen whole once scrolled into view, overlaps
    /// another, lies outside the pane, does not show its whole title or text, or scrolls sideways. Empty when the layout holds. On
    /// this macOS a view does not clip to its own bounds, so visibleRect is the part of the pane's visible area the view could draw
    /// in: a view is seen whole when its bounds lie within it.
    func layoutProblems() async -> [String] {
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        let width = pane.view.bounds.width
        // Frames for the overlaps are taken in the pane's content, which scrolling does not move.
        let content: NSView = (pane.view.subviews.first as? NSScrollView)?.documentView ?? pane.view
        var problems: [String] = [], frames: [(String, NSView, NSRect)] = []
        func seen(_ part: NSView, _ name: String) {
            frames.append((name, part, content.convert(part.bounds, from: part)))
            part.scrollToVisible(part.bounds)
            let frame = pane.view.convert(part.bounds, from: part)
            if part.bounds.isEmpty || part.visibleRect.intersection(part.bounds) != part.bounds {
                problems.append(name + " cannot be seen whole: \(part.visibleRect.intersection(part.bounds)) of \(part.bounds)")
            }
            if frame.minX < -0.5 || frame.maxX > width + 0.5 { problems.append(name + " lies outside the pane: \(frame) in \(width)") }
        }
        for button in views(NSButton.self, in: pane.view) where !button.isHiddenOrHasHiddenAncestor && button.window != nil {
            let name = "[" + button.title + "]"
            seen(button, name)
            if let choice = button as? WorksheetAIWrappingButton, choice.wrapsTitle {
                let needed = choice.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: button.bounds.width, height: 10_000)).height ?? .infinity
                if needed > button.bounds.height + 0.5 { problems.append(name + " shows \(button.bounds.height) of its wrapped title's \(needed)") }
            } else {
                let natural = button.intrinsicContentSize
                if natural.width > button.bounds.width + 0.5 || natural.height > button.bounds.height + 0.5 {
                    problems.append(name + " is \(button.bounds.size) for its title's \(natural)")
                }
            }
        }
        for field in views(NSTextField.self, in: pane.view) where !field.isHiddenOrHasHiddenAncestor && field.window != nil && !field.stringValue.isEmpty {
            let name = field.stringValue.prefix(40).debugDescription
            seen(field, name)
            if field.cell?.wraps == true {
                let needed = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10_000)).height ?? .infinity
                if needed > field.bounds.height + 0.5 { problems.append(name + " shows \(field.bounds.height) of its text's \(needed)") }
            } else if field !== pane.replyActivity, field.intrinsicContentSize.width > field.bounds.width + 0.5 {
                problems.append(name + " is \(field.bounds.width) wide for its text's \(field.intrinsicContentSize.width)")
            }
        }
        for (index, (name, part, frame)) in frames.enumerated() {
            for (other, second, rect) in frames[(index + 1)...] where !part.isDescendant(of: second) && !second.isDescendant(of: part)
                && frame.insetBy(dx: 0.5, dy: 0.5).intersects(rect.insetBy(dx: 0.5, dy: 0.5)) {
                problems.append(name + " overlaps " + other + ": \(frame) and \(rect)")
            }
        }
        // The card, the clarifying question, the general choices and the offer fill the pane's width from its leading margin, as
        // Windows' cards fill its conversation.
        if let stack = content.subviews.first(where: { $0 is NSStackView }) {
            let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
            let parts: [(String, NSView?)] = [("the card", control("worksheet-ai-distribution", in: pane.view)),
                                              ("the clarifying question", control("worksheet-ai-clarification", in: pane.view)),
                                              ("the general choices", pane.helpChoose.superview), ("the empty workbook's choices", pane.openExample.superview),
                                              ("the offer", proceed?.superview?.superview)]
            for (name, part) in parts {
                guard let part, !part.isHiddenOrHasHiddenAncestor, part.window != nil else { continue }
                let frame = content.convert(part.bounds, from: part)
                if abs(frame.minX - stack.frame.minX) > 0.5 || abs(frame.width - stack.frame.width) > 0.5 {
                    problems.append(name + " does not fill the pane's width from its leading margin: \(frame) in \(stack.frame)")
                }
            }
        }
        let sideways = (try? await pane.transcript.web.evaluateJavaScript("document.scrollingElement.scrollWidth - document.scrollingElement.clientWidth")) as? Int ?? 0
        if sideways > 0 { problems.append("the transcript scrolls sideways by \(sideways)") }
        if let scroller = pane.view.subviews.first as? NSScrollView, let document = scroller.documentView {
            if document.frame.width > scroller.contentView.bounds.width + 0.5 || scroller.hasHorizontalScroller {
                problems.append("the pane scrolls sideways: its content is \(document.frame.width) wide in \(scroller.contentView.bounds.width)")
            }
            scroller.contentView.scroll(to: .zero)
            scroller.reflectScrolledClipView(scroller.contentView)
        }
        return problems
    }

    /// Pictures of the pane as it is drawn now, taken from its own views (cacheDisplay; no screen capture): the pane with the card,
    /// the clarifying question, the choices or the offer scrolled into view, and, when the pane scrolls, its whole content. Their paths.
    func snapshot(_ name: String) -> [String] {
        let folder = root.appendingPathComponent(".build/worksheet-ai-narrow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        let parts: [NSView?] = [control("worksheet-ai-distribution", in: pane.view), control("worksheet-ai-clarification", in: pane.view),
                                (control("worksheet-ai-continue", in: pane.view) as NSButton?)?.superview?.superview, pane.guidance]
        if let shown = parts.compactMap({ $0 }).first(where: { !$0.isHiddenOrHasHiddenAncestor }) { shown.scrollToVisible(shown.bounds) }
        var paths: [String] = []
        func picture(_ view: NSView, _ file: String) {
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: image)
            let url = folder.appendingPathComponent(file + ".png")
            if let data = image.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { paths.append(url.path) }
        }
        picture(pane.view, name)
        if let scroller = pane.view.subviews.first as? NSScrollView, let document = scroller.documentView,
           document.frame.height > scroller.contentView.bounds.height + 0.5 {
            picture(document, name + "-whole")
        }
        (pane.view.subviews.first as? NSScrollView).map { $0.contentView.scroll(to: .zero); $0.reflectScrolledClipView($0.contentView) }
        return paths
    }
}

extension WorksheetAIHarness {
    /// The sizes the narrow checks use: the suite's own (the pane 460 points wide), the narrowest pane the divider allows in that
    /// window (its delegate, HelpPane, stops it 340 points from the right edge, where a drag ends), and the window at its minimum
    /// size, the pane as the window leaves it.
    func applySize(_ size: String, dock: CGFloat) {
        let window: NSWindow = viewer.window, split = viewer.workspaceSplit
        func layout() { window.contentView?.layoutSubtreeIfNeeded(); split.layoutSubtreeIfNeeded() }
        func narrowest() {
            let limit = split.delegate?.splitView?(split, constrainMaxCoordinate: split.bounds.width, ofSubviewAt: 0) ?? split.bounds.width - 340
            split.setPosition(limit, ofDividerAt: 0)
        }
        window.setContentSize(NSSize(width: 1350, height: 850)); layout()
        split.setPosition(split.bounds.width - dock - split.dividerThickness, ofDividerAt: 0); layout()
        switch size {
        case "narrowest": narrowest()
        case "minimum":
            let frame = window.frame
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - window.minSize.height, width: window.minSize.width, height: window.minSize.height), display: true)
        default: break
        }
        layout()
    }

    /// What `element` and every element under it give accessibility: the role, and the title, label and text of each.
    func accessibilityElements(_ element: Any, depth: Int = 0) -> [(role: String, title: String, text: String)] {
        let shown = accessibility(element)
        func text(_ value: Any?) -> String { (value as? String) ?? (value as? NSAttributedString)?.string ?? "" }
        var title = "", label = "", value = ""
        if let view = element as? NSView { title = view.accessibilityTitle() ?? ""; label = view.accessibilityLabel() ?? ""; value = text(view.accessibilityValue()) }
        else if let cell = element as? NSCell { title = cell.accessibilityTitle() ?? ""; label = cell.accessibilityLabel() ?? ""; value = text(cell.accessibilityValue()) }
        var found = [(role: shown.role, title: title.isEmpty ? label : title, text: value)]
        if depth < 6 { for child in shown.children { found += accessibilityElements(child, depth: depth + 1) } }
        return found
    }

    /// What a state gives accessibility, as Windows' page gives it: the choices are a group with Windows' aria label for what they
    /// show (Learning/conversation.mjs:122-127), and so is the offer ('Proposed worksheet method'); each of their buttons is a button
    /// titled with the text the suite holds to Windows'; and every paragraph of the card, the question and the offer is static text
    /// with its whole text.
    func checkAccessibility(_ state: String, group label: String) throws {
        viewer.window.contentView?.layoutSubtreeIfNeeded()
        var problems: [String] = []
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        let offer = proceed.flatMap { $0.isHiddenOrHasHiddenAncestor ? nil : $0.superview?.superview }
        let box: NSView = offer ?? pane.guidance
        if box.accessibilityRole() != .group || box.accessibilityLabel() != label {
            problems.append("its group is \(box.accessibilityRole()?.rawValue ?? "none") labelled \((box.accessibilityLabel() ?? "nothing").debugDescription)")
        }
        let elements = accessibilityElements(box).dropFirst()
        for button in views(NSButton.self, in: box) where !button.isHiddenOrHasHiddenAncestor {
            if !elements.contains(where: { $0.role == NSAccessibility.Role.button.rawValue && $0.title == button.title }) {
                problems.append("no button titled \(button.title.debugDescription)")
            }
        }
        for field in views(NSTextField.self, in: box) where !field.isHiddenOrHasHiddenAncestor && !field.stringValue.isEmpty {
            if !elements.contains(where: { $0.role == NSAccessibility.Role.staticText.rawValue && $0.text == field.stringValue }) {
                problems.append("no static text reading \(field.stringValue.prefix(60).debugDescription)")
            }
        }
        if let proceed, offer != nil, (proceed.accessibilityParent() as? NSView) !== offer { problems.append("Continue is outside the offer's group") }
        try check(problems.isEmpty, "\(state): the pane gives accessibility a group labelled \(label.debugDescription), as Windows' page does, with each of its "
                  + "buttons by its title and each of its paragraphs as text" + (problems.isEmpty ? "" : ": " + problems.joined(separator: "; ")))
    }

    /// Each card state in the narrowest pane the divider allows and at the window's minimum size (where the pane keeps that width, the
    /// split would otherwise share it out to 287.5 points): no button cut off, overlapping or outside the pane once scrolled into view,
    /// every title and text whole, nothing scrolling sideways (layoutProblems); pictures of each, and at the suite's size, in
    /// .build/worksheet-ai-narrow; and what each state gives accessibility (checkAccessibility).
    func narrowCards(_ cards: Document) async throws {
        let window: NSWindow = viewer.window, split = viewer.workspaceSplit, dock = pane.view.frame.width
        let narrowest = 340 - split.dividerThickness
        var pictures: [String] = [], states: [String] = []
        func measure(_ state: String, _ name: String, _ label: String) async throws {
            var failures: [String] = [], widths: [String] = []
            for size in ["normal", "narrowest", "minimum"] {
                applySize(size, dock: dock)
                let problems = await layoutProblems()
                pictures += snapshot(state + "-" + size)
                widths.append(size + " \(pane.view.frame.width)")
                if size != "normal", abs(pane.view.frame.width - narrowest) > 0.5 { failures.append(size + ": the pane is \(pane.view.frame.width) wide") }
                if size == "minimum", window.frame.size != window.minSize { failures.append("the window is \(window.frame.size), not its minimum \(window.minSize)") }
                if !problems.isEmpty { failures.append(size + " (pane \(pane.view.frame.size)): " + problems.joined(separator: "; ")) }
            }
            applySize("normal", dock: dock)
            try check(failures.isEmpty, "\(name): in the narrowest pane the divider allows (\(narrowest) points), and at the window's minimum size, where the pane keeps "
                      + "that width, no button is cut off, overlaps another or lies outside the pane once scrolled into view, every title and text shows whole, the "
                      + "card fills the pane's width from its leading margin and nothing scrolls sideways" + (failures.isEmpty ? "" : ": " + failures.joined(separator: " | ")))
            try checkAccessibility(name, group: label)
            states.append(state)
        }
        try await select(cards, "selectCells({x:0,y:0,width:1,height:1})", "Current cell: Cards!A1")
        pane.input.string = "DESIGN_A"
        pane.send()
        _ = try await waitCard("choose", [chooseLine], "The study-design question did not appear for the narrow checks")
        try await measure("choose", "the study-design question", "Study design")
        try click("paired")
        _ = try await waitCard("paired-interval", ["How many complete pairs are there?", "Check selected pairs"], "The unread paired card did not appear")
        try await measure("paired-unread", "the paired card unread", "Paired interval measurements")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        _ = try await waitCard("paired-interval", ["Local check found 4 complete pairs.", "Suggested branch"], "The read paired card did not appear")
        try await measure("paired-read", "the paired card read, with its recommendation", "Paired interval measurements")
        try await select(cards, "selectCells({x:6,y:0,width:2,height:103})", "Selection: Cards!G1:H103")
        _ = try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "The paired card for more than 100 pairs did not appear")
        try await measure("paired-large", "the paired card for more than 100 pairs", "Paired interval measurements")
        try click("normal")
        try await feedback("The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks.",
                           "The conflict feedback did not appear for the narrow checks")
        try await measure("paired-feedback", "the paired card with its conflict feedback", "Paired interval measurements")
        try click("large")
        _ = try await offered("Paired Student t test")
        try await measure("offer", "the offer with the card's check and advice", "Proposed worksheet method")
        _ = await pane.changeSample()
        _ = try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "Change sample choice did not return for the narrow checks")
        try click("back")
        _ = try await waitCard("choose", [chooseLine], "Change design did not return for the narrow checks")
        try click("independent")
        _ = try await waitCard("independent-interval", [], "Separate groups did not draw the independent card")
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        // The counts are Y1:Z8's: the card for G1:H103 shows the same question until Y1:Z8 is read.
        _ = try await waitCard("independent-interval", ["Selected columns, if they hold", "Column 1: n = 7", "Use these as separate samples"],
                               "The independent card did not count Y1:Z8")
        try await measure("independent-unconfirmed", "the independent card asking to use the columns as separate samples", "Independent interval measurements")
        try click("check")
        _ = try await waitCard("independent-interval", ["Column 1: n = 7"], "The independent card was not confirmed", absent: ["Selected columns, if they hold"])
        try await measure("independent-confirmed", "the independent card confirmed as separate samples", "Independent interval measurements")
        try click("non-normal")
        _ = try await offered("Mann-Whitney U (two-sample Wilcoxon) test")
        button("Cancel")?.performClick(nil)
        try await wait("Cancel did not bring back the general choices for the narrow checks") { pane.offer == nil && shown("worksheet-ai-help-choose") }
        try await measure("general", "the general choices", "Choose a worksheet method")
        pane.input.string = "CLARIFY_THEN_CARD_A"
        pane.send()
        try await wait("The clarifying question did not appear for the narrow checks") { !pane.isBusy && pane.clarification != nil }
        try await measure("clarification", "the clarifying question", "Analysis question")
        // The methods a reply names, four of the widest titles among them, wider than the narrowest pane: their titles wrap.
        pane.input.string = "LONG_METHODS"
        pane.send()
        let long = ["Friedman and Cochran (nonparametric two-way ANOVA) tests", "Chi-square 2-by-k test with user-defined scores for trend",
                    "Tests for signs of departure from normal distributions", "Two way hierarchical (nested) analysis of variance"]
        try await wait("The methods with long titles did not appear for the narrow checks") {
            !pane.isBusy && long.allSatisfy { title in button(title) != nil }
        }
        try await measure("methods", "the methods a reply names, with titles wider than the narrowest pane", "Choose a worksheet method")
        applySize("normal", dock: dock)
        try check(states.count == 11 && pictures.count >= 33 && abs(pane.view.frame.width - dock) < 0.5 && window.frame.size != window.minSize,
                  "pictures of the pane in the \(states.count) states, at the suite's size, in the narrowest pane and at the window's minimum size, are in "
                  + ".build/worksheet-ai-narrow (\(pictures.count) files), and the window and the pane are back at the suite's size")
    }
}

extension WorksheetAIHarness {
    /// Polls for up to two seconds, for what the pane does once the drawing in hand has been laid out.
    func settle(_ condition: () -> Bool) async {
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A pane too short for its controls (the window at its minimum size): with the pane at its top, where the conversation's
    /// controls are, a card drawn at its foot comes into view without the user scrolling, and so does the control the keyboard
    /// focus passes to, the offer's Continue at the top of the pane among them (Keyboard navigation on). Windows' conversation
    /// follows a card it adds; the Mac pane scrolls as a whole only when it is this short.
    func shortPane(_ cards: Document) async throws {
        let dock = pane.view.frame.width
        guard let scroller = pane.view.subviews.first as? NSScrollView, let content = scroller.documentView else {
            throw ChatGPTTutor.Failure(message: "The pane has no scroll view")
        }
        func top() { scroller.contentView.scroll(to: .zero); scroller.reflectScrolledClipView(scroller.contentView) }
        func inView(_ view: NSView?) -> Bool {
            guard let view, !view.isHiddenOrHasHiddenAncestor, view.window != nil else { return false }
            let clip = scroller.contentView
            return clip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(clip.convert(view.bounds, from: view))
        }
        func focused() -> NSButton? { viewer.window.firstResponder as? NSButton }
        keyboardNavigation(true)
        defer { keyboardNavigation(false); applySize("normal", dock: dock); top(); viewer.window.makeFirstResponder(pane.input) }
        applySize("minimum", dock: dock)
        // The paired card for more than 100 pairs is the tallest: drawn below the conversation, its choices lie below the pane's
        // foot while the pane is at its top.
        try await select(cards, "selectCells({x:6,y:0,width:2,height:103})", "Selection: Cards!G1:H103")
        top()
        viewer.window.makeFirstResponder(pane.input)
        pane.input.string = "PAIRED_A"
        pane.send()
        let large = try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "The paired card for G1:H103 did not appear in the short pane")
        guard let box: NSView = control("worksheet-ai-distribution", in: pane.view),
              let answer = views(WorksheetAIChoiceButton.self, in: box).first(where: { $0.choice == large.choices.first }) else {
            throw ChatGPTTutor.Failure(message: "The paired card for G1:H103 shows no choice")
        }
        let clip = scroller.contentView.bounds.height, whole = content.frame.height
        let foot = content.convert(answer.bounds, from: answer).maxY
        await settle { inView(answer) }
        try check(whole > clip + 50 && foot > clip && inView(answer),
                  "in a pane \(clip) points tall whose content is \(whole), the paired card drawn at its foot (its first choice to \(foot)) comes into view without "
                  + "scrolling; the card's choices are \(large.choices)")
        viewer.window.makeFirstResponder(answer)
        await space()
        _ = try await offered("Paired Student t test")
        let proceed: NSButton? = control("worksheet-ai-continue", in: pane.view)
        await settle { focused() === proceed && inView(proceed) }
        try check(focused() === proceed && inView(proceed),
                  "Space on the card's first choice (\(answer.choice)): the offer at the top of the pane comes into view with the focus on Continue")
        await tab(); await tab()
        await space()
        _ = try await waitCard("paired-interval", ["Local check found 101 complete pairs"], "Space on Change sample choice did not return to the card in the short pane")
        await settle { focusOnFirstChoice() && inView(focused()) }
        try check(pane.offer == nil && focusOnFirstChoice() && inView(focused()),
                  "Space on Change sample choice: the card comes back at the foot of the pane, its first choice in view with the focus")
        await space()
        _ = try await offered("Paired Student t test")
        await tab()
        await space()
        try await wait("Cancel did not bring back the general choices in the short pane") { pane.offer == nil && shown("worksheet-ai-help-choose") }
        await settle { focused() === pane.helpChoose && inView(pane.helpChoose) }
        try check(focused() === pane.helpChoose && inView(pane.helpChoose),
                  "Space on Cancel: Help me choose a method, the first of the general choices, has the focus and is in view")
    }

    /// Windows' Change design on the offer of a paired or unpaired t test that no card made (Learning/conversation.mjs:221-222,
    /// ScriptAIPane.WorksheetAnalysis.cs:266-276, :390-392), and its rule for a card's choices, Change sample choice, Change design
    /// and Continue, and a clarifying question's answers, while another document is in front of the card's workbook (:331-335): each
    /// is refused with Windows' notice, the card, question or offer kept; with the workbook in front again each is taken, and a card's
    /// choice clears the notice (:402).
    func designAndActivation(_ cards: Document, _ report: Document) async throws {
        keyboardNavigation(true)
        defer { keyboardNavigation(false); viewer.window.makeFirstResponder(pane.input) }
        func toReport() async throws {
            viewer.tabs.selectTabViewItem(report.item)
            try await wait("The report did not come in front of the card workbook") { viewer.active === report && pane.workbookID == cards.id }
        }
        func toCards() async throws {
            viewer.tabs.selectTabViewItem(cards.item)
            try await wait("The card workbook did not come back in front") { viewer.active === cards && pane.workbookID == cards.id }
        }
        func notice() -> String { label("worksheet-ai-notice") }
        try await select(cards, "selectCells({x:24,y:0,width:2,height:8})", "Selection: Cards!Y1:Z8")
        let quiet = dataTraffic()
        let activate = "Activate “" + label("worksheet-ai-workbook") + "” to continue this analysis."
        pane.prepareAnalysis("TPaired")
        _ = try await offered("Paired Student t test")
        let design: NSButton? = control("worksheet-ai-change-design", in: pane.view)
        let sample: NSButton? = control("worksheet-ai-change-sample", in: pane.view)
        try check(design?.title == "Change design" && design?.isHiddenOrHasHiddenAncestor == false && sample?.isHiddenOrHasHiddenAncestor == true,
                  "the paired t test offered without a card has Windows' Change design, not Change sample choice")

        try await toReport()
        let documents = viewer.documents.count
        design?.performClick(nil)
        let refusedDesign = notice()
        showNoticeCleared()
        pane.continueAnalysis()
        try await Task.sleep(for: .milliseconds(300))
        try check(refusedDesign == activate && notice() == activate && pane.offer?.methodTitle == "Paired Student t test" && card() == nil
                  && viewer.documents.count == documents && viewer.active === report,
                  "with a report in front of the workbook, Change design and Continue are each refused with Windows' notice “\(activate)” and the offer is kept")
        try await toCards()
        let designFocus: Bool = design.map { pressWithFocus($0) } ?? false
        let chosen = try await waitCard("choose", [chooseLine], "Change design did not go back to the study-design question")
        try check(pane.offer == nil && notice().isEmpty && chosen.choices == ["paired", "independent"],
                  "with the workbook in front, Change design goes back to the study-design question in the offer's place and clears the notice")
        try checkFocus(designFocus, focusOnFirstChoice(), "the keyboard focus on Change design moves to the study-design question's first answer")

        try await toReport()
        let token = chosen.token
        let paired = await pane.answerCard("paired", token: token)
        try check(!paired && notice() == activate && card()?.kind == "choose" && card()?.token == token,
                  "with the report in front, Same people or units is refused with Windows' notice and the question is kept with its token")
        try await toCards()
        try click("paired")
        let four = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Same people or units did not check Y1:Z8 with the workbook in front")
        try check(notice().isEmpty, "with the workbook in front, Same people or units is taken and clears the notice")

        try await toReport()
        let branch = await pane.answerCard("normal", token: four.token)
        let refusedBranch = notice()
        try await toCards()
        try check(!branch && refusedBranch == activate && pane.offer == nil && card()?.token == four.token,
                  "with the report in front, a branch is refused with Windows' notice, before its offer is prepared, and the card is kept")
        try click("normal")
        _ = try await offered("Paired Student t test")
        try check(notice().isEmpty && design?.isHiddenOrHasHiddenAncestor == true, "the branch's offer clears the notice and has no Change design")
        try await toReport()
        let wentBack = await pane.changeSample()
        try check(!wentBack && notice() == activate && pane.offer != nil, "with the report in front, Change sample choice is refused with Windows' notice and the offer is kept")
        try await toCards()
        sample?.performClick(nil)
        let returned = try await waitCard("paired-interval", ["Local check found 4 complete pairs."], "Change sample choice did not return with the workbook in front")
        try check(pane.offer == nil && notice().isEmpty, "with the workbook in front, Change sample choice returns to the card and clears the notice")
        try await toReport()
        let back = await pane.answerCard("back", token: returned.token)
        try check(!back && notice() == activate && card()?.kind == "paired-interval", "with the report in front, the card's Change design is refused with Windows' notice")
        try await toCards()
        try click("back")
        _ = try await waitCard("choose", [chooseLine], "The card's Change design did not go back with the workbook in front")
        try check(notice().isEmpty && dataTraffic() == quiet,
                  "with the workbook in front, the card's Change design goes back to the study-design question and clears the notice; nothing was sent")

        pane.prepareAnalysis("Wilcoxon")
        _ = try await offered("Wilcoxon signed ranks test")
        try check(design?.isHiddenOrHasHiddenAncestor == true && sample?.isHiddenOrHasHiddenAncestor == true,
                  "a method other than the paired or unpaired t test offered without a card has neither Change design nor Change sample choice")
        button("Cancel")?.performClick(nil)
        try await wait("Cancel did not end the Wilcoxon offer") { pane.offer == nil }

        pane.input.string = "CLARIFY_THEN_CARD_A"
        pane.send()
        try await wait("The clarifying question did not appear for the activation rule") { !pane.isBusy && pane.clarification != nil }
        let rows = await assistantRows()
        guard let box: NSView = control("worksheet-ai-clarification", in: pane.view), let option = views(WorksheetAIChoiceButton.self, in: box).first else {
            throw ChatGPTTutor.Failure(message: "The clarifying question shows no answer")
        }
        try await toReport()
        let sent = await pane.answerClarification(option.choice, token: option.token)
        try check(!sent && notice() == activate && pane.clarification != nil && !pane.isBusy,
                  "with the report in front, an answer to the clarifying question is refused with Windows' notice and the question is kept")
        try await toCards()
        let after = await assistantRows()
        try check(after == rows, "the refused answer sent nothing")
    }

    /// The notice line emptied by the test, so that the next refusal is seen on its own.
    func showNoticeCleared() { pane.showNotice("") }
}
