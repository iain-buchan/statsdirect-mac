import Cocoa

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

    unowned let viewer: Viewer
    let view = NSView()
    let transcript: AIConversationView
    let input = AIComposerInput()
    let share = NSButton(checkboxWithTitle: "Share workbook data", target: nil, action: nil)
    let confirm = NSButton(checkboxWithTitle: "I have checked for person-identifiable data.", target: nil, action: nil)
    let sendButton = NSButton(title: "Send question only", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    let chooseMethod = NSButton(title: "Choose a method", target: nil, action: nil)
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
    private var partial = ""
    private(set) var offer: WorksheetAIAnalysisOffer?
    private var offerTask: Task<Void, Never>?
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
        let actions = NSStackView(views: [sendButton, stopButton, chooseMethod])
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
        notice.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notice.textColor = .secondaryLabelColor
        questionOnlyHint.identifier = NSUserInterfaceItemIdentifier("worksheet-ai-question-only-hint")
        questionOnlyHint.font = notice.font
        questionOnlyHint.textColor = .secondaryLabelColor
        let history = transcript.view
        let stack = NSStackView(views: [header, workbookLabel, offerPanel, connection, sharingButton, sharingPanel,
                                       questionOnlyHint, composer, actions, notice, history, methods, openCode])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        for item in [header, workbookLabel, offerPanel, sharingPanel, questionOnlyHint, composer, notice, history, methods] {
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
        for item in [workbookLabel, warning, offerLabel, questionOnlyHint, notice] {
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
        if conversations[id] == nil { conversations[id] = Conversation() }
        input.string = conversation?.draft ?? ""
        expanded = conversation?.confirmed != true
        showNotice("")
        render()
    }

    func documentClosed(_ doc: Document) {
        conversations.removeValue(forKey: doc.id)
        if pendingWorkbookID == doc.id { pendingWorkbookID = nil }
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
        updateControls()
    }

    @objc private func newConversation() {
        guard let chat = conversation, !isBusy else { return }
        cancelAnalysis()
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
        chooseMethod.isEnabled = !isBusy && !disabled && workbook != nil
        if disabled { showNotice(TutorPolicy.message) }
    }

    @objc func send() {
        guard visible, !isBusy, !TutorPolicy.disabled, let workbook, let chat = conversation else { return }
        let question = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { showNotice("Enter a question for AI."); return }
        guard question.count <= 8000 else { showNotice("Shorten the question to 8,000 characters."); return }
        guard viewer.chatGPTTutor.account != nil else { showNotice("Choose Use my ChatGPT first."); return }
        guard !chat.share || chat.confirmed else { showNotice("Check the workbook for person identifiers, then confirm before sending."); return }
        cancelAnalysis()
        let token = UUID()
        let replyID = UUID().uuidString
        let shared = chat.share && chat.confirmed
        let row = ["id": UUID().uuidString, "role": "user", "text": question,
                   "context": shared ? "Shared for this question: " + workbook.title : "Question only"]
        let messages = chat.messages + [row]
        requestID = token
        partial = ""
        input.string = ""
        chat.draft = ""
        let context = ScriptAIContext(viewer: viewer, script: nil, workbook: shared ? workbook : nil,
                                      usesSessionConsent: false) { [weak self] in self?.acceptsRequest(token) == true }
        let tools = shared ? context.tools : []
        let reference = methodReference()
        let unsharedMessages = [row]
        let handler: ChatGPTTutor.ToolHandler?
        if shared { handler = { name, args in try await context.call(name, args) } }
        else { handler = nil }
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
                chat.messages.append(["id": replyID, "role": "assistant", "text": reply.text, "rData": context.rData])
                showNotice("")
            } catch {
                if Task.isCancelled || error is CancellationError {
                    if !partial.isEmpty {
                        chat.messages.append(["id": replyID, "role": "assistant",
                                              "text": partial + "\n[Reply stopped before completion.]", "incomplete": "true"])
                    }
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

    @objc func stop() { task?.cancel() }

    private func acceptsRequest(_ token: UUID) -> Bool {
        visible && requestID == token && task?.isCancelled == false
    }

    private func finishRequest(_ token: UUID) {
        guard requestID == token else { return }
        requestID = nil
        task = nil
        partial = ""
        let next = pendingWorkbookID
        pendingWorkbookID = nil
        if visible, let next, viewer.documents.contains(where: { $0.id == next }) { select(next) }
        render()
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

    private static let methodMarker = try! NSRegularExpression(pattern: #"(?m)^[ \t]*\[\[method:([A-Za-z0-9_]+)\]\][ \t]*$"#)

    private func render() {
        let latest = latestReply()
        openCode.isHidden = latest.map { ConversationRScript.blocks($0["text"] ?? "").isEmpty } ?? true
        openCode.isEnabled = !isBusy && !TutorPolicy.disabled
        for button in methods.arrangedSubviews { methods.removeArrangedSubview(button); button.removeFromSuperview() }
        if !isBusy, offer == nil, let reply = latest?["text"] {
            let catalogue = viewer.worksheetAIMethods
            var seen = Set<String>()
            for match in Self.methodMarker.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)) {
                guard let range = Range(match.range(at: 1), in: reply) else { continue }
                let id = String(reply[range])
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
        var rows: [[String: Any]] = (conversation?.messages ?? []).map { row in
            let body = row["text"] ?? ""
            let stripped = row["role"] == "assistant"
                ? Self.methodMarker.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
                : body
            return ["id": row["id"] ?? "", "role": row["role"] ?? "assistant", "text": stripped,
                    "context": row["context"] ?? "", "pending": row["incomplete"] == "true"]
        }
        if !partial.isEmpty { rows.append(["id": "pending", "role": "assistant", "text": partial, "pending": true]) }
        transcript.render(["generation": conversation?.generation ?? "", "messages": rows, "collapseR": true,
                           "introduction": "Ask for help analysing this workbook. You can choose a method, review the selection and run it locally."])
        updateControls()
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
