import Cocoa

@MainActor
final class CalculatorInput: NSTextView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
    var calculate: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if [36,76].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            if event.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(nil) }
            else { calculate?() }
        } else { super.keyDown(with:event) }
    }
}

// A session tool, not a document: hiding or moving it keeps the same input view,
// undo history, results and saved expressions. Help occupies the other split.
@MainActor
final class CalculatorPane: NSObject, NSSplitViewDelegate, NSWindowDelegate, NSTextViewDelegate {
    struct Calculation { let expression: String; let result: String }
    let view = NSView()
    let input = CalculatorInput()
    let result = NSTextView()
    let inputScroll = NSScrollView()
    let modeButton = NSButton(title:"Pop out",target:nil,action:nil)
    let calculateButton = NSButton(title:"Calculate",target:nil,action:nil)
    let saveButton = NSButton(title:"Save",target:nil,action:nil)
    let copyResultButton = NSButton(title:"Copy result",target:nil,action:nil)
    let savedMenu = NSPopUpButton()
    let recallButton = NSButton(title:"Recall",target:nil,action:nil)
    let insertButton = NSButton(title:"Insert",target:nil,action:nil)
    let deleteButton = NSButton(title:"Remove",target:nil,action:nil)
    let copyButton = NSButton(title:"Copy saved",target:nil,action:nil)
    weak var owner: NSWindow?
    weak var split: NSSplitView?
    private(set) var floatingWindow: NSPanel?
    private(set) var visible = false
    private(set) var prefersFloating = false
    private(set) var temporarilyFloating = false
    private(set) var dockHeight: CGFloat = 250
    private(set) var busy = false
    private(set) var saved: [Calculation] = []
    private var lastAnswer: String?
    private var timer: Timer?
    var evaluate: ((String, @escaping (Result<String,Error>) -> Void) -> Void)?
    var showHelp: (() -> Void)?

    override init() {
        super.init()
        let top = NSStackView(); top.spacing = 4
        let heading = NSTextField(labelWithString:"Calculator")
        heading.font = .systemFont(ofSize:12,weight:.semibold)
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let help = NSButton(title:"Help",target:self,action:#selector(help))
        let close = NSButton(title:"×",target:self,action:#selector(hide))
        close.setAccessibilityLabel("Close calculator"); close.toolTip = "Close calculator"
        modeButton.target = self; modeButton.action = #selector(toggleMode)
        for item in [heading,help,modeButton,close] { top.addArrangedSubview(item) }
        input.isRichText = false; input.allowsUndo = true; input.delegate = self
        input.font = .monospacedSystemFont(ofSize:13,weight:.regular)
        input.isAutomaticQuoteSubstitutionEnabled = false; input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false; input.isAutomaticSpellingCorrectionEnabled = false
        input.isContinuousSpellCheckingEnabled = false
        input.setAccessibilityLabel("Calculator expression")
        configure(input,in:inputScroll)
        input.calculate = { [weak self] in self?.calculate() }
        let actions = NSStackView(); actions.spacing = 4
        calculateButton.target = self; calculateButton.action = #selector(calculate)
        saveButton.target = self; saveButton.action = #selector(save)
        saveButton.toolTip = "Calculate and save the expression and result for this session"
        copyResultButton.target = self; copyResultButton.action = #selector(copyResult); copyResultButton.isEnabled = false
        let hint = NSTextField(labelWithString:"Enter: calculate · Shift+Enter: new line")
        hint.font = .systemFont(ofSize:10); hint.textColor = .secondaryLabelColor; hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        for item in [calculateButton,saveButton,copyResultButton,hint] { actions.addArrangedSubview(item) }
        let resultScroll = NSScrollView()
        result.isEditable = false; result.isRichText = false; result.font = .monospacedSystemFont(ofSize:13,weight:.regular)
        result.setAccessibilityLabel("Calculator result"); configure(result,in:resultScroll)
        let history = NSStackView(); history.spacing = 4
        savedMenu.setAccessibilityLabel("Saved calculations")
        savedMenu.target = self; savedMenu.action = #selector(selectionChanged)
        savedMenu.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        savedMenu.widthAnchor.constraint(greaterThanOrEqualToConstant:100).isActive = true
        deleteButton.target = self; deleteButton.action = #selector(deleteSaved)
        copyButton.target = self; copyButton.action = #selector(copySaved)
        recallButton.target = self; recallButton.action = #selector(recallSaved)
        recallButton.toolTip = "Replace the expression and result with the selected saved calculation"
        insertButton.target = self; insertButton.action = #selector(useSaved)
        insertButton.toolTip = "Insert the saved expression at the caret or replace selected text"
        for item in [recallButton,insertButton,deleteButton,copyButton] { history.addArrangedSubview(item) }
        for button in [help,modeButton,close,calculateButton,saveButton,copyResultButton,recallButton,insertButton,deleteButton,copyButton] { button.controlSize = .small; button.refusesFirstResponder = true }
        for child in [top,inputScroll,actions,resultScroll,savedMenu,history] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:view.topAnchor,constant:4), top.heightAnchor.constraint(equalToConstant:25),
            inputScroll.topAnchor.constraint(equalTo:top.bottomAnchor,constant:4), inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant:45),
            actions.topAnchor.constraint(equalTo:inputScroll.bottomAnchor,constant:3), actions.heightAnchor.constraint(equalToConstant:26),
            resultScroll.topAnchor.constraint(equalTo:actions.bottomAnchor,constant:3), resultScroll.heightAnchor.constraint(equalToConstant:38),
            savedMenu.topAnchor.constraint(equalTo:resultScroll.bottomAnchor,constant:3), savedMenu.heightAnchor.constraint(equalToConstant:26),
            history.topAnchor.constraint(equalTo:savedMenu.bottomAnchor,constant:3), history.heightAnchor.constraint(equalToConstant:26), history.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-5)
        ])
        for child in [top,inputScroll,actions,resultScroll,savedMenu,history] {
            child.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8).isActive = true
            child.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8).isActive = true
        }
        refreshSaved()
    }
    private func configure(_ text: NSTextView, in scroll: NSScrollView) {
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]; text.textContainerInset = NSSize(width:4,height:4)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width:0,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
    }
    func attach(to split: NSSplitView, owner: NSWindow) {
        self.split = split; self.owner = owner; split.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshModalPresentation() } }
    }
    func shutdown() { timer?.invalidate(); timer = nil; floatingWindow?.orderOut(nil) }
    var isFocused: Bool { visible && ((floatingWindow != nil && NSApp.keyWindow === floatingWindow) || (NSApp.keyWindow === owner && (owner?.firstResponder as? NSView)?.isDescendant(of:view) == true)) }
    var hasModal: Bool { owner?.attachedSheet != nil || (NSApp.modalWindow != nil && NSApp.modalWindow !== floatingWindow) }
    func open() {
        if !visible { visible = true; temporarilyFloating = hasModal && !prefersFloating; place(floating:prefersFloating || hasModal,activate:false) }
        refreshModalPresentation()
        view.window?.makeKeyAndOrderFront(nil); view.window?.makeFirstResponder(input)
    }
    @objc func help() { showHelp?() }
    @objc func calculate() { run(save:false) }
    @objc func save() { run(save:true) }
    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === input else { return }
        lastAnswer = nil; result.string = ""; copyResultButton.isEnabled = false
    }
    private func run(save: Bool) {
        guard !busy, let evaluate else { return }
        let expression = input.string
        busy = true; calculateButton.isEnabled = false; saveButton.isEnabled = false; input.isEditable = false; savedMenu.isEnabled = false
        lastAnswer = nil; copyResultButton.isEnabled = false; selectionChanged()
        result.textColor = .secondaryLabelColor; result.string = "Calculating…"
        evaluate(expression) { [weak self] output in
            guard let self else { return }
            self.busy = false; self.calculateButton.isEnabled = true; self.saveButton.isEnabled = true; self.input.isEditable = true
            switch output {
            case .success(let answer):
                self.result.textColor = .labelColor; self.result.string = answer
                self.lastAnswer = answer; self.copyResultButton.isEnabled = !answer.isEmpty
                if save { self.saved.append(Calculation(expression:expression,result:answer)); self.refreshSaved(select:self.saved.count - 1) }
            case .failure(let error): self.result.textColor = .systemRed; self.result.string = error.localizedDescription
            }
            self.savedMenu.isEnabled = !self.saved.isEmpty
            self.selectionChanged()
            self.result.scrollRangeToVisible(NSRange(location:0,length:0))
        }
    }
    private func refreshSaved(select: Int? = nil) {
        savedMenu.removeAllItems(); savedMenu.addItem(withTitle:"Saved calculations"); savedMenu.lastItem?.tag = -1; savedMenu.lastItem?.isEnabled = false
        for (index, entry) in saved.enumerated() {
            // Only the menu label is flattened; the saved expression stays exact.
            let label = savedLabel(entry)
            let item = NSMenuItem(title:String(label.prefix(120)),action:nil,keyEquivalent:"")
            item.tag = index; item.toolTip = entry.expression + " = " + entry.result; savedMenu.menu?.addItem(item)
        }
        if let select, saved.indices.contains(select) { savedMenu.selectItem(withTag:select) }
        savedMenu.isEnabled = !saved.isEmpty && !busy; copyButton.isEnabled = !saved.isEmpty
        selectionChanged()
    }
    private func savedLabel(_ entry: Calculation) -> String {
        entry.expression.replacingOccurrences(of:"\r",with:" ").replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\t",with:" ") + " = " + entry.result
    }
    @objc func selectionChanged() {
        let selected = saved.indices.contains(savedMenu.selectedItem?.tag ?? -1)
        recallButton.isEnabled = selected && !busy; insertButton.isEnabled = selected && !busy; deleteButton.isEnabled = selected && !busy
    }
    @objc func recallSaved() {
        guard !busy, let index = savedMenu.selectedItem?.tag, saved.indices.contains(index) else { return }
        let entry = saved[index]
        input.insertText(entry.expression,replacementRange:NSRange(location:0,length:(input.string as NSString).length))
        lastAnswer = entry.result; result.string = entry.result; result.textColor = .labelColor
        copyResultButton.isEnabled = !entry.result.isEmpty; view.window?.makeFirstResponder(input)
    }
    @objc func copyResult() {
        guard let answer = lastAnswer, !answer.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(answer,forType:.string)
    }
    @objc func useSaved() {
        guard !busy, let index = savedMenu.selectedItem?.tag, saved.indices.contains(index) else { return }
        input.insertText(saved[index].expression,replacementRange:input.selectedRange())
        deleteButton.isEnabled = true; view.window?.makeFirstResponder(input)
    }
    @objc func deleteSaved() {
        guard !busy, let index = savedMenu.selectedItem?.tag, saved.indices.contains(index) else { return }
        saved.remove(at:index); refreshSaved()
    }
    @objc func copySaved() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(saved.map(savedLabel).joined(separator:"\n"),forType:.string)
    }
    @objc func toggleMode() {
        guard !hasModal else { return }
        prefersFloating.toggle(); place(floating:prefersFloating,activate:true)
    }
    func refreshModalPresentation() {
        guard visible else { return }
        modeButton.isEnabled = !hasModal
        if hasModal && view.window === owner { temporarilyFloating = !prefersFloating; place(floating:true,activate:false) }
        else if !hasModal && temporarilyFloating { temporarilyFloating = false; place(floating:prefersFloating,activate:false) }
        floatingWindow?.level = hasModal ? .modalPanel : .normal
    }
    private func place(floating: Bool, activate: Bool) {
        guard let split, let owner else { return }
        let selection = input.selectedRange(), position = inputScroll.contentView.bounds.origin
        let focused = isFocused, responder = view.window?.firstResponder
        let returnFocus = !floating && floatingWindow?.isKeyWindow == true
        if view.superview === split { dockHeight = view.frame.height }
        view.removeFromSuperview()
        if floating {
            if floatingWindow == nil {
                let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:600,height:310),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
                panel.title = "StatsDirect Calculator"; panel.minSize = NSSize(width:320,height:255); panel.isReleasedWhenClosed = false
                panel.worksWhenModal = true; panel.hidesOnDeactivate = false; panel.delegate = self; panel.center(); floatingWindow = panel
            }
            view.autoresizingMask = [.width,.height]; view.translatesAutoresizingMaskIntoConstraints = true
            floatingWindow!.contentView = view; floatingWindow!.level = hasModal ? .modalPanel : .normal
            if activate { floatingWindow!.makeKeyAndOrderFront(nil) } else { floatingWindow!.orderFront(nil) }
            modeButton.title = "Dock"
        } else {
            floatingWindow?.contentView = nil; floatingWindow?.orderOut(nil)
            view.translatesAutoresizingMaskIntoConstraints = true; view.autoresizingMask = [.width,.height]
            split.addArrangedSubview(view); split.adjustSubviews()
            split.setPosition(max(150,split.bounds.height - min(dockHeight,split.bounds.height - 150) - split.dividerThickness),ofDividerAt:0)
            modeButton.title = "Pop out"
            if returnFocus { (owner.attachedSheet ?? owner).makeKeyAndOrderFront(nil) }
        }
        split.adjustSubviews(); modeButton.isEnabled = !hasModal
        if activate && focused { view.window?.makeFirstResponder(responder ?? input) }
        input.setSelectedRange(selection); inputScroll.contentView.scroll(to:position); inputScroll.reflectScrolledClipView(inputScroll.contentView)
    }
    @objc func hide() {
        guard visible else { return }
        let focused = isFocused
        if view.superview === split { dockHeight = view.frame.height }
        visible = false; temporarilyFloating = false
        view.removeFromSuperview(); floatingWindow?.orderOut(nil); split?.adjustSubviews()
        if focused && owner?.isVisible == true { (owner?.attachedSheet ?? owner)?.makeKeyAndOrderFront(nil) }
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool { hide(); return false }
    func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int) -> CGFloat { 150 }
    func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int) -> CGFloat { max(150,splitView.bounds.height - 220) }
    func splitView(_ splitView:NSSplitView,shouldAdjustSizeOfSubview view:NSView) -> Bool { view !== self.view }
}

extension Viewer {
    @objc func showCalculator() { calculatorPane.open() }
    func calculatorHelp() { if let url = helpPane.url(for:"1020") { helpPane.open(url) } }
}
