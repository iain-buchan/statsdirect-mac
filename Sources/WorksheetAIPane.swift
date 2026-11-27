import Cocoa

/// What the grid page tells AI Assist about a workbook: the active sheet, its selection as an A1 address, whether the
/// workbook holds anything and whether row 1 holds the column names. It stays in the app; nothing here is sent to the
/// provider.
struct WorksheetAIState: Equatable {
    let sheet: Int
    let sheetName: String
    let label: String
    let singleCell: Bool
    let hasData: Bool
    /// "First row has column names": it changes what a distribution card reads, so a change is a new state.
    let headerRow: Bool

    init(sheet: Int, sheetName: String, label: String, singleCell: Bool, hasData: Bool, headerRow: Bool) {
        self.sheet = sheet; self.sheetName = sheetName; self.label = label; self.singleCell = singleCell; self.hasData = hasData
        self.headerRow = headerRow
    }

    /// The page's message or bridge result, checked as GridHost checks every grid message.
    init?(_ body: [String: Any]) {
        guard let sheet = body["sheet"] as? Int, let name = body["sheetName"] as? String, name.count <= 256,
              let label = body["label"] as? String, label.count <= 200,
              let single = body["singleCell"] as? Bool, let hasData = body["hasData"] as? Bool,
              let headerRow = body["headerRow"] as? Bool else { return nil }
        self.init(sheet: sheet, sheetName: name, label: label, singleCell: single, hasData: hasData, headerRow: headerRow)
    }

    /// "Selection: Sheet 1!A1:B20" or "Current cell: Sheet 1!B3", as the Windows pane writes it; nil when nothing is selected.
    var caption: String? {
        label.isEmpty ? nil : (singleCell ? "Current cell: " : "Selection: ") + sheetName + "!" + label
    }
}

/// A clarifying question with fixed answers, offered by the assistant through a local tool when the goal, the outcome
/// scale or the study design is unclear. The wording matches the Windows card; choosing an answer sends its sentence.
struct WorksheetAIClarification: Equatable {
    struct Option: Equatable { let id: String; let label: String; let answer: String }
    let dimension: String
    let question: String
    let options: [Option]

    static let tool = "statsdirect_clarify_worksheet_analysis"
    static var definition: [String: Any] {
        TutorTools.tool(tool, "Show a fixed set of clickable answers for the next missing detail: goal, outcome scale or study design. Wait for the user's answer before suggesting a method. Does not inspect the worksheet or run an analysis.",
                        ["dimension": ["type": "string", "enum": ["goal", "scale", "design"]]], required: ["dimension"])
    }

    static func make(_ dimension: String) -> WorksheetAIClarification? {
        switch dimension {
        case "goal":
            return .init(dimension: dimension, question: "What would you like to find out?", options: [
                .init(id: "means", label: "Compare means", answer: "I want to compare means."),
                .init(id: "ordered", label: "Compare ordered scores", answer: "I want to compare ordered scores or relative ordering."),
                .init(id: "proportions", label: "Compare proportions", answer: "I want to compare proportions."),
                .init(id: "association", label: "Assess association", answer: "I want to assess an association between variables."),
                .init(id: "agreement", label: "Assess agreement", answer: "I want to assess agreement between measurements."),
                .init(id: "unsure", label: "I’m not sure", answer: "I am not sure what comparison best answers my question. Help me work it out.")])
        case "scale":
            return .init(dimension: dimension, question: "How was the outcome measured?", options: [
                .init(id: "quantitative", label: "Numeric measurement", answer: "My outcome is a quantitative measurement."),
                .init(id: "ordinal", label: "Ordered score or category", answer: "My outcome is an ordered score or category."),
                .init(id: "binary", label: "Two categories", answer: "My outcome has two categories."),
                .init(id: "nominal", label: "Unordered categories", answer: "My outcome has more than two unordered categories."),
                .init(id: "unsure", label: "I’m not sure", answer: "I am not sure of the outcome scale. Help me identify it.")])
        case "design":
            return .init(dimension: dimension, question: "How were the observations collected?", options: [
                .init(id: "paired", label: "Matched observations", answer: "The measurements are matched on the same people or units."),
                .init(id: "independent", label: "Separate groups", answer: "The observations come from separate, independent groups."),
                .init(id: "repeated", label: "Repeated or grouped observations", answer: "The observations are repeated over more than two occasions or grouped within clusters. Ask which applies if needed."),
                .init(id: "unsure", label: "I’m not sure", answer: "I am not sure how the observations are related. Help me identify the study design.")])
        default: return nil
        }
    }
}

/// The distribution decision cards of Windows 5.3.22, offered by the assistant through a local tool: the study-design
/// question, then the card for paired or independent interval measurements, which checks the two selected columns on
/// this Mac. The engine computes every line of a check (statsdirect_measurement_check); the fixed wording is the Windows
/// cards' (Learning/conversation.mjs). Nothing on a card is sent to the provider.
struct WorksheetAIDistribution {
    enum Kind: String { case choose, paired = "paired-interval", independent = "independent-interval" }

    /// The engine's card for the selection as the grid read it, or for no reading when it could not be read.
    struct Check {
        let sizeKnown: Bool
        let canCheck: Bool
        let largeSample: Bool?
        let diagnostics: [String]
        let suggestedBranch: String?
        let recommendation: String?
        /// Each branch's operation and Windows' advice for it; the feedback for a branch of the other size.
        let methods: [String: String]
        let advice: [String: String]
        let conflict: String?

        init?(_ reply: [String: Any], kind: Kind) {
            guard reply["kind"] as? String == kind.rawValue, let sizeKnown = reply["sizeKnown"] as? Bool,
                  let canCheck = reply["canCheck"] as? Bool, let methods = reply["methods"] as? [String: String],
                  let advice = reply["advice"] as? [String: String] else { return nil }
            self.sizeKnown = sizeKnown; self.canCheck = canCheck; self.methods = methods; self.advice = advice
            largeSample = reply["largeSample"] as? Bool
            diagnostics = reply["diagnostics"] as? [String] ?? []
            suggestedBranch = reply["suggestedBranch"] as? String
            recommendation = reply["recommendation"] as? String
            conflict = reply["conflict"] as? String
        }
    }

    let kind: Kind
    var check: Check?
    var feedback: String?

    init(kind: Kind, check: Check? = nil) { self.kind = kind; self.check = check }

    static let tool = "statsdirect_choose_worksheet_t_test"
    static var definition: [String: Any] {
        TutorTools.tool(tool, "Open the Help decision tree for a quantitative comparison. Omit design when the study design is unclear. Use paired for matched pairs and independent for two independent samples. The card considers the relevant counts and distributions locally. This tool shares no diagnostic data and runs no analysis.",
                        ["design": ["type": "string", "enum": ["paired", "independent"]]])
    }

    /// Windows' aria label for the card, which the pane's choices take while it is shown.
    var accessibilityLabel: String {
        switch kind {
        case .choose: return "Study design"
        case .paired: return "Paired interval measurements"
        case .independent: return "Independent interval measurements"
        }
    }

    var question: String? { kind == .choose ? "Were these measurements taken from the same people or units?" : nil }

    /// The paragraphs before the recommendation, in Windows' order: the check's lines, the question for a size not yet
    /// known, and, when the check makes no recommendation, the questions about the distribution.
    var lines: [String] {
        guard kind != .choose, let check else { return [] }
        let paired = kind == .paired
        var lines = check.diagnostics
        if !check.sizeKnown && check.diagnostics.isEmpty {
            lines.append(paired ? "How many complete pairs are there?" : "How many observations are there in each group?")
        }
        if check.recommendation == nil {
            lines.append(paired ? "How are the within-pair differences distributed?" : "How are the observations distributed within each group?")
            lines.append("Look at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive.")
        }
        return lines
    }

    /// The choices in Windows' order, with their titles; the suggested branch's title begins "Suggested · ".
    var buttons: [(choice: String, title: String)] {
        guard kind != .choose else { return [("paired", "Same people or units"), ("independent", "Separate groups")] }
        guard let check else { return [] }
        let paired = kind == .paired
        var buttons: [(choice: String, title: String)] = []
        if check.canCheck {
            buttons.append(("check", paired ? "Check selected pairs" : check.diagnostics.isEmpty ? "Check two sample columns" : "Use these as separate samples"))
        }
        buttons += [("large", paired ? "Large sample (more than 100 complete pairs)" : "Large samples (more than 100 in each group)"),
                    ("normal", paired ? "Small or medium · Approximately normal differences" : "Small or medium · Approximately normal within groups"),
                    ("non-normal", paired ? "Non-normal differences" : "Non-normal distributions within groups"),
                    ("back", "Change design")]
        return buttons.map { $0.choice == check.suggestedBranch ? (choice: $0.choice, title: "Suggested · " + $0.title) : $0 }
    }
}

/// An answer button on the clarification or distribution card. It belongs to the card it was drawn for: a selection
/// change, an edit or a new card retires the token, so a click that arrives late is refused rather than sent.
final class WorksheetAIChoiceButton: NSButton {
    var token = ""
    var choice = ""
    /// A distribution card's button wraps its title to the width it is given instead of widening the pane.
    var wrapsTitle = false {
        didSet {
            guard wrapsTitle else { return }
            bezelStyle = .flexiblePush
            cell?.wraps = true
            cell?.lineBreakMode = .byWordWrapping
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    /// Narrower than its title, the button is as tall as its title wrapped to its width.
    override var intrinsicContentSize: NSSize {
        let natural = super.intrinsicContentSize
        guard wrapsTitle, let cell, frame.width > 0, frame.width < natural.width else { return natural }
        return NSSize(width: natural.width, height: cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: frame.width, height: 10_000)).height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize.width != frame.width
        super.setFrameSize(newSize)
        if wrapsTitle && resized { invalidateIntrinsicContentSize() }
    }
}

/// Worksheet conversations and consent are scoped to a document ID. A running
/// request owns its original conversation even while the user changes tabs.
@MainActor final class WorksheetAIPane: NSObject {
    private final class Conversation {
        var generation = UUID().uuidString
        var messages: [[String: String]] = []
        var draft = ""
        var share = false
        var confirmed = false
    }
    /// What one question staged through its tools, one card at most, as on Windows; shown only if its reply completes.
    private final class RequestState {
        var clarification: WorksheetAIClarification?
        var distribution: WorksheetAIDistribution.Kind?
        var waiting: Bool { clarification != nil || distribution != nil }
    }
    /// The distribution card a method offer was chosen from: the branch, the selection the card was read for and the
    /// token it was drawn with. Change sample choice returns to it; any other end of the offer retires it.
    private struct OfferOrigin {
        let card: WorksheetAIDistribution
        let workbookID: String
        let fingerprint: String
        let token: String
        let branch: String
    }
    /// A distribution card's reading of the live selection, or the text to show the user instead.
    private enum CardRead {
        case read(WorksheetAIDistribution.Check, fingerprint: String?)
        case refused(String)
    }

    static let guidanceQuestion = "Help me choose a statistical method."
    static let stoppedBeforeText = "[Reply stopped before any text.]"
    static let noReply = "[No reply was received.]"

    unowned let viewer: Viewer
    let view = NSView()
    let transcript: AIConversationView
    let input = AIComposerInput()
    let share = NSButton(checkboxWithTitle: "Share workbook data", target: nil, action: nil)
    let confirm = NSButton(checkboxWithTitle: "I have checked for person-identifiable data.", target: nil, action: nil)
    let sendButton = NSButton(title: "Send question only", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    let replyActivity = NSTextField(labelWithString: "Reply in progress…")
    let selectionLabel = NSTextField(wrappingLabelWithString: "")
    let chooseMethod = NSButton(title: "Choose a method", target: nil, action: nil)
    let helpChoose = NSButton(title: "Help me choose a method", target: nil, action: nil)
    let openExample = NSButton(title: "Open example workbook", target: nil, action: nil)
    let workbookHelp = NSButton(title: "Workbook help", target: nil, action: nil)
    let guidance = NSStackView()
    private let emptyRow = NSStackView()
    private let compareRow = NSStackView()
    private let clarifyBox = NSStackView()
    private let distributionBox = NSStackView()
    private let connection = NSButton(title: "Use my ChatGPT", target: nil, action: nil)
    private let workbookLabel = NSTextField(wrappingLabelWithString: "")
    let sharingButton = NSButton(title: "Sharing options", target: nil, action: nil)
    private let sharingPanel = NSStackView()
    private let questionOnlyHint = NSTextField(wrappingLabelWithString: "Include the full question each time. Earlier messages aren’t sent.")
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let methods = NSStackView()
    private let offerLabel = NSTextField(wrappingLabelWithString: "")
    private let offerDetails = NSTextField(wrappingLabelWithString: "")
    private let changeSample = NSButton(title: "Change sample choice", target: nil, action: nil)
    private let offerPanel = NSStackView()
    private let openCode = NSButton(title: "Open in R", target: nil, action: nil)
    private var conversations: [String: Conversation] = [:]
    private(set) var workbookID: String?
    private var pendingWorkbookID: String?
    private var requestID: UUID?
    private var task: Task<Void, Never>?
    private var stopRequested = false
    private var partial = ""
    private(set) var offer: WorksheetAIAnalysisOffer?
    private var offerTask: Task<Void, Never>?
    /// The clarification card shown below the conversation, and the workbook whose conversation asked it.
    private(set) var clarification: (card: WorksheetAIClarification, workbookID: String)?
    /// The distribution card shown below the conversation, and its workbook. An interval card is drawn once the
    /// selection has been read for it.
    private(set) var distribution: (card: WorksheetAIDistribution, workbookID: String)?
    private var offerOrigin: OfferOrigin?
    /// The token every answer button of the current card carries.
    private(set) var guidanceToken = UUID().uuidString
    /// The exact selection, sheet and revisions the current token was issued for (worksheetAISelection, as JSON). A click
    /// is accepted only while the live grid still matches it; until it has been read, clicks are refused.
    private(set) var guidanceFingerprint: String?
    private var renderedEmpty = false
    private var expanded = true
    private(set) var visible = false
    private var width: CGFloat = 460

    private var conversation: Conversation? { workbookID.flatMap { conversations[$0] } }
    private var workbook: Document? { viewer.documents.first { $0.id == workbookID && $0.kind == "grid" } }
    var isBusy: Bool { task != nil }
    var isFocused: Bool {
        visible && (viewer.window.firstResponder as? NSView)?.isDescendant(of: view) == true
    }

    init(viewer: Viewer) {
        self.viewer = viewer
        transcript = AIConversationView(root: viewer.root)
        super.init()

        let label = NSTextField(labelWithString: "AI Assist")
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let close = NSButton(title: "Close", target: self, action: #selector(hide))
        let fresh = NSButton(title: "New conversation", target: self, action: #selector(newConversation))
        let header = NSStackView(views: [label, NSView(), fresh, close])
        label.setContentHuggingPriority(.required, for: .horizontal)
        workbookLabel.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-workbook")
        selectionLabel.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-selection")
        selectionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        selectionLabel.textColor = .secondaryLabelColor
        selectionLabel.isHidden = true
        let warning = NSTextField(wrappingLabelWithString: "Share the named workbook with ChatGPT only after removing names, dates of birth, patient IDs and identifying free text.")
        warning.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for control in [warning, share, confirm] { sharingPanel.addArrangedSubview(control) }
        sharingPanel.orientation = .vertical
        sharingPanel.alignment = .leading
        sharingPanel.spacing = 5
        sharingPanel.detachesHiddenViews = true

        let composer = NSScrollView()
        composer.hasVerticalScroller = true
        composer.borderType = .bezelBorder
        composer.documentView = input
        input.isRichText = false
        input.importsGraphics = false
        input.font = .systemFont(ofSize: 13)
        input.textContainerInset = NSSize(width: 5, height: 5)
        input.isVerticallyResizable = true
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.setAccessibilityLabel("Your worksheet question")
        input.send = { [weak self] in self?.send() }
        replyActivity.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-reply-activity")
        replyActivity.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        replyActivity.textColor = .secondaryLabelColor
        replyActivity.isHidden = true
        // In a narrow dock the indicator gives way to the buttons rather than widening the row.
        replyActivity.lineBreakMode = .byTruncatingTail
        replyActivity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [sendButton, stopButton, replyActivity])
        actions.detachesHiddenViews = true
        let proceed = NSButton(title: "Continue", target: self, action: #selector(continueAnalysis))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAnalysis))
        proceed.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-continue")
        offerLabel.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-confirmation")
        // A method chosen on a distribution card also shows the card's check and Windows' advice for the branch, with the
        // way back to the card on a row of its own, so a narrow dock is not widened.
        offerDetails.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-offer-details")
        changeSample.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-change-sample")
        changeSample.target = self; changeSample.action = #selector(changeSampleChoice)
        let offerActions = NSStackView(views: [proceed, cancel])
        offerPanel.orientation = .vertical
        offerPanel.alignment = .leading
        offerPanel.spacing = 4
        offerPanel.detachesHiddenViews = true
        for part in [offerLabel, offerDetails, offerActions, changeSample] { offerPanel.addArrangedSubview(part) }
        offerLabel.widthAnchor.constraint(equalTo: offerPanel.widthAnchor).isActive = true
        offerDetails.widthAnchor.constraint(equalTo: offerPanel.widthAnchor).isActive = true
        offerPanel.isHidden = true
        methods.orientation = .vertical
        methods.alignment = .leading
        methods.spacing = 3
        methods.detachesHiddenViews = true

        // The choices below the conversation: an empty workbook's two starting points, the general guidance and the
        // method list for a workbook with data, or the card the assistant offered: its clarifying question with fixed
        // answers, or a distribution card.
        openExample.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-open-example")
        workbookHelp.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-workbook-help")
        helpChoose.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-help-choose")
        chooseMethod.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-choose-method")
        openExample.setAccessibilityHelp("Opens the bundled example workbook in a new tab.")
        workbookHelp.setAccessibilityHelp("Opens the Help topic about workbooks.")
        helpChoose.setAccessibilityHelp("Asks AI Assist to help choose a statistical method.")
        chooseMethod.setAccessibilityHelp("Lists the StatsDirect methods to choose from locally.")
        for (row, buttons) in [(emptyRow, [openExample, workbookHelp]), (compareRow, [helpChoose, chooseMethod])] {
            for button in buttons { row.addArrangedSubview(button) }
            row.orientation = .horizontal
            row.spacing = 6
        }
        clarifyBox.orientation = .vertical
        clarifyBox.alignment = .leading
        clarifyBox.spacing = 3
        clarifyBox.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-clarification")
        distributionBox.orientation = .vertical
        distributionBox.alignment = .leading
        distributionBox.spacing = 3
        distributionBox.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-distribution")
        guidance.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-choices")
        guidance.orientation = .vertical
        // Each part fills the choices' width, so a card's text wraps however often the part is shown again.
        guidance.alignment = .width
        guidance.spacing = 4
        guidance.detachesHiddenViews = true
        for part in [emptyRow, compareRow, clarifyBox, distributionBox] { part.isHidden = true; guidance.addArrangedSubview(part) }
        guidance.setAccessibilityElement(true)
        guidance.setAccessibilityRole(.group)
        guidance.setAccessibilityLabel("Suggested next steps")

        notice.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-notice")
        notice.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notice.textColor = .secondaryLabelColor
        questionOnlyHint.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-question-only-hint")
        questionOnlyHint.font = notice.font
        questionOnlyHint.textColor = .secondaryLabelColor
        let history = transcript.view
        let stack = NSStackView(views: [header, workbookLabel, selectionLabel, offerPanel, connection, sharingButton, sharingPanel,
                                       questionOnlyHint, composer, actions, notice, history, guidance, methods, openCode])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        for item in [header, workbookLabel, selectionLabel, offerPanel, sharingPanel, questionOnlyHint, composer, notice, history, guidance, methods] {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        warning.widthAnchor.constraint(equalTo: sharingPanel.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            composer.heightAnchor.constraint(equalToConstant: 68),
            history.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
        for item in [workbookLabel, selectionLabel, warning, offerLabel, offerDetails, questionOnlyHint, notice] {
            item.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        history.setContentHuggingPriority(.defaultLow, for: .vertical)
        connection.target = self; connection.action = #selector(connect)
        sharingButton.target = self; sharingButton.action = #selector(toggleSharingOptions)
        share.target = self; share.action = #selector(sharingChanged)
        confirm.target = self; confirm.action = #selector(sharingChanged)
        sendButton.target = self; sendButton.action = #selector(send)
        stopButton.target = self; stopButton.action = #selector(stop)
        chooseMethod.target = self; chooseMethod.action = #selector(chooseLocalMethod)
        helpChoose.target = self; helpChoose.action = #selector(askForGuidance)
        openExample.target = self; openExample.action = #selector(openExampleWorkbook)
        workbookHelp.target = self; workbookHelp.action = #selector(openWorkbookHelp)
        openCode.target = self; openCode.action = #selector(openLastCode)
        transcript.openR = { [weak self] generation, message, block, shown in
            self?.openReply(generation, message, block, shown)
        }
        transcript.copyCode = { [weak self] generation, message, code in
            self?.copyReply(generation, message, code) ?? false
        }
        updateControls()
    }

    func open(_ doc: Document) {
        guard doc.kind == "grid", !TutorPolicy.disabled else { return }
        viewer.scriptAI.hide()
        viewer.helpPane.hide()
        if !visible {
            visible = true
            viewer.workspaceSplit.addArrangedSubview(view)
            viewer.workspaceSplit.adjustSubviews()
            let split = viewer.workspaceSplit.bounds.width
            viewer.workspaceSplit.setPosition(max(320, split - width - viewer.workspaceSplit.dividerThickness), ofDividerAt: 0)
        }
        activeDocumentChanged(doc)
        refreshWorksheetState(doc)
        viewer.window.makeFirstResponder(input)
        Task { @MainActor [weak self] in
            guard let self, !TutorPolicy.disabled else { return }
            do { try await viewer.chatGPTTutor.refreshAccount() }
            catch { if visible { showNotice(error.localizedDescription) } }
        }
    }

    func activeDocumentChanged(_ doc: Document) {
        guard visible, doc.kind == "grid" else { return }
        if doc.id != workbookID { cancelAnalysis() }
        if isBusy {
            pendingWorkbookID = doc.id
            updateControls()
            return
        }
        select(doc.id)
    }

    private func select(_ id: String) {
        guard workbookID != id else { updateControls(); return }
        conversation?.draft = input.string
        workbookID = id
        clarification = nil
        distribution = nil
        if conversations[id] == nil { conversations[id] = Conversation() }
        input.string = conversation?.draft ?? ""
        expanded = conversation?.confirmed != true
        showNotice("")
        if let doc = workbook, doc.aiWorksheet == nil { refreshWorksheetState(doc) }
        render()
    }

    func documentClosed(_ doc: Document) {
        conversations.removeValue(forKey: doc.id)
        if pendingWorkbookID == doc.id { pendingWorkbookID = nil }
        if clarification?.workbookID == doc.id { clarification = nil }
        if distribution?.workbookID == doc.id { distribution = nil }
        guard workbookID == doc.id else {
            if visible, doc.kind == "grid" { updateControls() }
            return
        }
        cancelAnalysis()
        if isBusy { stop() }
        workbookID = nil
        input.string = ""
        if let active = viewer.active, active !== doc, active.kind == "grid" { activeDocumentChanged(active) }
        else if !viewer.documents.contains(where: { $0.kind == "grid" }) { hide() }
        else { render() }
    }

    /// The grid page reported a new selection, an edit, a load, a sheet switch or a change of "First row has column
    /// names" (GridHost "aiWorksheet").
    func worksheetStateChanged(_ doc: Document) {
        guard visible, doc.id == workbookID else { return }
        // A card belongs to the selection and contents it was drawn for: a late click on its previous buttons is
        // refused, and the card is drawn again with a new token (an interval card once it has been read again).
        issueGuidanceToken()
        // The conversation is drawn again only when the workbook becomes empty or stops being empty (its introduction
        // changes); a selection change redraws only the label and the choices.
        if !hasData(doc) != renderedEmpty { render() } else { renderGuidance(); updateControls() }
    }

    /// A new token for the current card, with the live selection it belongs to read from the grid. An interval card is
    /// read again, as Windows reads it on every selection or content change: only the newest reading is drawn, with a
    /// token of its own, so a click on the card as it stood before is refused.
    private func issueGuidanceToken() {
        let token = UUID().uuidString
        guidanceToken = token
        guidanceFingerprint = nil
        guard let doc = workbook else { return }
        if let shown = distribution, shown.workbookID == doc.id, shown.card.kind != .choose {
            let kind = shown.card.kind
            Task { @MainActor [weak self] in
                guard let read = await self?.readCard(doc, kind, confirm: false), let self, self.guidanceToken == token,
                      self.workbookID == doc.id, self.distribution?.workbookID == doc.id, self.distribution?.card.kind == kind else { return }
                switch read {
                case .read(let check, let fingerprint):
                    // A new reading clears any feedback, and an independent card's confirmation of separate samples.
                    self.distribution = (WorksheetAIDistribution(kind: kind, check: check), doc.id)
                    self.guidanceToken = UUID().uuidString
                    self.guidanceFingerprint = fingerprint
                    self.renderGuidance()
                case .refused(let message):
                    // Not even an unread card could be drawn: the engine did not answer.
                    self.distribution = nil
                    self.render()
                    self.showNotice(message)
                }
            }
            return
        }
        guard clarification?.workbookID == doc.id || distribution?.workbookID == doc.id else { return }
        Task { @MainActor [weak self] in
            guard let self, let fingerprint = await self.selectionFingerprint(doc), self.guidanceToken == token else { return }
            self.guidanceFingerprint = fingerprint
        }
    }

    /// The grid's exact selection, with whole rows and columns as compact slices, its sheet and the workbook and sheet
    /// revisions, which every edit changes (Grid/ai-selection.mjs selectionFingerprint).
    private func selectionFingerprint(_ doc: Document) async -> String? {
        let web = doc.web
        let value = try? await web.evaluateJavaScript("window.statsDirectGrid.aiSelectionFingerprint()")
        guard doc.web === web, viewer.documents.contains(where: { $0 === doc }) else { return nil }
        return value as? String
    }

    /// An interval card's local check of the live selection (Windows ReadSelection): the page reads the two selected
    /// columns as an analysis of them would, with the click fingerprint of the same moment (Grid/measurement-columns.mjs),
    /// and the engine checks them. For the user's Check (`confirm`), a selection the page or the engine refuses comes
    /// back as its text, for the card; otherwise the card is drawn without a check, as Windows draws a selection it
    /// cannot read. Nil when the workbook has gone.
    private func readCard(_ doc: Document, _ kind: WorksheetAIDistribution.Kind, confirm: Bool) async -> CardRead? {
        let paired = kind == .paired, web = doc.web
        let page = (try? await web.callAsyncJavaScript(
            "return window.statsDirectGrid?.aiMeasurementColumns ? await window.statsDirectGrid.aiMeasurementColumns(design) : null",
            arguments: ["design": paired ? "paired" : "independent"], in: nil, contentWorld: .page)) as? [String: Any]
        // The paired differences' snapshot file is the engine's to read once; it is forgotten however the check ends.
        let snapshot = (page?["snapshot"] as? [String: Any])?["id"] as? String
        defer { if let snapshot { SnapshotStore.shared.forget(snapshot) } }
        guard doc.web === web, viewer.documents.contains(where: { $0 === doc }) else { return nil }
        let unreadable = "The worksheet could not be read. Try again."
        var refusal = page == nil ? unreadable : page?["error"] as? String
        var read: [String: Any]?
        if refusal == nil, let page {
            if paired, let pairs = page["pairs"] as? Int {
                if pairs == 0 { read = ["differences": [Double]()] }
                else if let snapshot, let file = SnapshotStore.shared.file(for: snapshot) { read = ["snapshot": file.path, "pairs": pairs] }
            } else if !paired, let samples = page["samples"] as? [[String: Any]] {
                let columns = samples.compactMap { sample -> [String: Any]? in
                    guard let count = sample["count"] as? Int, let values = sample["values"] as? [Double] else { return nil }
                    return ["count": count, "values": values]
                }
                if columns.count == 2 { read = ["samples": columns] }
            }
            if read == nil { refusal = unreadable }
        }
        if confirm, let refusal { return .refused(refusal) }
        var fingerprint = page?["fingerprint"] as? String
        if page == nil { fingerprint = await selectionFingerprint(doc) }
        do {
            return .read(try await measurementCheck(kind, read: read, separateSamples: confirm), fingerprint: fingerprint)
        } catch {
            if confirm || read == nil { return .refused(error.localizedDescription) }
            // A reading the engine could not check leaves the card unread, as an unreadable selection does.
            guard let check = try? await measurementCheck(kind, read: nil, separateSamples: false) else { return .refused(error.localizedDescription) }
            return .read(check, fingerprint: fingerprint)
        }
    }

    /// The engine's card for a reading (statsdirect_measurement_check), its numbers in the user's format as the calculator
    /// gives them (main.swift), computed off the main thread. `read` nil is a selection that could not be read.
    private func measurementCheck(_ kind: WorksheetAIDistribution.Kind, read: [String: Any]?, separateSamples: Bool) async throws -> WorksheetAIDistribution.Check {
        let culture = Locale.current.identifier.components(separatedBy: "@")[0].replacingOccurrences(of: "_", with: "-")
        let request: [String: Any] = ["design": kind == .paired ? "paired" : "independent", "culture": culture,
                                      "separateSamples": separateSamples, "read": read ?? NSNull()]
        // JSONSerialization would end the app on a number JSON cannot hold; the page sends only finite ones.
        guard JSONSerialization.isValidJSONObject(request) else { throw ChatGPTTutor.Failure(message: "The worksheet could not be read. Try again.") }
        let reply = try await withCheckedThrowingContinuation { continuation in
            viewer.analysisRequest(request, entry: "statsdirect_measurement_check") { continuation.resume(with: $0) }
        }
        guard let check = WorksheetAIDistribution.Check(reply, kind: kind) else { throw ChatGPTTutor.Failure(message: "The worksheet could not be read. Try again.") }
        return check
    }

    /// Asks the page for its state when the pane has not heard from it: a workbook loaded before the pane opened, or a
    /// load that has just finished (the page posts only when its state changes, and a new empty sheet's does not).
    func refreshWorksheetState(_ doc: Document) {
        let web = doc.web
        web.evaluateJavaScript("window.statsDirectGrid && window.statsDirectGrid.aiWorksheetState ? window.statsDirectGrid.aiWorksheetState() : null") { [weak self, weak doc] value, _ in
            guard let self, let doc, doc.web === web, let body = value as? [String: Any], let state = WorksheetAIState(body) else { return }
            doc.aiWorksheet = state
            self.worksheetStateChanged(doc)
        }
    }

    /// An empty workbook is offered the example and the workbook Help. While a file is still loading, or before the
    /// page has reported, an opened file counts as having data and an untouched new sheet as empty.
    private func hasData(_ doc: Document) -> Bool {
        if let pending = doc.pendingCSV { return !pending.isEmpty }
        if let pending = doc.pendingWorkbook {
            // A file read by the engine brings cells or a snapshot; File ▸ New Worksheet brings an empty sheet.
            return (pending["sheets"] as? [[String: Any]] ?? []).contains { sheet in
                sheet["snapshot"] is String || !((sheet["cells"] as? [Any]) ?? []).isEmpty
            }
        }
        if let state = doc.aiWorksheet { return state.hasData }
        return doc.openedFileURL != nil || doc.gridVersion > 0 || doc.gridDirty
    }

    @objc func hide() {
        guard visible else { return }
        conversation?.draft = input.string
        cancelAnalysis()
        distribution = nil
        width = view.frame.width
        visible = false
        pendingWorkbookID = nil
        stop()
        view.removeFromSuperview()
        viewer.workspaceSplit.adjustSubviews()
    }

    func shutdown() {
        offerTask?.cancel()
        task?.cancel()
        requestID = nil
        task = nil
        transcript.shutdown()
    }

    func showNotice(_ message: String) {
        notice.stringValue = message
        notice.isHidden = message.isEmpty
    }

    @objc private func connect() {
        if let workbook { viewer.configureLearningAI(workbook) }
    }

    @objc private func toggleSharingOptions() {
        expanded.toggle()
        updateControls()
    }

    @objc private func sharingChanged() {
        guard let chat = conversation, !isBusy else { return }
        chat.share = share.state == .on
        chat.confirmed = chat.share && confirm.state == .on
        if chat.confirmed { expanded = false }
        // A clarifying question needs the conversation it came from, which only a shared workbook sends.
        if !chat.confirmed, clarification?.workbookID == workbookID { clarification = nil; render() }
        updateControls()
    }

    @objc private func newConversation() {
        guard let chat = conversation, !isBusy else { return }
        cancelAnalysis()
        clarification = nil
        distribution = nil
        chat.generation = UUID().uuidString
        chat.messages.removeAll()
        chat.draft = ""
        input.string = ""
        showNotice("")
        render()
    }

    func updateControls() {
        let chat = conversation
        let tutor = viewer.chatGPTTutor
        let disabled = TutorPolicy.disabled
        let name = workbook.map(displayName(for:)) ?? "No workbook selected"
        workbookLabel.stringValue = name
        workbookLabel.toolTip = name
        let caption = workbook?.aiWorksheet?.caption
        selectionLabel.stringValue = caption ?? ""
        selectionLabel.isHidden = caption == nil || disabled
        share.state = chat?.share == true ? .on : .off
        confirm.state = chat?.confirmed == true ? .on : .off
        share.isEnabled = !disabled && !isBusy && chat != nil
        confirm.isHidden = chat?.share != true
        confirm.isEnabled = share.isEnabled && chat?.share == true
        sharingPanel.isHidden = !expanded
        questionOnlyHint.isHidden = disabled || chat == nil || chat?.share == true
        sharingButton.title = expanded ? "Sharing for this workbook ▾"
            : chat?.confirmed == true ? "Sharing: this workbook ▸" : "Question only · Sharing options ▸"
        connection.title = disabled ? "AI disabled by policy" : tutor.account != nil ? "ChatGPT connection…" : "Use my ChatGPT"
        connection.isEnabled = !disabled && !isBusy
        sendButton.title = chat?.share == true ? "Send with selected context" : "Send question only"
        sendButton.isEnabled = !disabled && !isBusy && tutor.account != nil && chat != nil
            && (chat?.share != true || chat?.confirmed == true)
        stopButton.isEnabled = isBusy
        replyActivity.stringValue = stopRequested ? "Stopping…" : "Reply in progress…"
        replyActivity.isHidden = !isBusy
        chooseMethod.isEnabled = !isBusy && !disabled && workbook != nil
        helpChoose.isEnabled = !isBusy && !disabled && chat != nil
        openExample.isEnabled = !isBusy && !disabled
        workbookHelp.isEnabled = !isBusy && !disabled
        if disabled { showNotice(TutorPolicy.message) }
        // A policy that disables AI reaches the pane here: the card and the other choices go with it.
        if disabled, !guidance.isHidden { renderGuidance() }
    }

    @objc func send() {
        submit(input.string.trimmingCharacters(in: .whitespacesAndNewlines), typed: true)
    }

    /// Sends a question: one the user typed, or a fixed sentence from a button (the guidance question or a
    /// clarification answer), which leaves the user's draft in the composer. Returns whether it was sent.
    @discardableResult
    private func submit(_ question: String, typed: Bool) -> Bool {
        guard visible, !isBusy, !TutorPolicy.disabled, let workbook, let chat = conversation else { return false }
        guard !question.isEmpty else { showNotice("Enter a question for AI."); return false }
        guard question.count <= 8000 else { showNotice("Shorten the question to 8,000 characters."); return false }
        guard viewer.chatGPTTutor.account != nil else {
            if !typed, input.string.isEmpty { input.string = question; chat.draft = question }
            showNotice("Choose Use my ChatGPT first."); return false
        }
        guard !chat.share || chat.confirmed else { showNotice("Check the workbook for person identifiers, then confirm before sending."); return false }
        cancelAnalysis()
        clarification = nil
        distribution = nil
        let token = UUID()
        let replyID = UUID().uuidString
        let shared = chat.share && chat.confirmed
        let row = ["id": UUID().uuidString, "role": "user", "text": question,
                   "context": shared ? "Shared for this question: " + workbook.title : "Question only"]
        let messages = chat.messages + [row]
        requestID = token
        stopRequested = false
        partial = ""
        if typed { input.string = ""; chat.draft = "" }
        let context = ScriptAIContext(viewer: viewer, script: nil, workbook: shared ? workbook : nil,
                                      usesSessionConsent: false, worksheetAssist: true) { [weak self] in self?.acceptsRequest(token) == true }
        // The clarifying card is offered only with a shared workbook that holds data: a question-only send carries no
        // earlier messages, so a one-line answer would reach the provider without the question it answers.
        let offersClarification = shared && hasData(workbook)
        // The distribution cards are offered in both modes, as on Windows: they are completed on this Mac and send
        // nothing. They need the workbook in front, with data, and not being opened or saved.
        func cardReady() -> Bool { !TutorPolicy.disabled && viewer.active === workbook && hasData(workbook) && !workbook.fileBusy }
        let offersCard = cardReady()
        let tools = (shared ? context.tools : []) + (offersCard ? [WorksheetAIDistribution.definition] : [])
            + (offersClarification ? [WorksheetAIClarification.definition] : [])
        let reference = methodReference()
        let unsharedMessages = [row]
        let staged = RequestState()
        // Stages a distribution card for the reply to show, in Windows' order of checks (ScriptAIPane.cs). The result
        // tells the assistant only that the card waits for the user.
        let stageCard: ChatGPTTutor.ToolHandler = { _, args in
            try context.check()
            guard offersCard, cardReady() else { throw ChatGPTTutor.Failure(message: "Choose an active worksheet before offering a study-design choice.") }
            guard !staged.waiting else { throw ChatGPTTutor.Failure(message: "A worksheet action is already waiting.") }
            let kind: WorksheetAIDistribution.Kind
            if args.isEmpty { kind = .choose }
            else if args.count == 1, let design = args["design"] as? String, design == "paired" || design == "independent" {
                kind = design == "paired" ? .paired : .independent
            } else { throw ChatGPTTutor.Failure(message: "Omit design or set it to paired or independent.") }
            staged.distribution = kind
            return kind == .choose
                ? ["state": "awaiting_design", "message": "Ask the user to choose “Same people or units” or “Separate groups” in the chat."]
                : ["state": "awaiting_distribution", "message": "The decision card lets the user check their selection locally and choose a branch. Ask them to review the card."]
        }
        let handler: ChatGPTTutor.ToolHandler?
        if shared {
            handler = { name, args in
                if name == WorksheetAIDistribution.tool { return try await stageCard(name, args) }
                if name == WorksheetAIClarification.tool {
                    guard offersClarification else { throw ChatGPTTutor.Failure(message: "This question does not allow that AI action.") }
                    try context.check()
                    guard args.count == 1, let dimension = args["dimension"] as? String,
                          let card = WorksheetAIClarification.make(dimension) else { throw ChatGPTTutor.Failure(message: "Choose goal, scale or design.") }
                    guard !staged.waiting else { throw ChatGPTTutor.Failure(message: "A worksheet action is already waiting.") }
                    staged.clarification = card
                    return ["state": "awaiting_clarification",
                            "message": "The question and its answers are shown in the chat. Ask the user to choose an answer."]
                }
                return try await context.call(name, args)
            }
        } else if offersCard {
            // Question only offers the card's tool alone, and any refusal reaches the provider as Windows' guidance-only
            // text, which says nothing about the workbook.
            handler = { name, args in
                do { return try await stageCard(name, args) }
                catch let stop as CancellationError { throw stop }
                catch { throw ChatGPTTutor.Failure(message: "The analysis proposal could not be staged.") }
            }
        } else { handler = nil }
        // The tutor reports each result it sent; only then does a read join Data used and the reply's R data.
        let delivered: ChatGPTTutor.ToolDelivery?
        if shared { delivered = { name, value in context.delivered(name, value) } } else { delivered = nil }
        let progress: ChatGPTTutor.ProgressHandler = { [weak self] text in
            guard let self, self.acceptsRequest(token) else { return }
            self.partial = text
            self.render()
        }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishRequest(token) }
            do {
                try context.check()
                let reply = try await viewer.chatGPTTutor.converse(context: reference,
                    messages: shared ? messages : unsharedMessages, tools: tools, purpose: .worksheet,
                    progress: progress, toolHandler: handler, toolDelivered: delivered)
                try context.check()
                chat.messages.append(["id": replyID, "role": "assistant", "text": reply.text, "rData": context.rData,
                                      "reads": Self.encode(context.reads)])
                if let card = staged.clarification, workbookID == workbook.id {
                    clarification = (card, workbook.id)
                    issueGuidanceToken()
                }
                // A staged interval card reads the selection as it now stands, not as it was when the card was staged.
                if let kind = staged.distribution, workbookID == workbook.id {
                    distribution = (WorksheetAIDistribution(kind: kind), workbook.id)
                    issueGuidanceToken()
                }
                showNotice("")
            } catch {
                // The receipt survives a reply that stops or fails once cells have been read, as on Windows. Its fields
                // stay in the app: ChatGPTTutor sends only each row's role and text.
                let stopped = Task.isCancelled || error is CancellationError
                let reads = Self.encode(context.reads)
                if !partial.isEmpty {
                    chat.messages.append(["id": replyID, "role": "assistant", "text": partial + "\n[Reply stopped before completion.]",
                                          "incomplete": "true", "reads": reads])
                } else if !context.reads.isEmpty {
                    chat.messages.append(["id": replyID, "role": "assistant", "text": stopped ? Self.stoppedBeforeText : Self.noReply,
                                          "incomplete": "true", "reads": reads])
                }
                if stopped {
                    // As on Windows, the question waits in the composer unless something else was typed since.
                    if input.string.isEmpty, workbookID == workbook.id {
                        input.string = question; chat.draft = question
                        showNotice("Reply stopped. Your question is kept here.")
                    } else { showNotice("Reply stopped.") }
                } else {
                    showNotice(error.localizedDescription)
                    if input.string.isEmpty { input.string = question; chat.draft = question }
                }
            }
        }
        chat.messages = messages
        showNotice(shared ? "Sending with the approved workbook…" : "Sending your question only…")
        render()
        return true
    }

    @objc func stop() {
        guard let task else { return }
        stopRequested = true
        task.cancel()
        updateControls()
    }

    private func acceptsRequest(_ token: UUID) -> Bool {
        visible && requestID == token && task?.isCancelled == false
    }

    private func finishRequest(_ token: UUID) {
        guard requestID == token else { return }
        requestID = nil
        task = nil
        stopRequested = false
        partial = ""
        let next = pendingWorkbookID
        pendingWorkbookID = nil
        if visible, let next, viewer.documents.contains(where: { $0.id == next }) { select(next) }
        render()
    }

    private static func encode(_ reads: [WorksheetAIRead]) -> String {
        (try? JSONEncoder().encode(reads)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    private static func decode(_ reads: String) -> [WorksheetAIRead]? {
        try? JSONDecoder().decode([WorksheetAIRead].self, from: Data(reads.utf8))
    }

    private func displayName(for document: Document) -> String {
        func filename(_ doc: Document) -> String { doc.openedFileURL?.lastPathComponent ?? doc.title }
        func folder(_ doc: Document) -> String? { doc.openedFileURL?.deletingLastPathComponent().standardizedFileURL.path }
        let name = filename(document)
        let matches = viewer.documents.filter {
            $0.kind == "grid" && filename($0).caseInsensitiveCompare(name) == .orderedSame
        }
        guard matches.count > 1 else { return name }
        let parent = folder(document)
        let location = parent.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Unsaved workbook"
        let copies = matches.filter { folder($0) == parent }
        if copies.count > 1, let index = copies.firstIndex(where: { $0 === document }) {
            return name + "\n" + location + " · Open copy \(index + 1)"
        }
        return name + "\n" + location
    }

    private func methodReference() -> String {
        let url = viewer.root.appendingPathComponent("Help/methods/method_selection.htm")
        let guide = (try? String(contentsOf: url, encoding: .utf8)).map(LearningWorkspace.plain) ?? ""
        let catalogue = viewer.worksheetAIMethods.map { $0.id + ": " + $0.title }.joined(separator: "\n")
        return "Packaged Method Selection guide:\n" + String(guide.prefix(9_000))
            + "\n\nEnabled StatsDirect method catalogue:\n" + String(catalogue.prefix(21_000))
    }

    private func latestReply() -> [String: String]? {
        guard let reply = conversation?.messages.last, reply["role"] == "assistant", reply["incomplete"] != "true" else { return nil }
        return reply
    }

    private func render() {
        let latest = latestReply()
        let empty = workbook.map { !hasData($0) } ?? false
        // An emptied workbook drops its card and offers no methods, as on Windows.
        if empty, clarification?.workbookID == workbookID { clarification = nil }
        if empty, distribution?.workbookID == workbookID { distribution = nil }
        openCode.isHidden = latest.map { ConversationRScript.blocks($0["text"] ?? "").isEmpty } ?? true
        openCode.isEnabled = !isBusy && !TutorPolicy.disabled
        for button in methods.arrangedSubviews { methods.removeArrangedSubview(button); button.removeFromSuperview() }
        if !isBusy, offer == nil, !empty, let reply = latest?["text"] {
            let catalogue = viewer.worksheetAIMethods
            var seen = Set<String>()
            for id in WorksheetAIMarkers.read(reply).ids {
                guard seen.insert(id).inserted, let method = catalogue.first(where: { $0.id == id }) else { continue }
                let button = NSButton(title: method.title, target: self, action: #selector(pickMethod(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(id)
                button.setAccessibilityHelp("Review the selection and report destination for this analysis.")
                methods.addArrangedSubview(button)
                if methods.arrangedSubviews.count == 4 { break }
            }
        }
        methods.isHidden = methods.arrangedSubviews.isEmpty
        offerPanel.isHidden = offer == nil
        renderGuidance()
        var rows: [[String: Any]] = (conversation?.messages ?? []).map { row in
            let body = row["text"] ?? ""
            let stripped = row["role"] == "assistant" ? WorksheetAIMarkers.read(body).text : body
            var shown: [String: Any] = ["id": row["id"] ?? "", "role": row["role"] ?? "assistant", "text": stripped,
                                        "context": row["context"] ?? "", "pending": row["incomplete"] == "true"]
            if row["role"] == "assistant", let reads = row["reads"].flatMap(Self.decode) {
                if reads.isEmpty { shown["generalGuidance"] = true } else { shown["dataUsed"] = reads.map(\.line) }
            }
            return shown
        }
        if !partial.isEmpty {
            rows.append(["id": "pending", "role": "assistant", "text": WorksheetAIMarkers.read(partial).text, "pending": true])
        }
        renderedEmpty = empty
        transcript.render(["generation": conversation?.generation ?? "", "messages": rows, "collapseR": true,
                           "introduction": empty ? "This workbook is empty."
                               : "Ask for help analysing this workbook. You can choose a method, review the selection and run it locally."])
        updateControls()
    }

    /// One card at a time, as on Windows, and none while a reply runs or a method waits for confirmation.
    private func renderGuidance() {
        // Drawing the card again (a new token) must not drop the keyboard focus on one of its answers.
        let focused = (viewer.window.firstResponder as? WorksheetAIChoiceButton).flatMap {
            $0.isDescendant(of: clarifyBox) || $0.isDescendant(of: distributionBox) ? $0.choice : nil
        }
        for box in [clarifyBox, distributionBox] {
            for part in box.arrangedSubviews { box.removeArrangedSubview(part); part.removeFromSuperview() }
        }
        guard visible, !isBusy, offer == nil, !TutorPolicy.disabled, let workbook else {
            for part in [emptyRow, compareRow, clarifyBox, distributionBox] { part.isHidden = true }
            guidance.isHidden = true
            return
        }
        let empty = !hasData(workbook)
        let card = empty ? nil : clarification.flatMap { $0.workbookID == workbook.id ? $0.card : nil }
        let decision = empty || card != nil ? nil : distribution.flatMap { $0.workbookID == workbook.id ? $0.card : nil }
        emptyRow.isHidden = !empty
        compareRow.isHidden = empty || card != nil || decision != nil
        clarifyBox.isHidden = card == nil
        // An interval card is drawn once the selection has been read for it.
        distributionBox.isHidden = decision.map { $0.kind != .choose && $0.check == nil } ?? true
        guidance.setAccessibilityLabel(empty ? "Getting started with a workbook" : card != nil ? "Analysis question"
            : decision?.accessibilityLabel ?? "Choose a worksheet method")
        if let decision, !distributionBox.isHidden { drawDistribution(decision, focused: focused) }
        if let card {
            let question = NSTextField(wrappingLabelWithString: card.question)
            question.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-clarification-question")
            clarifyBox.addArrangedSubview(question)
            question.widthAnchor.constraint(equalTo: clarifyBox.widthAnchor).isActive = true
            for option in card.options {
                let button = WorksheetAIChoiceButton(title: option.label, target: self, action: #selector(chooseAnswer(_:)))
                button.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-choice-" + option.id)
                button.token = guidanceToken
                button.choice = option.id
                clarifyBox.addArrangedSubview(button)
                if option.id == focused { viewer.window.makeFirstResponder(button) }
            }
        }
        guidance.isHidden = [emptyRow, compareRow, clarifyBox, distributionBox].allSatisfy(\.isHidden)
    }

    /// A distribution card as Windows lays it out (Learning/conversation.mjs): its paragraphs, the recommendation under
    /// its heading, any feedback, then its choices, whose titles wrap to the card's width.
    private func drawDistribution(_ card: WorksheetAIDistribution, focused: String?) {
        func paragraph(_ text: String, _ id: String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-distribution-" + id)
            distributionBox.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: distributionBox.widthAnchor).isActive = true
            return field
        }
        if let question = card.question { _ = paragraph(question, "question") }
        for (index, line) in card.lines.enumerated() { _ = paragraph(line, "line-\(index)") }
        if let check = card.check, let recommendation = check.recommendation {
            let size = NSFont.systemFontSize
            let text = NSMutableAttributedString(string: (check.suggestedBranch != nil ? "Suggested branch" : "Review the differences") + "\n",
                                                 attributes: [.font: NSFont.boldSystemFont(ofSize: size)])
            text.append(NSAttributedString(string: recommendation, attributes: [.font: NSFont.systemFont(ofSize: size)]))
            paragraph("", "recommendation").attributedStringValue = text
        }
        if let feedback = card.feedback {
            paragraph(feedback, "feedback").font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        }
        var restored = false
        for (choice, title) in card.buttons {
            let button = WorksheetAIChoiceButton(title: title, target: self, action: #selector(chooseCard(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-card-" + choice)
            button.token = guidanceToken
            button.choice = choice
            button.wrapsTitle = true
            if choice == card.check?.suggestedBranch { button.font = .boldSystemFont(ofSize: NSFont.systemFontSize) }
            distributionBox.addArrangedSubview(button)
            button.widthAnchor.constraint(lessThanOrEqualTo: distributionBox.widthAnchor).isActive = true
            if choice == focused { restored = viewer.window.makeFirstResponder(button) }
        }
        // As on Windows, focus that was on the card moves to its first choice when its own choice has gone.
        if focused != nil, !restored, let first = distributionBox.arrangedSubviews.first(where: { $0 is WorksheetAIChoiceButton }) {
            viewer.window.makeFirstResponder(first)
        }
    }

    @objc private func chooseCard(_ button: WorksheetAIChoiceButton) {
        let choice = button.choice, token = button.token
        Task { @MainActor [weak self] in _ = await self?.answerCard(choice, token: token) }
    }

    /// One choice on the distribution card (Windows ChooseWorksheetAction). As for the clarifying question, a token
    /// from an earlier card refuses the click, and so does any difference between the live grid and the selection and
    /// revisions the card was drawn for: the card is then read and drawn again, and the click is dropped. Returns whether
    /// the click was taken.
    @discardableResult
    func answerCard(_ choice: String, token: String) async -> Bool {
        func current() -> (Document, WorksheetAIDistribution)? {
            guard visible, !isBusy, offer == nil, !TutorPolicy.disabled, token == guidanceToken, let workbook, workbookID == workbook.id,
                  let shown = distribution, shown.workbookID == workbook.id,
                  shown.card.buttons.contains(where: { $0.choice == choice }) else { return nil }
            return (workbook, shown.card)
        }
        guard let before = current(), let expected = guidanceFingerprint else { return false }
        let live = await selectionFingerprint(before.0)
        guard let (workbook, card) = current(), workbook === before.0 else { return false }
        guard live == expected else {
            issueGuidanceToken()
            renderGuidance()
            return false
        }
        switch choice {
        case "paired", "independent":
            distribution = (WorksheetAIDistribution(kind: choice == "paired" ? .paired : .independent), workbook.id)
            issueGuidanceToken()
            renderGuidance()
        case "back":
            // The study-design question for the same selection: a new token, and the fingerprint just matched.
            distribution = (WorksheetAIDistribution(kind: .choose), workbook.id)
            guidanceToken = UUID().uuidString
            renderGuidance()
        case "check":
            // Windows' Check: the live selection, confirmed for an independent card as two separate samples. A refusal
            // stays on the card; a check redraws it with a new token. A change meanwhile wins over the check.
            let read = await readCard(workbook, card.kind, confirm: true)
            guard token == guidanceToken, offer == nil, distribution?.workbookID == workbook.id, distribution?.card.kind == card.kind else { return true }
            switch read {
            case .refused(let message): showCardFeedback(message)
            case .read(let check, let fingerprint):
                distribution = (WorksheetAIDistribution(kind: card.kind, check: check), workbook.id)
                guidanceToken = UUID().uuidString
                guidanceFingerprint = fingerprint
                showNotice("")
                renderGuidance()
            case nil: break
            }
        default:
            guard let check = card.check else { return false }
            // Windows' conflict rule: a known size refuses the other size's branch; the non-normal branch is always open.
            if let large = check.largeSample, large != (choice == "large"), choice != "non-normal" {
                showCardFeedback(check.conflict ?? "")
                return true
            }
            guard let method = check.methods[choice], viewer.worksheetAIMethods.contains(where: { $0.id == method }) else {
                distribution = nil
                render()
                showNotice("That method is unavailable. Choose another method in Analyse.")
                return true
            }
            prepareAnalysis(method, from: OfferOrigin(card: card, workbookID: workbook.id, fingerprint: expected, token: token, branch: choice))
            await offerTask?.value
        }
        return true
    }

    /// Feedback on the distribution card keeps its token, as Windows' `with { Feedback }` does: the evidence is unchanged.
    private func showCardFeedback(_ message: String) {
        guard let shown = distribution else { return }
        var card = shown.card
        card.feedback = message
        distribution = (card, shown.workbookID)
        showNotice("")
        renderGuidance()
        // Windows' feedback paragraph is a live region (role="status").
        NSAccessibility.post(element: viewer.window as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc private func chooseAnswer(_ button: WorksheetAIChoiceButton) {
        let choice = button.choice, token = button.token
        Task { @MainActor [weak self] in _ = await self?.answerClarification(choice, token: token) }
    }

    /// Sends the fixed sentence of one answer to the current clarifying question. A token from an earlier card, a
    /// changed workbook or sharing that has since been turned off refuses the click. So does any difference between the
    /// live grid and the selection and revisions the card was drawn for, as on Windows: the page reports a selection
    /// only once it settles and only when its short caption changes, so a click can arrive before that report or after
    /// a change the caption does not show. A refused card is drawn again with a new token. Returns whether it was sent.
    @discardableResult
    func answerClarification(_ choice: String, token: String) async -> Bool {
        func current() -> (Document, WorksheetAIClarification.Option)? {
            guard visible, !isBusy, !TutorPolicy.disabled, token == guidanceToken, let workbook, workbookID == workbook.id,
                  let pending = clarification, pending.workbookID == workbook.id,
                  let option = pending.card.options.first(where: { $0.id == choice }) else { return nil }
            return (workbook, option)
        }
        guard let before = current(), let expected = guidanceFingerprint else { return false }
        let live = await selectionFingerprint(before.0)
        guard let after = current(), after.0 === before.0, let chat = conversation else { return false }
        let option = after.1
        guard live == expected else {
            issueGuidanceToken()
            renderGuidance()
            return false
        }
        guard chat.share && chat.confirmed else {
            showNotice("Share this workbook again to answer, or type your full question."); return false
        }
        // submit retires the card once the answer is on its way; a send it refuses keeps the card for another try.
        return submit(option.answer, typed: false)
    }

    @objc private func askForGuidance() {
        guard visible, !isBusy, !TutorPolicy.disabled else { return }
        submit(Self.guidanceQuestion, typed: false)
    }

    @objc private func openExampleWorkbook() {
        guard visible, !isBusy, !TutorPolicy.disabled else { return }
        viewer.openExampleWorkbook()
    }

    @objc private func openWorkbookHelp() {
        guard visible, !isBusy, !TutorPolicy.disabled else { return }
        viewer.openHelp(viewer.root.appendingPathComponent("Help/basics/worksheet.htm"), title: "Workbook")
    }

    @objc private func pickMethod(_ button: NSButton) {
        guard let method = button.identifier?.rawValue else { return }
        prepareAnalysis(method)
    }

    @objc private func chooseLocalMethod() {
        guard visible, !isBusy, !TutorPolicy.disabled, let workbook else { return }
        cancelAnalysis()
        viewer.tabs.selectTabViewItem(workbook.item)
        viewer.window.makeFirstResponder(workbook.web)
        workbook.web.callAsyncJavaScript("window.statsDirectGrid.showWorksheetCommands(methods)",
            arguments: ["methods": viewer.worksheetAIMethods.map(\.id)], in: nil, in: .page) { _ in }
    }

    func prepareAnalysis(_ method: String) { prepareAnalysis(method, from: nil) }

    /// Offers a method for the current selection. `origin` is the distribution card the method was chosen on (Windows
    /// ConfirmWorksheetAnalysis with the decision and branch): the offer then also shows the card's check and Windows'
    /// advice for the branch, with Change sample choice, and takes the card's place; an error preparing it clears the card.
    private func prepareAnalysis(_ method: String, from origin: OfferOrigin?) {
        guard visible, !isBusy, let workbook, viewer.active === workbook, !TutorPolicy.disabled else {
            showNotice("Select the worksheet you want to analyse."); return
        }
        cancelAnalysis()
        offerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prepared = try await viewer.prepareWorksheetAIAnalysis(method, for: workbook)
                guard !Task.isCancelled, visible, workbookID == workbook.id else { return }
                if let origin {
                    // The card the branch was chosen on must still be the one shown.
                    guard guidanceToken == origin.token, distribution?.workbookID == workbook.id else { return }
                    distribution = nil
                    offerDetails.stringValue = ((origin.card.check?.diagnostics ?? []) + [origin.card.check?.advice[origin.branch] ?? ""])
                        .filter { !$0.isEmpty }.joined(separator: "\n")
                }
                offer = prepared
                offerOrigin = origin
                offerDetails.isHidden = origin == nil
                changeSample.isHidden = origin == nil
                offerLabel.stringValue = prepared.methodTitle + "\nMenu: " + prepared.menuPath + "\nWorksheet: " + prepared.worksheetName
                    + "\nSelection: " + prepared.selectionLabel + "\nReport: " + prepared.reportTitle
                showNotice("")
                render()
            } catch {
                guard !Task.isCancelled else { return }
                if let origin, guidanceToken == origin.token, distribution?.workbookID == workbook.id { distribution = nil; render() }
                showNotice(error.localizedDescription)
            }
        }
    }

    @objc func continueAnalysis() {
        guard let offer, let workbook, !isBusy, !TutorPolicy.disabled else { return }
        offerTask?.cancel()
        offerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await viewer.continueWorksheetAIAnalysis(offer, for: workbook) {
                    !Task.isCancelled && self.visible && self.workbookID == workbook.id && self.offer?.id == offer.id
                }
                cancelAnalysis()
            } catch {
                if !Task.isCancelled { cancelAnalysis(); showNotice(error.localizedDescription) }
            }
        }
    }

    /// Cancel, and every other end of an offer: a method chosen on a distribution card takes the card with it.
    @objc func cancelAnalysis() {
        offerTask?.cancel()
        offerTask = nil
        offerOrigin = nil
        if offer != nil { offer = nil; render() }
    }

    @objc private func changeSampleChoice() {
        Task { @MainActor [weak self] in _ = await self?.changeSample() }
    }

    /// Change sample choice (Windows' confirm "sample"): back from the offer to the distribution card it came from, as
    /// it was while the live selection is the one the card was read for, otherwise read again. Returns whether it went back.
    @discardableResult
    func changeSample() async -> Bool {
        guard visible, !isBusy, !TutorPolicy.disabled, let workbook, let origin = offerOrigin, origin.workbookID == workbook.id,
              let shown = offer else { return false }
        let live = await selectionFingerprint(workbook)
        guard visible, !isBusy, !TutorPolicy.disabled, offer === shown, offerOrigin != nil, self.workbook === workbook else { return false }
        cancelAnalysis()
        var card = origin.card
        card.feedback = nil
        distribution = (card, workbook.id)
        if let live, live == origin.fingerprint {
            guidanceToken = UUID().uuidString
            guidanceFingerprint = live
        } else { issueGuidanceToken() }
        render()
        return true
    }

    @objc private func openLastCode() {
        guard let chat = conversation, let id = latestReply()?["id"] else { return }
        openReply(chat.generation, id, -1, nil)
    }

    private func openReply(_ generation: String, _ messageID: String, _ blockIndex: Int, _ shown: String?) {
        guard !TutorPolicy.disabled, !isBusy, let chat = conversation, chat.generation == generation,
              let index = chat.messages.firstIndex(where: { $0["id"] == messageID && $0["role"] == "assistant" && $0["incomplete"] != "true" }) else { return }
        var block = blockIndex
        if let shown {
            block = ConversationRScript.findBlock(ConversationRScript.readBlocks(chat.messages[index]["text"] ?? ""), position: blockIndex, shown: shown)
            guard block >= 0 else { showNotice(ConversationRScript.unmatchedNotice); return }
        }
        do {
            let script = try ConversationRScript.build(chat.messages, messageIndex: index, blockIndex: block, currentReplyOnly: true)
            viewer.makeRScript(script: script, title: "AI suggestion", allowReportOutput: true)
            viewer.status.stringValue = "Review the suggested R code before choosing Run."
        } catch { showNotice(error.localizedDescription) }
    }

    private func copyReply(_ generation: String, _ messageID: String, _ shown: String) -> Bool {
        guard let chat = conversation, chat.generation == generation, shown.utf8.count <= 200_000,
              let row = chat.messages.first(where: { $0["id"] == messageID && $0["role"] == "assistant" && $0["incomplete"] != "true" }) else { return false }
        let blocks = ConversationRScript.readBlocks(row["text"] ?? "")
        let index = ConversationRScript.findBlock(blocks, position: -1, shown: shown, rOnly: false)
        guard index >= 0 else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(blocks[index].text, forType: .string)
    }
}

extension Viewer {
    func openWorksheetAI(_ doc: Document) {
        guard !TutorPolicy.disabled else { gridStatus(doc, TutorPolicy.message); return }
        if worksheetAI == nil { worksheetAI = WorksheetAIPane(viewer: self) }
        worksheetAI?.open(doc)
    }
}
