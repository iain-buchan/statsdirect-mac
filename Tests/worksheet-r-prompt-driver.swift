import Cocoa

/// The worksheet R import prompt (the shared worksheet R rules, section 1): its labels, and how its controls follow one
/// another. The prompt is built and clicked here but never shown, so this needs no window or focus.
@main
struct WorksheetRPromptDriver {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.prohibited)
        do { try run() } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
    }

    @MainActor static func run() throws {
        var passed = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw Failure(message: label) }
            passed += 1
            print("PASS \(label)")
        }
        func option(_ range: String, _ rows: Int, _ columns: Int, headings: Bool) -> WorksheetRImportPrompt.Option? {
            WorksheetRImportPrompt.Option(["range": range, "rowCount": rows, "columnCount": columns, "suggestHeadings": headings])
        }
        func choose(_ prompt: WorksheetRImportPrompt, format index: Int) {
            prompt.format.selectItem(at: index)
            prompt.format.sendAction(prompt.format.action, to: prompt.format.target)
        }

        let entire = option("A1:C4", 4, 3, headings: true), selected = option("B2:B3", 2, 1, headings: false)
        let r = WorksheetRImportPrompt(external: false, sheet: "Sheet1", entire: entire, selected: selected, selectedReason: nil)
        try check(r.alert.messageText == "Open in StatsDirect R"
                  && r.alert.informativeText == "Choose the data from “Sheet1” to copy into the new R session as worksheet_data.",
                  "R's prompt is titled as its button and names the sheet, the new session and worksheet_data")
        try check(r.entireButton.title == "Entire worksheet — A1:C4 (4 rows × 3 columns)"
                  && r.selectedButton.title == "Selected cells — B2:B3 (2 rows × 1 column)" && r.noneButton.title == "No data",
                  "the data choices give each range with its rows and columns")
        let arranged = (r.alert.accessoryView as? NSStackView)?.arrangedSubviews ?? []
        try check(arranged.count == 7 && arranged[0] === r.entireButton && arranged[1] === r.selectedButton && arranged[2] === r.noneButton
                  && arranged[4] === r.formatHint && arranged[5] === r.headings && arranged[6] === r.rFriendlyNames,
                  "the data choices, Import as, its hint and the two boxes come in the rules' order")
        try check(r.scope == .none && r.noneButton.state == .on && r.alert.window.initialFirstResponder === r.noneButton,
                  "No data is chosen, and has the focus, when the prompt opens")
        try check(r.format.itemTitles == ["Data frame (keep rows aligned)", "List of vectors (independent samples)"]
                  && r.format.indexOfSelectedItem == 0 && !r.format.isEnabled && r.formatHint.isHidden,
                  "Import as offers the data frame first, and is dimmed while No data is chosen")
        try check(r.headings.title == "Use the first row as column names" && !r.headings.isEnabled && r.headings.state == .off
                  && r.rFriendlyNames.title == "Use R-friendly names" && !r.rFriendlyNames.isEnabled && r.rFriendlyNames.state == .off,
                  "both boxes are dimmed and unticked when the prompt opens")
        try check(r.alert.buttons.map(\.title) == ["Open", "Cancel"] && r.alert.buttons[0].keyEquivalent == "\r"
                  && r.alert.buttons[1].keyEquivalent == "\u{1b}", "Open is the default button, and Cancel takes Escape")
        let controls: [NSControl] = [r.entireButton, r.selectedButton, r.noneButton, r.format, r.formatHint, r.headings, r.rFriendlyNames,
                                     r.alert.buttons[0], r.alert.buttons[1]]
        try check(controls.map { $0.accessibilityIdentifier() } == ["worksheet-r-entire", "worksheet-r-selected", "worksheet-r-none",
                  "worksheet-r-format", "worksheet-r-format-hint", "worksheet-r-headings", "worksheet-r-friendly-names",
                  "worksheet-r-open", "worksheet-r-cancel"], "every control keeps its accessibility identifier")
        var choice = r.selection
        try check(choice.scope == .none && !choice.headings && !choice.rFriendlyNames && !choice.asList, "No data asks for no import")

        r.entireButton.performClick(nil)
        try check(r.scope == .entire && r.format.isEnabled && r.headings.isEnabled && r.headings.state == .on
                  && r.rFriendlyNames.isEnabled && r.rFriendlyNames.state == .off,
                  "Entire worksheet enables the options and takes its heading suggestion")
        r.rFriendlyNames.performClick(nil)
        r.headings.performClick(nil)
        choice = r.selection
        try check(r.headings.state == .off && !r.rFriendlyNames.isEnabled && r.rFriendlyNames.state == .on && !choice.headings && !choice.rFriendlyNames,
                  "unticking the first box dims R-friendly names, which keep their tick but are not used")
        r.entireButton.performClick(nil)
        try check(r.headings.state == .off, "choosing the same data again keeps the user's first-box choice")
        r.headings.performClick(nil)
        choice = r.selection
        try check(r.rFriendlyNames.isEnabled && r.rFriendlyNames.state == .on && choice.headings && choice.rFriendlyNames,
                  "ticking the first box again brings back the user's R-friendly tick")
        r.selectedButton.performClick(nil)
        try check(r.scope == .selected && r.headings.isEnabled && r.headings.state == .off && !r.rFriendlyNames.isEnabled
                  && r.rFriendlyNames.state == .on, "a new data choice takes its own suggestion, and R-friendly names keep their tick while dimmed")
        let size = r.alert.accessoryView?.fittingSize
        choose(r, format: 1)
        try check(!r.formatHint.isHidden && r.formatHint.stringValue == "Missing values are removed separately from each vector." && r.selection.asList,
                  "List of vectors shows its hint")
        try check(r.alert.accessoryView?.fittingSize == size, "showing the hint leaves the prompt's size unchanged")
        choose(r, format: 0)
        try check(r.formatHint.isHidden && !r.selection.asList, "the data frame hides the hint")
        choose(r, format: 1)
        r.noneButton.performClick(nil)
        choice = r.selection
        try check(choice.scope == .none && !choice.asList && !choice.headings && !r.format.isEnabled && !r.headings.isEnabled
                  && r.headings.state == .off && !r.rFriendlyNames.isEnabled, "No data dims every option again and asks for no import")

        let oneRow = WorksheetRImportPrompt(external: false, sheet: "S", entire: option("A1:C1", 1, 3, headings: true), selected: nil,
                                            selectedReason: "none")
        oneRow.entireButton.performClick(nil)
        try check(!oneRow.headings.isEnabled && oneRow.headings.state == .off && !oneRow.selection.headings && oneRow.format.isEnabled,
                  "the first box stays dimmed for a single row")
        let plus = WorksheetRImportPrompt(external: true, sheet: "Sheet1", entire: entire, selected: nil, selectedReason: "shape")
        try check(plus.alert.messageText == "Open in R or RStudio"
                  && plus.alert.informativeText == "Choose the data from “Sheet1” to copy into R as worksheet_data.",
                  "R+ is titled Open in R or RStudio, and copies into R")
        try check(plus.selectedButton.title == "Selected cells (select one rectangle, or whole columns or rows)" && !plus.selectedButton.isEnabled,
                  "a selection of another shape is dimmed and says why")
        plus.selectedButton.performClick(nil)
        try check(plus.scope == .none && plus.noneButton.state == .on, "a dimmed choice cannot be chosen")
        let empty = WorksheetRImportPrompt(external: false, sheet: "Empty sheet", entire: nil, selected: nil, selectedReason: "empty")
        try check(empty.alert.informativeText == "The worksheet “Empty sheet” has no data to copy."
                  && empty.entireButton.title == "Entire worksheet (no data)" && !empty.entireButton.isEnabled
                  && empty.selectedButton.title == "Selected cells (no data in the selection)" && !empty.selectedButton.isEnabled,
                  "an empty worksheet says it has no data to copy, and both data choices are dimmed")
        let reasons: [String?] = ["none", nil, "something else"]
        try check(reasons.allSatisfy { WorksheetRImportPrompt.unavailableSelection($0) == "Selected cells (no selection)" },
                  "no selection is the reason when the grid gives no other")
        let counts = [(1, "row", "1 row"), (2, "row", "2 rows"), (999, "row", "999 rows"), (1000, "row", "1,000 rows"),
                      (1_048_576, "row", "1,048,576 rows"), (1, "column", "1 column"), (16_384, "column", "16,384 columns")]
        try check(counts.allSatisfy { WorksheetRImportPrompt.Option.count($0.0, $0.1) == $0.2 },
                  "counts are digits with commas, and singular for one")
        // Run with -AppleLocale de_DE, as the toolbar suite does, where the locale's own form would be 1.048.576.
        let largest = WorksheetRImportPrompt(external: false, sheet: "Sheet1", entire: option("A1:XFD1048576", 1_048_576, 16_384, headings: false),
                                             selected: nil, selectedReason: nil)
        try check(largest.entireButton.title == "Entire worksheet — A1:XFD1048576 (1,048,576 rows × 16,384 columns)",
                  "the largest worksheet's counts are digits with commas in the \(Locale.current.identifier) locale too")
        try check(WorksheetRImportPrompt.Option(["range": "A1", "rowCount": true, "columnCount": 1]) == nil
                  && WorksheetRImportPrompt.Option(["range": "A1", "rowCount": 0, "columnCount": 1]) == nil
                  && WorksheetRImportPrompt.Option(["range": " ", "rowCount": 1, "columnCount": 1]) == nil
                  && WorksheetRImportPrompt.Option(["range": "A1", "rowCount": 1.5, "columnCount": 1]) == nil
                  && WorksheetRImportPrompt.Option(["range": "A1", "rowCount": 2.0, "columnCount": 1])?.rowCount == 2,
                  "a data choice needs a range and positive whole counts")
        print("PASS \(passed) worksheet R prompt checks")
    }
}
