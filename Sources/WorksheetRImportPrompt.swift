import Cocoa

/// A worksheet import choice shared by the internal R console and an external R application
/// (the shared worksheet R rules, section 1).
@MainActor
final class WorksheetRImportPrompt: NSObject {
    struct Option {
        let range: String
        let rowCount: Int
        let columnCount: Int
        let suggestHeadings: Bool

        init?(_ object: [String: Any]?) {
            guard let object,
                  let range = object["range"] as? String,
                  !range.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rows = Self.positiveInteger(object["rowCount"]),
                  let columns = Self.positiveInteger(object["columnCount"]) else { return nil }
            self.range = range
            rowCount = rows
            columnCount = columns
            suggestHeadings = object["suggestHeadings"] as? Bool ?? false
        }

        private static func positiveInteger(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = Int(exactly: number.doubleValue), integer > 0 else { return nil }
            return integer
        }

        fileprivate var detail: String {
            "\(range) (\(Self.count(rowCount, "row")) × \(Self.count(columnCount, "column")))"
        }

        /// "1 row", "1,048,576 rows": digits with commas, whatever the user's locale (rule 1.4).
        static func count(_ value: Int, _ noun: String) -> String {
            var digits = String(value), groups = ""
            while digits.count > 3 { groups = "," + digits.suffix(3) + groups; digits.removeLast(3) }
            return digits + groups + " " + noun + (value == 1 ? "" : "s")
        }
    }

    enum Scope: String { case entire, selected, none }

    struct Selection {
        let scope: Scope
        let headings: Bool
        let rFriendlyNames: Bool
        let asList: Bool
    }

    let alert = NSAlert()
    let entireButton = NSButton(radioButtonWithTitle: "Entire worksheet", target: nil, action: nil)
    let selectedButton = NSButton(radioButtonWithTitle: "Selected cells", target: nil, action: nil)
    let noneButton = NSButton(radioButtonWithTitle: "No data", target: nil, action: nil)
    let format = NSPopUpButton(frame: .zero, pullsDown: false)
    let formatHint = NSTextField(labelWithString: "Missing values are removed separately from each vector.")
    let headings = NSButton(checkboxWithTitle: "Use the first row as column names", target: nil, action: nil)
    let rFriendlyNames = NSButton(checkboxWithTitle: "Use R-friendly names", target: nil, action: nil)
    private let formatLabel = NSTextField(labelWithString: "Import as:")
    private let entire: Option?
    private let selected: Option?
    private var completion: ((Selection?) -> Void)?
    private(set) var scope: Scope = .none

    static func present(on window: NSWindow, external: Bool, sheet: String, entire: Option?, selected: Option?,
                        selectedReason: String?, completion: @escaping (Selection?) -> Void) {
        let prompt = WorksheetRImportPrompt(external: external, sheet: sheet, entire: entire, selected: selected,
                                            selectedReason: selectedReason)
        prompt.completion = completion
        prompt.alert.beginSheetModal(for: window) { [prompt] response in
            let callback = prompt.completion
            prompt.completion = nil
            callback?(response == .alertFirstButtonReturn ? prompt.selection : nil)
        }
    }

    /// Why Selected cells cannot be chosen, from the grid's `selectedReason` (rule 1.5).
    static func unavailableSelection(_ reason: String?) -> String {
        switch reason {
        case "shape": return "Selected cells (select one rectangle, or whole columns or rows)"
        case "empty": return "Selected cells (no data in the selection)"
        default: return "Selected cells (no selection)"
        }
    }

    init(external: Bool, sheet: String, entire: Option?, selected: Option?, selectedReason: String?) {
        self.entire = entire
        self.selected = selected
        super.init()
        alert.messageText = external ? "Open in R or RStudio" : "Open in StatsDirect R"
        // RStudio opens the script in the user's own session, so R+ does not promise a new one (rule 1.2).
        alert.informativeText = entire == nil && selected == nil ? "The worksheet “\(sheet)” has no data to copy."
            : "Choose the data from “\(sheet)” to copy into \(external ? "R" : "the new R session") as worksheet_data."
        alert.alertStyle = .informational
        alert.window.identifier = NSUserInterfaceItemIdentifier("worksheet-r-import")
        let open = alert.addButton(withTitle: "Open")
        open.identifier = NSUserInterfaceItemIdentifier("worksheet-r-open")
        open.setAccessibilityIdentifier("worksheet-r-open")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.identifier = NSUserInterfaceItemIdentifier("worksheet-r-cancel")
        cancel.setAccessibilityIdentifier("worksheet-r-cancel")
        cancel.keyEquivalent = "\u{1b}"

        for (button, id, value) in [(entireButton, "worksheet-r-entire", Scope.entire),
                                    (selectedButton, "worksheet-r-selected", Scope.selected),
                                    (noneButton, "worksheet-r-none", Scope.none)] {
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setAccessibilityIdentifier(id)
            button.target = self
            button.action = #selector(scopeChanged(_:))
            button.tag = value == .entire ? 0 : value == .selected ? 1 : 2
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        entireButton.title = entire.map { "Entire worksheet — \($0.detail)" } ?? "Entire worksheet (no data)"
        selectedButton.title = selected.map { "Selected cells — \($0.detail)" } ?? Self.unavailableSelection(selectedReason)
        entireButton.isEnabled = entire != nil
        selectedButton.isEnabled = selected != nil
        noneButton.state = .on

        format.addItems(withTitles: ["Data frame (keep rows aligned)", "List of vectors (independent samples)"])
        format.identifier = NSUserInterfaceItemIdentifier("worksheet-r-format")
        format.setAccessibilityIdentifier("worksheet-r-format")
        format.setAccessibilityLabel("Import data as")
        format.setAccessibilityHelp("Choose a data frame or a named list containing one vector per worksheet column.")
        format.selectItem(at: 0)
        format.target = self
        format.action = #selector(formatChanged(_:))
        let formatRow = NSStackView(views: [formatLabel, format])
        formatRow.spacing = 8
        formatHint.identifier = NSUserInterfaceItemIdentifier("worksheet-r-format-hint")
        formatHint.setAccessibilityIdentifier("worksheet-r-format-hint")
        formatHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for (button, id) in [(headings, "worksheet-r-headings"), (rFriendlyNames, "worksheet-r-friendly-names")] {
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setAccessibilityIdentifier(id)
        }
        headings.target = self
        headings.action = #selector(headingsChanged(_:))
        headings.setAccessibilityHelp("The first row becomes the column names and is excluded from the data.")
        rFriendlyNames.setAccessibilityHelp("Replace spaces with underscores and make the names valid and unique in R.")
        rFriendlyNames.state = .off

        let stack = NSStackView(views: [entireButton, selectedButton, noneButton, formatRow, formatHint, headings, rFriendlyNames])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        // The hint keeps its line while hidden, so the open sheet never changes size.
        stack.detachesHiddenViews = false
        stack.setCustomSpacing(18, after: noneButton)
        stack.setCustomSpacing(4, after: formatRow)
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 540).isActive = true
        format.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        alert.accessoryView = stack
        updateControls(resetHeadings: true)
        alert.layout()
        alert.window.initialFirstResponder = noneButton
    }

    var selection: Selection {
        let hasData = scope != .none
        let useHeadings = hasData && headings.isEnabled && headings.state == .on
        return Selection(scope: scope, headings: useHeadings,
                         rFriendlyNames: useHeadings && rFriendlyNames.state == .on,
                         asList: hasData && format.indexOfSelectedItem == 1)
    }

    @objc private func scopeChanged(_ sender: NSButton) {
        let chosen: Scope = sender === entireButton ? .entire : sender === selectedButton ? .selected : .none
        guard sender.isEnabled, chosen != scope else { updateControls(resetHeadings: false); return }
        scope = chosen
        updateControls(resetHeadings: true)
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        updateControls(resetHeadings: false)
    }

    @objc private func headingsChanged(_ sender: NSButton) {
        updateControls(resetHeadings: false)
    }

    private func updateControls(resetHeadings: Bool) {
        entireButton.state = scope == .entire ? .on : .off
        selectedButton.state = scope == .selected ? .on : .off
        noneButton.state = scope == .none ? .on : .off
        let option = scope == .entire ? entire : scope == .selected ? selected : nil
        format.isEnabled = option != nil
        formatLabel.textColor = option == nil ? .disabledControlTextColor : .labelColor
        formatHint.isHidden = format.indexOfSelectedItem != 1
        formatHint.textColor = option == nil ? .disabledControlTextColor : .secondaryLabelColor
        // The first box takes the suggestion each time the data choice changes (rule 1.7). The R-friendly box keeps
        // the user's own tick while the prompt is open; while the first box is unticked it is dimmed and not used.
        headings.isEnabled = (option?.rowCount ?? 0) > 1
        if resetHeadings { headings.state = headings.isEnabled && option?.suggestHeadings == true ? .on : .off }
        rFriendlyNames.isEnabled = headings.isEnabled && headings.state == .on
    }
}
