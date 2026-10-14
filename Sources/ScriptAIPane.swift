import Cocoa
import WebKit

@MainActor private final class ScriptAIControlsStack: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor final class ScriptAIPane: NSObject {
    private static let confirmationNotice="Check the selected content for person identifiers, then confirm before sending."
    final class Conversation {
        let generation = UUID().uuidString
        var messages: [[String:String]]=[]
        var draft=""
        var shareScript=false
        var shareWorkbook=false
        var workbookID: String?
        var reportResultID: String?
    }
    unowned let viewer: Viewer
    let view=NSView()
    let transcript: AIConversationView
    let input=NSTextView()
    let heading=NSTextField(labelWithString:"AI assistance · ChatGPT")
    let sourceLabel=NSTextField(labelWithString:"")
    let notice=NSTextField(wrappingLabelWithString:"")
    let connection=NSButton(title:"Use my ChatGPT",target:nil,action:nil)
    let shareScript=NSButton(checkboxWithTitle:"Share this script and its R output",target:nil,action:nil)
    let shareWorkbook=NSButton(checkboxWithTitle:"Share workbook data",target:nil,action:nil)
    let workbookPicker=NSPopUpButton()
    let acknowledgement=NSButton(checkboxWithTitle:"I have checked the selected content contains no person identifiers.",target:nil,action:nil)
    let sendButton=NSButton(title:"Send question only",target:nil,action:nil)
    let stopButton=NSButton(title:"Stop",target:nil,action:nil)
    let contextButton=NSButton(title:"Sharing for this session ▾",target:nil,action:nil)
    let contextPanel=NSStackView()
    let openCodeButton=NSButton(title:"Open R code",target:nil,action:nil)
    private var activeContext: ScriptAIContext?
    private(set) var visible=false
    private(set) var scriptID: String?
    private(set) var conversations: [String:Conversation]=[:]
    private(set) var requestID: UUID?
    private var task: Task<Void,Never>?
    private var partial=""
    private var replyID = UUID().uuidString
    private var dockWidth: CGFloat=460
    private var conversation: Conversation? { scriptID.flatMap{conversations[$0]} }
    private var isReport: Bool { viewer.documents.first(where:{$0.id==scriptID})?.kind == "report" }
    var isBusy: Bool { task != nil }
    var isFocused: Bool { visible && NSApp.keyWindow === viewer.window && (viewer.window.firstResponder as? NSView)?.isDescendant(of:view) == true }

    init(viewer: Viewer) {
        self.viewer=viewer;transcript=AIConversationView(root:viewer.root);super.init()
        transcript.openR = { [weak self] generation,id,index in self?.openCode(generation:generation,messageID:id,blockIndex:index) }
        transcript.copyCode = { [weak self] generation,id,code in self?.copyCode(generation:generation,messageID:id,code:code) }
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let close=NSButton(title:"×",target:self,action:#selector(hide));close.setAccessibilityLabel("Close AI assistance")
        let fresh=NSButton(image:NSImage(systemSymbolName:"square.and.pencil",accessibilityDescription:"New AI conversation")!,target:self,action:#selector(newConversation))
        fresh.toolTip="Start a new conversation for this document";fresh.setAccessibilityLabel("New AI conversation")
        for button in [close,fresh,connection,contextButton] { button.controlSize = .small;button.refusesFirstResponder=true }
        let header=NSStackView(views:[heading,fresh,close]);header.spacing=6
        sourceLabel.font = .systemFont(ofSize:11);sourceLabel.textColor = .secondaryLabelColor;sourceLabel.lineBreakMode = .byTruncatingMiddle
        connection.target=self;connection.action=#selector(connect)
        input.isRichText=false;input.allowsUndo=true;input.font = .systemFont(ofSize:13)
        input.isAutomaticQuoteSubstitutionEnabled=false;input.isAutomaticDashSubstitutionEnabled=false
        input.setAccessibilityLabel("Question for AI")
        func scroll(_ text:NSTextView) -> NSScrollView {
            let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
            text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask=[.width]
            text.textContainer?.widthTracksTextView=true;text.textContainerInset=NSSize(width:8,height:8);scroll.documentView=text
            return scroll
        }
        let history=transcript.view,composer=scroll(input)
        contextButton.target=self;contextButton.action=#selector(toggleContext)
        contextButton.isBordered=false;contextButton.alignment = .left
        contextPanel.orientation = .vertical;contextPanel.alignment = .leading;contextPanel.spacing=5
        let warning=NSTextField(wrappingLabelWithString:"Share reports, workbook data or scripts with ChatGPT for this app session? Confirm again after restarting or selecting a different data document. Do not share person-identifiable data: remove names, dates of birth, patient IDs and identifying free text.")
        warning.font = .systemFont(ofSize:11);warning.textColor = .secondaryLabelColor
        acknowledgement.cell?.wraps=true;acknowledgement.font = .systemFont(ofSize:11)
        for control in [shareScript,shareWorkbook,acknowledgement] { control.target=self;control.action=#selector(sharingChanged);control.controlSize = .small }
        acknowledgement.action=#selector(acknowledge)
        workbookPicker.target=self;workbookPicker.action=#selector(workbookChanged)
        workbookPicker.setAccessibilityLabel("Workbook to share with AI")
        let dataRow=NSStackView(views:[shareWorkbook,workbookPicker]);dataRow.spacing=6
        shareWorkbook.setContentHuggingPriority(.required,for:.horizontal)
        for child in [warning,shareScript,dataRow,acknowledgement] { contextPanel.addArrangedSubview(child) }
        let reminder=NSTextField(wrappingLabelWithString:"Your question and recent conversation go to ChatGPT when you send. Earlier shared content may remain in the conversation. Start a new conversation to leave it out.")
        reminder.font = .systemFont(ofSize:10);reminder.textColor = .secondaryLabelColor
        sendButton.target=self;sendButton.action=#selector(send);sendButton.toolTip="Send question (⌘Return)"
        stopButton.target=self;stopButton.action=#selector(stop);stopButton.isEnabled=false
        let actions=NSStackView(views:[sendButton,stopButton]);actions.spacing=8
        notice.font = .systemFont(ofSize:11);notice.textColor = .secondaryLabelColor
        let questionLabel=NSTextField(labelWithString:"Your question"),conversationLabel=NSTextField(labelWithString:"Conversation")
        for label in [questionLabel,conversationLabel] { label.font = .systemFont(ofSize:11,weight:.semibold) }
        let controls=ScriptAIControlsStack(views:[connection,contextButton,contextPanel,questionLabel,composer,actions,reminder,notice])
        controls.orientation = .vertical;controls.alignment = .leading;controls.spacing=7;controls.detachesHiddenViews=true
        controls.translatesAutoresizingMaskIntoConstraints=false
        let controlsScroll=NSScrollView();controlsScroll.hasVerticalScroller=true;controlsScroll.autohidesScrollers=true
        controlsScroll.drawsBackground=false;controlsScroll.documentView=controls
        let controlsHeight=controlsScroll.heightAnchor.constraint(equalTo:controls.heightAnchor)
        controlsHeight.priority = .defaultHigh
        // Short docks scroll the question/sharing controls instead of clipping them
        // or taking away the conversation's minimum reading area.
        openCodeButton.target=self;openCodeButton.action=#selector(openLastCode);openCodeButton.controlSize = .small
        openCodeButton.toolTip="Open the latest reply with its original data and preceding R code; review before running"
        let stack=NSStackView(views:[header,sourceLabel,controlsScroll,conversationLabel,history,openCodeButton])
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=7;stack.detachesHiddenViews=true
        stack.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(stack)
        for child in [header,sourceLabel,controlsScroll,conversationLabel,history] {
            child.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        }
        for child in [contextButton,contextPanel,questionLabel,composer,reminder,notice,warning,dataRow,acknowledgement] {
            child.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true
        }
        for child in controls.arrangedSubviews+contextPanel.arrangedSubviews+[header,sourceLabel,conversationLabel] {
            child.setContentCompressionResistancePriority(.required,for:.vertical)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:view.topAnchor,constant:8),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-8),
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:10),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-10),
            controls.topAnchor.constraint(equalTo:controlsScroll.contentView.topAnchor),controls.leadingAnchor.constraint(equalTo:controlsScroll.contentView.leadingAnchor),
            controls.widthAnchor.constraint(equalTo:controlsScroll.contentView.widthAnchor),controlsHeight,
            controlsScroll.heightAnchor.constraint(lessThanOrEqualTo:controls.heightAnchor),controlsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant:100),
            composer.heightAnchor.constraint(equalToConstant:82),history.heightAnchor.constraint(greaterThanOrEqualToConstant:100)
        ])
        history.setContentHuggingPriority(.defaultLow,for:.vertical)
    }
    func open(_ doc: Document, reportResultID: String? = nil) {
        guard ["r","report"].contains(doc.kind) else { return }
        if scriptID != doc.id {
            saveChoices();stop();scriptID=doc.id
            if conversations[doc.id]==nil { conversations[doc.id]=Conversation() }
            input.string=conversation!.draft
        }
        if let reportResultID { conversation?.reportResultID=reportResultID }
        shareScript.title=doc.kind=="report" ? "Share this report" : "Share this script and its R output"
        heading.stringValue=doc.kind=="report" ? "AI report help · ChatGPT" : "AI assistance · ChatGPT"
        shareScript.state=viewer.aiSharing.shareDocument ? .on:.off
        shareWorkbook.state=viewer.aiSharing.shareWorkbook ? .on:.off
        sourceLabel.stringValue=doc.title
        refreshWorkbooks();offerResultWorkbook(doc,resultID:reportResultID);setContextExpanded(!viewer.aiSharing.accepted);render();updateConnection()
        if !visible {
            if viewer.helpPane.visible && viewer.helpPane.view.superview === viewer.workspaceSplit { viewer.helpPane.hide() }
            visible=true;view.autoresizingMask=[.width,.height];view.translatesAutoresizingMaskIntoConstraints=true
            viewer.workspaceSplit.addArrangedSubview(view);viewer.workspaceSplit.adjustSubviews()
            viewer.workspaceSplit.setPosition(max(320,viewer.workspaceSplit.bounds.width-min(dockWidth,viewer.workspaceSplit.bounds.width-320)-viewer.workspaceSplit.dividerThickness),ofDividerAt:0)
        }
        viewer.window.makeFirstResponder(input)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { if !TutorPolicy.disabled { try await viewer.chatGPTTutor.refreshAccount() };updateConnection() }
            catch { showNotice(error.localizedDescription) }
        }
    }
    /// The workbook offered for sharing when the pane opens for a report: the one the result's record names, as the Windows pane
    /// offers it (ScriptAIPane.OfferResultWorkbookAsync, after Iain found the last activated workbook offered whatever the result
    /// came from) and as Continue in R finds it: the record's input paths and file names, or an unsaved workbook's name, against the
    /// open worksheets. The result is the one the page named; from the menu, the latest with a record. The selection goes through
    /// the viewer's data-document path, as a choice by hand does, so the session's sharing is confirmed again, and the status line
    /// names the workbook; a result without a record, or whose workbook is not open, leaves the box as it was.
    func offerResultWorkbook(_ doc: Document, resultID: String?) {
        guard doc.kind == "report" else { return }
        let entry = resultID != nil ? doc.reportEntries?.first(where:{$0.id==resultID}) : doc.lastRecordEntry
        guard let record=entry?.record, let object=(try? JSONSerialization.jsonObject(with:Data(record.utf8))) as? [String:Any] else { return }
        var names: [String] = []
        for input in object["inputs"] as? [[String:Any]] ?? [] { for key in ["path","file"] { if let name=input[key] as? String, !name.isEmpty { names.append(name) } } }
        if let source=object["source"] as? [String:Any] { for key in ["path","file"] { if let name=source[key] as? String, !name.isEmpty { names.append(name) } } }
        let grids=viewer.documents.filter{$0.kind=="grid"}
        guard let workbook=names.lazy.compactMap({ name in grids.first(where:{ $0.workbookSourceURL?.path==name || $0.workbookName==name }) }).first,
              workbookPicker.selectedItem?.representedObject as? String != workbook.id else { return }
        viewer.selectAIDataDocument(workbook.id)
        if let index=workbookPicker.itemArray.firstIndex(where:{$0.representedObject as? String==workbook.id}) { workbookPicker.selectItem(at:index) }
        saveChoices();updateControls()
        viewer.status.stringValue="The workbook offered for sharing is the result's: "+workbook.title
    }
    func activeDocumentChanged(_ doc: Document) {
        guard visible else { return }
        if ["r","report"].contains(doc.kind) && doc.id != scriptID { open(doc) } else { refreshWorkbooks() }
    }
    func refreshWorkbooks() {
        let id=viewer.aiSharing.dataDocumentID
        workbookPicker.removeAllItems()
        for doc in viewer.documents where doc.kind=="grid" { workbookPicker.addItem(withTitle:doc.title);workbookPicker.lastItem?.representedObject=doc.id }
        if let index=workbookPicker.itemArray.firstIndex(where:{$0.representedObject as? String==id}) { workbookPicker.selectItem(at:index) }
        // Losing a chosen workbook never silently authorises its replacement.
        else if id != nil { shareWorkbook.state = .off;workbookPicker.selectItem(at:-1) }
        if workbookPicker.numberOfItems==0 { shareWorkbook.state = .off }
        saveChoices();updateControls()
    }
    func updateConnection() {
        let tutor=viewer.chatGPTTutor
        connection.title=TutorPolicy.disabled ? "AI disabled by policy" : tutor.account != nil ? "ChatGPT connection…" : tutor.loginID != nil ? "Finish ChatGPT sign-in…" : "Use my ChatGPT"
        connection.isEnabled = !TutorPolicy.disabled && !isBusy
        updateControls()
    }
    @objc private func connect() {
        guard let doc=viewer.documents.first(where:{$0.id==scriptID}) else { return }
        viewer.configureLearningAI(doc)
    }
    @objc func sharingChanged() {
        if shareWorkbook.state == .on { viewer.selectAIDataDocument(workbookPicker.selectedItem?.representedObject as? String) }
        viewer.aiSharing.shareDocument=shareScript.state == .on
        viewer.aiSharing.shareWorkbook=shareWorkbook.state == .on
        saveChoices();updateControls()
    }
    @objc private func workbookChanged() {
        viewer.selectAIDataDocument(workbookPicker.selectedItem?.representedObject as? String)
        saveChoices();updateControls()
    }
    func sessionSharingChanged() {
        if isBusy { stop() }
        refreshWorkbooks();setContextExpanded(!viewer.aiSharing.accepted);updateControls()
    }
    private func saveChoices() {
        guard let chat=conversation else { return }
        chat.draft=input.string;chat.shareScript=shareScript.state == .on;chat.shareWorkbook=shareWorkbook.state == .on
        if let id=workbookPicker.selectedItem?.representedObject as? String { chat.workbookID=id }
    }
    private func updateControls() {
        let sharing=shareScript.state == .on || shareWorkbook.state == .on
        acknowledgement.state = viewer.aiSharing.accepted ? .on:.off
        acknowledgement.isHidden = !sharing;acknowledgement.isEnabled = !isBusy
        sendButton.title=sharing ? "Send with selected context" : "Send question only"
        sendButton.isEnabled = !isBusy && !TutorPolicy.disabled && viewer.chatGPTTutor.account != nil && (!sharing || viewer.aiSharing.accepted)
        stopButton.isEnabled=isBusy;shareScript.isEnabled = !isBusy
        shareWorkbook.isEnabled = !isBusy && workbookPicker.numberOfItems>0
        workbookPicker.isEnabled = !isBusy && shareWorkbook.state == .on
        updateContextTitle()
    }
    @objc private func acknowledge() {
        if acknowledgement.state == .on {
            viewer.aiSharing.approve()
            if notice.stringValue==Self.confirmationNotice { showNotice("") }
            setContextExpanded(false);viewer.window.makeFirstResponder(input)
        } else { viewer.aiSharing.revoke();setContextExpanded(true) }
        updateControls()
    }
    private func setContextExpanded(_ expanded: Bool) {
        contextPanel.isHidden = !expanded
        updateContextTitle()
    }
    private func updateContextTitle() {
        let sharing=shareScript.state == .on || shareWorkbook.state == .on
        if !contextPanel.isHidden { contextButton.title="Sharing for this session ▾" }
        else if sharing && !isBusy && acknowledgement.state != .on { contextButton.title="Confirm sharing for this data document ▸" }
        else if sharing {
            let scope=[shareScript.state == .on ? (isReport ? "report":"script and R output"):nil,shareWorkbook.state == .on ? "workbook":nil].compactMap{$0}.joined(separator:" + ")
            contextButton.title="Sharing: "+scope+" ▸"
        } else { contextButton.title="Question only · Sharing options ▸" }
        contextButton.toolTip=contextPanel.isHidden ? "Review or change what is shared with ChatGPT" : "Hide sharing options"
        contextButton.setAccessibilityValue(contextPanel.isHidden ? "Collapsed" : "Expanded")
    }
    @objc private func toggleContext() { setContextExpanded(contextPanel.isHidden) }
    func showNotice(_ text: String) { notice.stringValue=text }
    @objc func send() {
        guard !isBusy, let chat=conversation, let source=viewer.documents.first(where:{$0.id==scriptID}), !TutorPolicy.disabled else { return }
        let question=input.string.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !question.isEmpty else { showNotice("Enter a question for AI.");return }
        guard question.count<=8000 else { showNotice("Please shorten this question to 8,000 characters.");return }
        guard viewer.chatGPTTutor.account != nil else { showNotice("Choose Use my ChatGPT to connect your account first.");return }
        let sharing=shareScript.state == .on || shareWorkbook.state == .on
        guard !sharing || viewer.aiSharing.accepted else { showNotice(Self.confirmationNotice);return }
        let workbook=shareWorkbook.state == .on ? viewer.documents.first(where:{$0.kind=="grid" && $0.id==workbookPicker.selectedItem?.representedObject as? String}) : nil
        guard shareWorkbook.state != .on || workbook != nil else { showNotice("Choose an open workbook to share.");return }
        if sharing { setContextExpanded(false) }
        let token=UUID();requestID=token;replyID=UUID().uuidString;saveChoices()
        let reportMode=source.kind=="report"
        let context=ScriptAIContext(viewer:viewer,script:shareScript.state == .on && !reportMode ? source:nil,workbook:workbook,
            report:shareScript.state == .on && reportMode ? source:nil,reportResultID:chat.reportResultID,active:{[weak self] in self?.requestID==token})
        let sharedNames=[shareScript.state == .on ? source.title:nil,workbook?.title].compactMap{$0}
        activeContext=context
        let messages=chat.messages+[["id":UUID().uuidString,"rSource":context.rSource,"role":"user","text":question,"context":sharedNames.isEmpty ? "Question and conversation only" : "Shared for this question: " + sharedNames.joined(separator:"; ")]]
        partial="";showNotice(sharing ? "Sending the approved context to ChatGPT…" : "Sending your question and conversation only…")
        task=Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if requestID==token { task=nil;requestID=nil;activeContext=nil;updateConnection() } }
            do {
                let reference=try await context.context();try context.check()
                // This conversation's history is bounded by the existing provider client.
                chat.messages=messages;input.string="";chat.draft="";render()
                let reply=try await viewer.chatGPTTutor.converse(context:reference,messages:messages,tools:context.tools,purpose:reportMode ? .report:.script,progress:{[weak self] text in
                    guard let self,self.requestID==token else { return };self.partial=text;self.render()
                },toolHandler:{ name,args in try await context.call(name,args) })
                try context.check();chat.messages.append(["id":replyID,"rData":context.rData,"role":"assistant","text":reply.text]);partial="";render()
                showNotice(reportMode ? "Reply received. Ask a follow-up about the interpretation or method." : "Reply received. Review suggested code before running it in R.")
            } catch {
                guard requestID==token else { return }
                if !partial.isEmpty { chat.messages.append(["id":replyID,"rData":activeContext?.rData ?? "","role":"assistant","text":partial+"\n[Reply stopped before completion.]"]);partial="" }
                render();showNotice(error is CancellationError ? "Reply stopped." : error.localizedDescription)
                if input.string.isEmpty { input.string=question;chat.draft=question }
            }
        }
        updateControls()
    }
    @objc func stop() {
        if let chat=conversation, !partial.isEmpty { chat.messages.append(["id":replyID,"rData":activeContext?.rData ?? "","role":"assistant","text":partial+"\n[Reply stopped before completion.]"]) }
        task?.cancel();task=nil;requestID=nil;activeContext=nil;partial="";render();updateConnection()
    }
    @objc func hide() {
        guard visible else { return };saveChoices();stop();dockWidth=view.frame.width;visible=false
        view.removeFromSuperview();viewer.workspaceSplit.adjustSubviews()
        if let doc=viewer.active, let pane=doc.rPane { viewer.window.makeFirstResponder(pane.editor) }
        else if let doc=viewer.active, doc.kind=="report" { viewer.window.makeFirstResponder(doc.web) }
    }
    @objc func newConversation() {
        guard let id=scriptID else { return };stop();conversations[id]=Conversation();input.string=""
        refreshWorkbooks();setContextExpanded(!viewer.aiSharing.accepted);render();showNotice("New conversation: earlier questions and replies are cleared. Your session sharing choice is unchanged.")
    }
    func documentClosed(_ doc: Document) {
        if doc.id==scriptID { hide();scriptID=nil }
        conversations.removeValue(forKey:doc.id)
        if visible { refreshWorkbooks() }
    }
    func shutdown() { task?.cancel();task=nil;requestID=nil;activeContext=nil;transcript.shutdown() }
    @objc func openLastCode() {
        guard let chat=conversation, let index=chat.messages.lastIndex(where:{$0["role"]=="assistant"}), let id=chat.messages[index]["id"] else { return }
        openCode(generation:chat.generation,messageID:id)
    }
    func openCode(generation: String,messageID: String,blockIndex: Int = -1) {
        guard let chat=conversation, chat.generation==generation else { return }
        guard let index=chat.messages.firstIndex(where:{$0["id"]==messageID}) else { showNotice("Wait for the reply to finish before opening its R code.");return }
        do {
            let code=try ConversationRScript.build(chat.messages,messageIndex:index,blockIndex:blockIndex)
            viewer.makeRScript(script:code,title:"AI suggestion",saved:false)
            viewer.status.stringValue="Review the source, earlier examples and suggested R code before choosing Run"
        } catch { showNotice(error.localizedDescription) }
    }
    private func copyCode(generation: String,messageID: String,code: String) {
        guard let chat=conversation,chat.generation==generation,code.utf8.count<=200000,
              let row=chat.messages.first(where:{$0["id"]==messageID}),row["text"]?.contains(code)==true else { return }
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(code,forType:.string)
    }
    private func render() {
        let messages=conversation?.messages ?? []
        openCodeButton.isEnabled = messages.last(where:{$0["role"]=="assistant"}).map{!ConversationRScript.blocks($0["text"] ?? "").isEmpty} ?? false
        var rows: [[String:Any]]=messages.map { row in
            ["id":row["id"] ?? "", "role":row["role"] ?? "assistant", "text":row["text"] ?? "", "context":row["context"] ?? ""]
        }
        if !partial.isEmpty { rows.append(["id":replyID,"role":"assistant","text":partial,"pending":true]) }
        let intro=isReport ? "Ask what your results mean, how the method works, or which assumptions to check."
            : "Ask for help understanding, improving or debugging your R script."
        transcript.render(["generation":conversation?.generation ?? "", "messages":rows,
            "introduction":intro+"\n\nChoose whether to share documents or ask a question without them. Nothing is sent until you press Send."])
    }
}
