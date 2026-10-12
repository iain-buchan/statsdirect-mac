import Cocoa
import WebKit

// Find and replace in a report, as the Windows report window offers it (its FindBar and ReportView): a bar above the report's
// page, hidden until Edit > Find… or Replace… shows it, whose searches the page answers through the same scripts as the Windows
// view runs, so a term is found, the selected match replaced and every match replaced alike on both sides. Replacing through
// the editor's insertText keeps the report's undo history, as the Windows report relies on.
final class ReportFindBar: NSView, NSSearchFieldDelegate {
    private(set) weak var document: Document?
    let term = NSSearchField()
    let replacement = NSTextField()
    let matchCase = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)
    // The result of the last search or replacement, as the Windows bar reports it: not found, or how many were replaced.
    let outcome = NSTextField(labelWithString: "")
    private var viewer: Viewer? { NSApp.delegate as? Viewer }
    // Whether the keyboard is in the bar, so the Edit menu's clipboard and undo commands go to its fields, not the report.
    var isFocused: Bool { !isHidden && (window?.firstResponder as? NSView)?.isDescendant(of: self) == true }

    init(document: Document) {
        self.document = document
        super.init(frame: .zero)
        setAccessibilityIdentifier("report-find-bar"); setAccessibilityLabel("Find and replace")
        term.placeholderString = "Find"; term.setAccessibilityLabel("Find"); term.delegate = self
        replacement.placeholderString = "Replace with"; replacement.setAccessibilityLabel("Replace with"); replacement.delegate = self
        outcome.font = .systemFont(ofSize: 11); outcome.textColor = .secondaryLabelColor; outcome.lineBreakMode = .byTruncatingTail
        func button(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
            let button = NSButton(title: title, target: self, action: action); button.toolTip = tip; return button
        }
        let find = row([term, matchCase, button("Find Next", #selector(findNext), "Select the next match (Return; Shift-Return for the previous)"), outcome, button("Done", #selector(close), "Close the find bar (Escape)")])
        let replace = row([replacement, button("Replace", #selector(replaceSelection), "Replace the selected match and find the next (Return)"), button("Replace All", #selector(replaceAll), "Replace every match in the report"), NSView()])
        for field in [term, replacement] { field.widthAnchor.constraint(equalToConstant: 220).isActive = true }
        for view in [find.arrangedSubviews, replace.arrangedSubviews].joined() { view.setContentHuggingPriority(.defaultHigh, for: .horizontal) }
        // The outcome and the spacer take the width the controls leave, so Done sits at the right end.
        for view in [outcome, replace.arrangedSubviews.last!] { view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal) }
        outcome.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let rows = NSStackView(views: [find, replace])
        rows.orientation = .vertical; rows.alignment = .width; rows.spacing = 4
        rows.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        let separator = NSBox(); separator.boxType = .separator
        for view in [rows, separator] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor), rows.leadingAnchor.constraint(equalTo: leadingAnchor), rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: rows.bottomAnchor), separator.leadingAnchor.constraint(equalTo: leadingAnchor), separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        row.setClippingResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    // Opens the bar with the keyboard in the term (or the replacement), the find pasteboard's string as the term when there is none yet.
    func open(replace: Bool) {
        isHidden = false; outcome.stringValue = ""
        if term.stringValue.isEmpty, let shared = NSPasteboard(name: .find).string(forType: .string), !shared.isEmpty { term.stringValue = shared }
        (replace ? replacement : term).selectText(nil)
    }
    // Hides the bar and gives the keyboard back to the report.
    @objc func close() {
        guard !isHidden else { return }
        let host = window
        isHidden = true; outcome.stringValue = ""
        if let document { host?.makeFirstResponder(document.web) }
    }
    override func cancelOperation(_ sender: Any?) { close() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            if control === replacement { replaceSelection() } else { find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true) }
            return true
        }
        return false
    }

    @objc func findNext() { find(backwards: false) }
    func find(backwards: Bool) {
        guard let document, let viewer, !term.stringValue.isEmpty else { return }
        let term = self.term.stringValue, matchCase = matchCase.state == .on
        Task { @MainActor in
            do {
                let found = try await viewer.reportFindNext(document, term: term, matchCase: matchCase, backwards: backwards)
                outcome.stringValue = found ? "" : "Not found: \(term)"
            } catch { outcome.stringValue = error.localizedDescription }
        }
    }
    // Replaces the match found last, then finds the next, as the Windows bar does. Replacing is editing: a report that is not
    // being edited is put into editing first, as Add text does.
    @objc func replaceSelection() {
        guard let document, let viewer, !term.stringValue.isEmpty else { return }
        let term = self.term.stringValue, replacement = self.replacement.stringValue, matchCase = matchCase.state == .on
        Task { @MainActor in
            do {
                try await viewer.beginReportEditing(document)
                _ = try await viewer.reportReplaceSelection(document, term: term, replacement: replacement, matchCase: matchCase)
                let found = try await viewer.reportFindNext(document, term: term, matchCase: matchCase)
                outcome.stringValue = found ? "" : "Not found: \(term)"
            } catch { outcome.stringValue = error.localizedDescription }
        }
    }
    @objc func replaceAll() {
        guard let document, let viewer, !term.stringValue.isEmpty else { return }
        let term = self.term.stringValue, replacement = self.replacement.stringValue, matchCase = matchCase.state == .on
        Task { @MainActor in
            do {
                try await viewer.beginReportEditing(document)
                let count = try await viewer.reportReplaceAll(document, term: term, replacement: replacement, matchCase: matchCase)
                outcome.stringValue = count == 0 ? "Not found: \(term)" : "\(count) replaced"
            } catch { outcome.stringValue = error.localizedDescription }
        }
    }
}

extension Document {
    // The report's page with its find bar above it, in one column; the bar is detached while hidden, so the page has the whole height.
    func reportFindHost() -> NSView {
        let bar = ReportFindBar(document: self); bar.isHidden = true; findBar = bar
        let column = NSStackView(views: [bar, web])
        column.orientation = .vertical; column.alignment = .width; column.spacing = 0; column.distribution = .fill
        column.translatesAutoresizingMaskIntoConstraints = true; column.autoresizingMask = [.width, .height]
        bar.setContentHuggingPriority(.defaultHigh, for: .vertical); web.setContentHuggingPriority(.defaultLow, for: .vertical)
        return column
    }
}

extension Viewer {
    // The report the Edit menu's find items serve: the active document when it is a report that has loaded and is not under a sheet.
    var findableReport: Document? {
        guard !calculatorPane.isFocused, !helpPane.isFocused, let doc = active, doc.kind == "report", !doc.web.isLoading, window.attachedSheet == nil else { return nil }
        return doc
    }
    func isReportFindItem(_ item: NSMenuItem) -> Bool {
        [#selector(showReportFind), #selector(showReportReplace), #selector(findReportNext), #selector(findReportPrevious), #selector(useReportSelectionForFind)].contains(item.action)
    }
    var findableDocument: Document? {
        guard !calculatorPane.isFocused, !helpPane.isFocused, !scriptAI.isFocused,
              let doc = active, ["report", "grid", "r"].contains(doc.kind), window.attachedSheet == nil,
              doc.kind == "r" || !doc.web.isLoading else { return nil }
        return doc
    }
    @objc func showReportFind() {
        guard let doc = findableDocument else { return }
        if let pane = doc.rPane { pane.showFind() }
        else if doc.kind == "grid" { doc.web.evaluateJavaScript("window.statsDirectGrid.showFind()") }
        else { showFindBar(doc, replace: false) }
    }
    @objc func showReportReplace() { if let doc = findableReport { showFindBar(doc, replace: true) } }
    @objc func findReportNext() { findReportAgain(backwards: false) }
    @objc func findReportPrevious() { findReportAgain(backwards: true) }
    // The report's selected text as the term, and on the find pasteboard as other applications share it.
    @objc func useReportSelectionForFind() {
        guard let doc = findableReport else { return }
        Task { @MainActor in
            guard let text = try? await doc.web.evaluateJavaScript("getSelection().toString()") as? String, !text.isEmpty else { return }
            let pasteboard = NSPasteboard(name: .find); pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
            doc.findBar?.term.stringValue = text
        }
    }
    func showFindBar(_ doc: Document, replace: Bool) { doc.findBar?.open(replace: replace) }
    func hideFindBar(_ doc: Document) { doc.findBar?.close() }
    private func findReportAgain(backwards: Bool) {
        guard let doc = findableReport, let bar = doc.findBar else { return }
        if bar.term.stringValue.isEmpty { bar.open(replace: false) } else { bar.find(backwards: backwards) }
    }
    // Editing on before a replacement, as the editor's own commands need it; the editor reports the change back (editing message).
    func beginReportEditing(_ doc: Document) async throws {
        guard !doc.reportEditing else { return }
        _ = try await doc.web.evaluateJavaScript("(() => { StatsDirectReportEditor.setEditing(true); return true; })()")
        doc.reportEditing = true
    }

    // The searches, with exactly the scripts the Windows report view runs (ReportView.FindNextAsync, ReplaceSelectionAsync and
    // ReplaceAllAsync), so a term is found, the selected match replaced and every match replaced alike on both sides.
    // The next match after the selection, round to the start of the report (or backwards, round to the end); the match is selected.
    func reportFindNext(_ doc: Document, term: String, matchCase: Bool, backwards: Bool = false) async throws -> Bool {
        guard !term.isEmpty else { return false }
        return try await doc.web.evaluateJavaScript("window.find(\(jsString(term)), \(matchCase), \(backwards), true, false, false, false)") as? Bool ?? false
    }
    // Replaces the selection when it is the term; false when it is not, or cannot be edited.
    func reportReplaceSelection(_ doc: Document, term: String, replacement: String, matchCase: Bool) async throws -> Bool {
        guard !term.isEmpty else { return false }
        let same = matchCase ? "t === \(jsString(term))" : "t.toLowerCase() === \(jsString(term)).toLowerCase()"
        return try await doc.web.evaluateJavaScript("(() => { const t = getSelection().toString(); if (!t || !(\(same))) return false; return document.execCommand('insertText', false, \(jsString(replacement))); })()") as? Bool ?? false
    }
    // Replaces every match from the start of the report; the number replaced.
    func reportReplaceAll(_ doc: Document, term: String, replacement: String, matchCase: Bool) async throws -> Int {
        guard !term.isEmpty else { return 0 }
        let script = "(() => { const s = getSelection(), r = document.createRange(); r.setStart(document.body, 0); r.collapse(true); s.removeAllRanges(); s.addRange(r); let n = 0; "
            + "while (n < 100000 && window.find(\(jsString(term)), \(matchCase), false, false, false, false, false)) { if (!document.execCommand('insertText', false, \(jsString(replacement)))) break; n++; } return n; })()"
        return try await doc.web.evaluateJavaScript(script) as? Int ?? 0
    }
}
