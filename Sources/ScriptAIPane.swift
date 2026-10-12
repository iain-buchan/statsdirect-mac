import Cocoa

@MainActor private final class ScriptAIControlsStack: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor final class ScriptAIPane: NSObject {
    private static let confirmationNotice="Check the selected content for person identifiers, then confirm before sending."
    final class Conversation {
        var messages: [[String:String]]=[]
        var draft=""
        var shareScript=false
        var shareWorkbook=false
        var workbookID: String?
    }
    unowned let viewer: Viewer
    let view=NSView()
    let transcript=NSTextView()
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
    let contextButton=NSButton(title:"Sharing for this question ▾",target:nil,action:nil)
    let contextPanel=NSStackView()
    private(set) var visible=false
    private(set) var scriptID: String?
    private(set) var conversations: [String:Conversation]=[:]
    private(set) var requestID: UUID?
    private var task: Task<Void,Never>?
    private var partial=""
    private weak var renderedConversation: Conversation?
    private var dockWidth: CGFloat=460
    private var conversation: Conversation? { scriptID.flatMap{conversations[$0]} }
    var isBusy: Bool { task != nil }
    var isFocused: Bool { visible && NSApp.keyWindow === viewer.window && (viewer.window.firstResponder as? NSView)?.isDescendant(of:view) == true }

    init(viewer: Viewer) {
        self.viewer=viewer;super.init()
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let close=NSButton(title:"×",target:self,action:#selector(hide));close.setAccessibilityLabel("Close AI assistance")
        let fresh=NSButton(image:NSImage(systemSymbolName:"square.and.pencil",accessibilityDescription:"New AI conversation")!,target:self,action:#selector(newConversation))
        fresh.toolTip="Start a new conversation for this script";fresh.setAccessibilityLabel("New AI conversation")
        for button in [close,fresh,connection,contextButton] { button.controlSize = .small;button.refusesFirstResponder=true }
        let header=NSStackView(views:[heading,fresh,close]);header.spacing=6
        sourceLabel.font = .systemFont(ofSize:11);sourceLabel.textColor = .secondaryLabelColor;sourceLabel.lineBreakMode = .byTruncatingMiddle
        connection.target=self;connection.action=#selector(connect)
        transcript.isEditable=false;transcript.isSelectable=true;transcript.isRichText=true
        transcript.setAccessibilityLabel("AI conversation")
        input.isRichText=false;input.allowsUndo=true;input.font = .systemFont(ofSize:13)
        input.isAutomaticQuoteSubstitutionEnabled=false;input.isAutomaticDashSubstitutionEnabled=false
        input.setAccessibilityLabel("Question for AI")
        func scroll(_ text:NSTextView) -> NSScrollView {
            let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
            text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask=[.width]
            text.textContainer?.widthTracksTextView=true;text.textContainerInset=NSSize(width:8,height:8);scroll.documentView=text
            return scroll
        }
        let history=scroll(transcript),composer=scroll(input)
        contextButton.target=self;contextButton.action=#selector(toggleContext)
        contextButton.isBordered=false;contextButton.alignment = .left
        contextPanel.orientation = .vertical;contextPanel.alignment = .leading;contextPanel.spacing=5
        let warning=NSTextField(wrappingLabelWithString:"Share workbook data or scripts with ChatGPT? Do not share person-identifiable data: remove names, dates of birth, patient IDs and identifying free text.")
        warning.font = .systemFont(ofSize:11);warning.textColor = .secondaryLabelColor
        acknowledgement.cell?.wraps=true;acknowledgement.font = .systemFont(ofSize:11)
        for control in [shareScript,shareWorkbook,acknowledgement] { control.target=self;control.action=#selector(sharingChanged);control.controlSize = .small }
        acknowledgement.action=#selector(acknowledge)
        workbookPicker.target=self;workbookPicker.action=#selector(sharingChanged)
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
        let stack=NSStackView(views:[header,sourceLabel,controlsScroll,conversationLabel,history])
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
    func open(_ doc: Document) {
        guard doc.kind=="r" else { return }
        if scriptID != doc.id {
            saveChoices();stop();scriptID=doc.id
            if conversations[doc.id]==nil { let chat=Conversation();chat.workbookID=viewer.documents.first(where:{$0.kind=="grid" && $0.id==viewer.analysisSourceID})?.id ?? viewer.documents.last(where:{$0.kind=="grid"})?.id;conversations[doc.id]=chat }
            input.string=conversation!.draft;shareScript.state=conversation!.shareScript ? .on:.off;shareWorkbook.state=conversation!.shareWorkbook ? .on:.off
        }
        acknowledgement.state = .off;setContextExpanded(true)
        sourceLabel.stringValue=doc.title
        refreshWorkbooks();render();updateConnection()
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
    func activeDocumentChanged(_ doc: Document) {
        guard visible else { return }
        if doc.kind=="r" && doc.id != scriptID { open(doc) } else { refreshWorkbooks() }
    }
    func refreshWorkbooks() {
        let id=conversation?.workbookID
        workbookPicker.removeAllItems()
        for doc in viewer.documents where doc.kind=="grid" { workbookPicker.addItem(withTitle:doc.title);workbookPicker.lastItem?.representedObject=doc.id }
        if let index=workbookPicker.itemArray.firstIndex(where:{$0.representedObject as? String==id}) { workbookPicker.selectItem(at:index) }
        // Losing a chosen workbook never silently authorises its replacement.
        else if id != nil { shareWorkbook.state = .off }
        if workbookPicker.numberOfItems==0 { shareWorkbook.state = .off }
        sharingChanged()
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
        acknowledgement.state = .off;setContextExpanded(true);saveChoices();updateControls()
    }
    private func saveChoices() {
        guard let chat=conversation else { return }
        chat.draft=input.string;chat.shareScript=shareScript.state == .on;chat.shareWorkbook=shareWorkbook.state == .on
        if let id=workbookPicker.selectedItem?.representedObject as? String { chat.workbookID=id }
    }
    private func updateControls() {
        let sharing=shareScript.state == .on || shareWorkbook.state == .on
        acknowledgement.isHidden = !sharing;acknowledgement.isEnabled = !isBusy
        sendButton.title=sharing ? "Send with selected context" : "Send question only"
        sendButton.isEnabled = !isBusy && !TutorPolicy.disabled && viewer.chatGPTTutor.account != nil && (!sharing || acknowledgement.state == .on)
        stopButton.isEnabled=isBusy;shareScript.isEnabled = !isBusy
        shareWorkbook.isEnabled = !isBusy && workbookPicker.numberOfItems>0
        workbookPicker.isEnabled = !isBusy && shareWorkbook.state == .on
        updateContextTitle()
    }
    @objc private func acknowledge() {
        updateControls()
        if acknowledgement.state == .on && (shareScript.state == .on || shareWorkbook.state == .on) {
            if notice.stringValue==Self.confirmationNotice { showNotice("") }
            setContextExpanded(false)
            viewer.window.makeFirstResponder(input)
        }
    }
    private func setContextExpanded(_ expanded: Bool) {
        contextPanel.isHidden = !expanded
        updateContextTitle()
    }
    private func updateContextTitle() {
        let sharing=shareScript.state == .on || shareWorkbook.state == .on
        if !contextPanel.isHidden { contextButton.title="Sharing for this question ▾" }
        else if sharing && !isBusy && acknowledgement.state != .on { contextButton.title="Review sharing for the next question ▸" }
        else if sharing {
            let scope=[shareScript.state == .on ? "script and R output":nil,shareWorkbook.state == .on ? "workbook":nil].compactMap{$0}.joined(separator:" + ")
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
        guard !sharing || acknowledgement.state == .on else { showNotice(Self.confirmationNotice);return }
        let workbook=shareWorkbook.state == .on ? viewer.documents.first(where:{$0.kind=="grid" && $0.id==workbookPicker.selectedItem?.representedObject as? String}) : nil
        guard shareWorkbook.state != .on || workbook != nil else { showNotice("Choose an open workbook to share.");return }
        let token=UUID();requestID=token;saveChoices()
        let context=ScriptAIContext(viewer:viewer,script:shareScript.state == .on ? source:nil,workbook:workbook,active:{[weak self] in self?.requestID==token})
        let sharedNames=[shareScript.state == .on ? source.title:nil,workbook?.title].compactMap{$0}
        let messages=chat.messages+[["role":"user","text":question,"context":sharedNames.isEmpty ? "Question and conversation only" : "Shared for this question: " + sharedNames.joined(separator:"; ")]]
        partial="";showNotice(sharing ? "Sending the approved context to ChatGPT…" : "Sending your question and conversation only…")
        task=Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if requestID==token { task=nil;requestID=nil;acknowledgement.state = .off;updateConnection() } }
            do {
                let reference=try await context.context();try context.check()
                // This conversation's history is bounded by the existing provider client.
                chat.messages=messages;input.string="";chat.draft="";render()
                let reply=try await viewer.chatGPTTutor.converse(context:reference,messages:messages,tools:context.tools,purpose:.script,progress:{[weak self] text in
                    guard let self,self.requestID==token else { return };self.partial=text;self.render()
                },toolHandler:{ name,args in try await context.call(name,args) })
                try context.check();chat.messages.append(["role":"assistant","text":reply.text]);partial="";render()
                showNotice("Reply received. Review suggested code before running it in R.")
            } catch {
                guard requestID==token else { return }
                if !partial.isEmpty { chat.messages.append(["role":"assistant","text":partial+"\n[Reply stopped before completion.]"]);partial="" }
                render();showNotice(error is CancellationError ? "Reply stopped." : error.localizedDescription)
                if input.string.isEmpty { input.string=question;chat.draft=question }
            }
        }
        // Confirmation is for this request only; changing scope clears it as well.
        acknowledgement.state = .off;updateControls()
    }
    @objc func stop() {
        if let chat=conversation, !partial.isEmpty { chat.messages.append(["role":"assistant","text":partial+"\n[Reply stopped before completion.]"]) }
        task?.cancel();task=nil;requestID=nil;partial="";acknowledgement.state = .off;render();updateConnection()
    }
    @objc func hide() {
        guard visible else { return };saveChoices();stop();dockWidth=view.frame.width;visible=false
        view.removeFromSuperview();viewer.workspaceSplit.adjustSubviews()
        if let doc=viewer.active, let pane=doc.rPane { viewer.window.makeFirstResponder(pane.editor) }
    }
    @objc func newConversation() {
        guard let id=scriptID else { return };stop();conversations[id]=Conversation();input.string="";shareScript.state = .off;shareWorkbook.state = .off
        acknowledgement.state = .off;refreshWorkbooks();render();showNotice("New conversation: no earlier questions, replies or shared content will be included.")
    }
    func documentClosed(_ doc: Document) {
        if doc.id==scriptID { hide();scriptID=nil }
        conversations.removeValue(forKey:doc.id)
        if visible { refreshWorkbooks() }
    }
    func shutdown() { task?.cancel();task=nil;requestID=nil }
    private func render() {
        let text=NSMutableAttributedString()
        func add(_ value:String,_ attributes:[NSAttributedString.Key:Any]) { text.append(NSAttributedString(string:value,attributes:attributes)) }
        let normal: [NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.textColor]
        let messages=conversation?.messages ?? []
        if messages.isEmpty { add("Ask for help understanding, improving or debugging your R script.\n\nChoose above whether to share workbook data and scripts, or send a question without documents. Nothing is sent until you press Send.",normal) }
        for row in messages + (partial.isEmpty ? [] : [["role":"assistant","text":partial]]) {
            add((row["role"]=="user" ? "You" : "ChatGPT")+"\n",[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.secondaryLabelColor])
            if let context=row["context"] { add(context+"\n",[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.secondaryLabelColor]) }
            var code=false
            for line in (row["text"] ?? "").components(separatedBy:"\n") {
                if line.hasPrefix("```") { code.toggle();continue }
                add(line+"\n",code ? [.font:NSFont.monospacedSystemFont(ofSize:12,weight:.regular),.foregroundColor:NSColor.textColor] : normal)
            }
            add("\n",normal)
        }
        guard let storage=transcript.textStorage else { return }
        let sameConversation=renderedConversation === conversation
        var prefix=0
        if sameConversation {
            for (old,new) in zip(storage.string.utf16,text.string.utf16) {
                if old != new { break };prefix+=1
            }
            // A completed code fence can change formatting without changing text.
            var offset=0
            while offset<prefix {
                var oldRun=NSRange(),newRun=NSRange()
                let old=storage.attributes(at:offset,effectiveRange:&oldRun)
                let new=text.attributes(at:offset,effectiveRange:&newRun)
                if !NSDictionary(dictionary:old).isEqual(to:new) { prefix=offset;break }
                offset=min(prefix,NSMaxRange(oldRun),NSMaxRange(newRun))
            }
            if prefix==storage.length && prefix==text.length { return }
        }
        // Never split a surrogate pair or a composed character at the edit boundary.
        if prefix<storage.length { prefix=min(prefix,(storage.string as NSString).rangeOfComposedCharacterSequence(at:prefix).location) }
        if prefix<text.length { prefix=min(prefix,(text.string as NSString).rangeOfComposedCharacterSequence(at:prefix).location) }
        let scroll=transcript.enclosingScrollView,clip=scroll?.contentView
        if let container=transcript.textContainer { transcript.layoutManager?.ensureLayout(for:container) }
        let origin=clip?.bounds.origin ?? .zero
        let selections=transcript.selectedRanges.map(\.rangeValue)
        let followEnd = !sameConversation || (selections.allSatisfy{$0.length==0} && (clip?.documentVisibleRect.maxY ?? 0)>=transcript.bounds.maxY-3)
        storage.beginEditing()
        storage.replaceCharacters(in:NSRange(location:prefix,length:storage.length-prefix),with:text.attributedSubstring(from:NSRange(location:prefix,length:text.length-prefix)))
        storage.endEditing()
        renderedConversation=conversation
        if sameConversation {
            transcript.selectedRanges=selections.map { range in
                let start=min(range.location,text.length)
                return NSValue(range:NSRange(location:start,length:min(range.length,text.length-start)))
            }
        } else { transcript.setSelectedRange(NSRange(location:0,length:0)) }
        if let container=transcript.textContainer { transcript.layoutManager?.ensureLayout(for:container) }
        if followEnd { transcript.scrollToEndOfDocument(nil) }
        else if let clip { clip.scroll(to:origin);scroll?.reflectScrolledClipView(clip) }
    }
}
