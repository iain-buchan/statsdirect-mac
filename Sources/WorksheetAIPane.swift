import Cocoa

/// What the grid page tells AI Assist about a workbook: the active sheet, its selection as an A1 address, and whether
/// the workbook holds anything. It stays in the app; nothing here is sent to the provider.
struct WorksheetAIState: Equatable {
    let sheet: Int
    let sheetName: String
    let label: String
    let singleCell: Bool
    let hasData: Bool

    init(sheet: Int, sheetName: String, label: String, singleCell: Bool, hasData: Bool) {
        self.sheet = sheet; self.sheetName = sheetName; self.label = label; self.singleCell = singleCell; self.hasData = hasData
    }

    /// The page's message or bridge result, checked as GridHost checks every grid message.
    init?(_ body: [String: Any]) {
        guard let sheet = body["sheet"] as? Int, let name = body["sheetName"] as? String, name.count <= 256,
              let label = body["label"] as? String, label.count <= 200,
              let single = body["singleCell"] as? Bool, let hasData = body["hasData"] as? Bool else { return nil }
        self.init(sheet: sheet, sheetName: name, label: label, singleCell: single, hasData: hasData)
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

/// A clarification answer button. It belongs to the card it was drawn for: a selection change, an edit or a new card
/// retires the token, so a click that arrives late is refused rather than sent.
final class WorksheetAIChoiceButton: NSButton {
    var token = ""
    var choice = ""
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
    /// What one question staged through its tools; shown only if its reply completes.
    private final class RequestState { var clarification: WorksheetAIClarification? }

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
    let chooseMethod = NSButton(title: "Browse methods", target: nil, action: nil)
    let helpChoose = NSButton(title: "Help me choose a method", target: nil, action: nil)
    let openExample = NSButton(title: "Open example workbook", target: nil, action: nil)
    let workbookHelp = NSButton(title: "Workbook help", target: nil, action: nil)
    let guidance = NSStackView()
    private let emptyRow = NSStackView()
    private let compareRow = NSStackView()
    private let clarifyBox = NSStackView()
    private let connection = NSButton(title: "Use my ChatGPT", target: nil, action: nil)
    private let workbookLabel = NSTextField(wrappingLabelWithString: "")
    let sharingButton = NSButton(title: "Sharing options", target: nil, action: nil)
    private let sharingPanel = NSStackView()
    private let questionOnlyHint = NSTextField(wrappingLabelWithString: "Include the full question each time. Earlier messages aren’t sent.")
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let methods = NSStackView()
    private let offerLabel = NSTextField(wrappingLabelWithString: "")
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
    /// The token every answer button of the current card carries.
    private(set) var guidanceToken = UUID().uuidString
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
        let offerActions = NSStackView(views: [proceed, cancel])
        offerPanel.orientation = .vertical
        offerPanel.alignment = .leading
        offerPanel.spacing = 4
        offerPanel.addArrangedSubview(offerLabel)
        offerPanel.addArrangedSubview(offerActions)
        offerLabel.widthAnchor.constraint(equalTo: offerPanel.widthAnchor).isActive = true
        offerPanel.isHidden = true
        methods.orientation = .vertical
        methods.alignment = .leading
        methods.spacing = 3
        methods.detachesHiddenViews = true

        // The choices below the conversation: an empty workbook's two starting points, the general guidance and the
        // method list for a workbook with data, or the assistant's clarifying question with its fixed answers.
        openExample.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-open-example")
        workbookHelp.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-workbook-help")
        helpChoose.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-help-choose")
        chooseMethod.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-browse-methods")
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
        guidance.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-choices")
        guidance.orientation = .vertical
        // Each part fills the choices' width, so the clarifying question wraps however often the part is shown again.
        guidance.alignment = .width
        guidance.spacing = 4
        guidance.detachesHiddenViews = true
        for part in [emptyRow, compareRow, clarifyBox] { part.isHidden = true; guidance.addArrangedSubview(part) }
        guidance.setAccessibilityElement(true)
        guidance.setAccessibilityRole(.group)
        guidance.setAccessibilityLabel("Suggested next steps")

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
        for item in [workbookLabel, selectionLabel, warning, offerLabel, questionOnlyHint, notice] {
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

    /// The grid page reported a new selection, an edit, a load or a sheet switch (GridHost "aiWorksheet").
    func worksheetStateChanged(_ doc: Document) {
        guard visible, doc.id == workbookID else { return }
        // A clarifying question belongs to the selection and contents it was asked about: a late click on its
        // previous buttons is refused, and the card is drawn again with a new token.
        guidanceToken = UUID().uuidString
        // The conversation is drawn again only when the workbook becomes empty or stops being empty (its introduction
        // changes); a selection change redraws only the label and the choices.
        if !hasData(doc) != renderedEmpty { render() } else { renderGuidance(); updateControls() }
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
        if doc.pendingWorkbook != nil || doc.pendingCSV != nil { return true }
        if let state = doc.aiWorksheet { return state.hasData }
        return doc.openedFileURL != nil || doc.gridVersion > 0 || doc.gridDirty
    }

    @objc func hide() {
        guard visible else { return }
        conversation?.draft = input.string
        cancelAnalysis()
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
    }

    @objc func send() {
        submit(input.string.trimmingCharacters(in: .whitespacesAndNewlines), typed: true)
    }

    /// Sends a question: one the user typed, or a fixed sentence from a button (the guidance question or a
    /// clarification answer), which leaves the user's draft in the composer.
    private func submit(_ question: String, typed: Bool) {
        guard visible, !isBusy, !TutorPolicy.disabled, let workbook, let chat = conversation else { return }
        guard !question.isEmpty else { showNotice("Enter a question for AI."); return }
        guard question.count <= 8000 else { showNotice("Shorten the question to 8,000 characters."); return }
        guard viewer.chatGPTTutor.account != nil else {
            if !typed, input.string.isEmpty { input.string = question; chat.draft = question }
            showNotice("Choose Use my ChatGPT first."); return
        }
        guard !chat.share || chat.confirmed else { showNotice("Check the workbook for person identifiers, then confirm before sending."); return }
        cancelAnalysis()
        clarification = nil
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
        let tools = shared ? context.tools + (offersClarification ? [WorksheetAIClarification.definition] : []) : []
        let reference = methodReference()
        let unsharedMessages = [row]
        let staged = RequestState()
        let handler: ChatGPTTutor.ToolHandler?
        if shared {
            handler = { name, args in
                if name == WorksheetAIClarification.tool {
                    guard offersClarification else { throw ChatGPTTutor.Failure(message: "This question does not allow that AI action.") }
                    try context.check()
                    guard args.count == 1, let dimension = args["dimension"] as? String,
                          let card = WorksheetAIClarification.make(dimension) else { throw ChatGPTTutor.Failure(message: "Choose goal, scale or design.") }
                    guard staged.clarification == nil else { throw ChatGPTTutor.Failure(message: "A worksheet action is already waiting.") }
                    staged.clarification = card
                    return ["state": "awaiting_clarification",
                            "message": "The question and its answers are shown in the chat. Ask the user to choose an answer."]
                }
                return try await context.call(name, args)
            }
        } else { handler = nil }
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
                    progress: progress, toolHandler: handler)
                try context.check()
                chat.messages.append(["id": replyID, "role": "assistant", "text": reply.text, "rData": context.rData,
                                      "reads": Self.encode(context.reads)])
                if let card = staged.clarification, workbookID == workbook.id {
                    clarification = (card, workbook.id)
                    guidanceToken = UUID().uuidString
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
                    showNotice("Reply stopped.")
                } else {
                    showNotice(error.localizedDescription)
                    if input.string.isEmpty { input.string = question; chat.draft = question }
                }
            }
        }
        chat.messages = messages
        showNotice(shared ? "Sending with the approved workbook…" : "Sending your question only…")
        render()
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
        openCode.isHidden = latest.map { ConversationRScript.blocks($0["text"] ?? "").isEmpty } ?? true
        openCode.isEnabled = !isBusy && !TutorPolicy.disabled
        for button in methods.arrangedSubviews { methods.removeArrangedSubview(button); button.removeFromSuperview() }
        if !isBusy, offer == nil, let reply = latest?["text"] {
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
        let empty = workbook.map { !hasData($0) } ?? false
        renderedEmpty = empty
        transcript.render(["generation": conversation?.generation ?? "", "messages": rows, "collapseR": true,
                           "introduction": empty ? "This workbook is empty."
                               : "Ask for help analysing this workbook. You can choose a method, review the selection and run it locally."])
        updateControls()
    }

    /// One card at a time, as on Windows, and none while a reply runs or a method waits for confirmation.
    private func renderGuidance() {
        for part in clarifyBox.arrangedSubviews { clarifyBox.removeArrangedSubview(part); part.removeFromSuperview() }
        guard visible, !isBusy, offer == nil, !TutorPolicy.disabled, let workbook else {
            for part in [emptyRow, compareRow, clarifyBox] { part.isHidden = true }
            guidance.isHidden = true
            return
        }
        let empty = !hasData(workbook)
        let card = empty ? nil : clarification.flatMap { $0.workbookID == workbook.id ? $0.card : nil }
        emptyRow.isHidden = !empty
        compareRow.isHidden = empty || card != nil
        clarifyBox.isHidden = card == nil
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
            }
            clarifyBox.setAccessibilityLabel(card.question)
        }
        guidance.isHidden = false
    }

    @objc private func chooseAnswer(_ button: WorksheetAIChoiceButton) {
        _ = answerClarification(button.choice, token: button.token)
    }

    /// Sends the fixed sentence of one answer to the current clarifying question. A token from an earlier card, a
    /// changed workbook or sharing that has since been turned off refuses the click. Returns whether it was sent.
    @discardableResult
    func answerClarification(_ choice: String, token: String) -> Bool {
        guard visible, !isBusy, !TutorPolicy.disabled, token == guidanceToken, let workbook, let chat = conversation,
              let pending = clarification, pending.workbookID == workbook.id,
              let option = pending.card.options.first(where: { $0.id == choice }) else { return false }
        guard chat.share && chat.confirmed else {
            showNotice("Share this workbook again to answer, or type your full question."); return false
        }
        clarification = nil
        submit(option.answer, typed: false)
        return true
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

    func prepareAnalysis(_ method: String) {
        guard visible, !isBusy, let workbook, viewer.active === workbook, !TutorPolicy.disabled else {
            showNotice("Select the worksheet you want to analyse."); return
        }
        cancelAnalysis()
        offerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prepared = try await viewer.prepareWorksheetAIAnalysis(method, for: workbook)
                guard !Task.isCancelled, visible, workbookID == workbook.id else { return }
                offer = prepared
                offerLabel.stringValue = prepared.methodTitle + "\nMenu: " + prepared.menuPath + "\nWorksheet: " + prepared.worksheetName
                    + "\nSelection: " + prepared.selectionLabel + "\nReport: " + prepared.reportTitle
                showNotice("")
                render()
            } catch { if !Task.isCancelled { showNotice(error.localizedDescription) } }
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

    @objc func cancelAnalysis() {
        offerTask?.cancel()
        offerTask = nil
        if offer != nil { offer = nil; render() }
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
