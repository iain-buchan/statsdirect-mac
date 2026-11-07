import Cocoa

private final class HelpIndexPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A temporary native keyword picker. Selection alone never navigates.
@MainActor
final class HelpIndexPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let panel: NSPanel = HelpIndexPanel(contentRect:NSRect(x:0,y:0,width:440,height:460),
                                      styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    let filter = NSSearchField()
    let table = NSTableView()
    private let count = NSTextField(labelWithString:"")
    private let target = NSTextField(labelWithString:"")
    private var catalog: HelpKeywordIndex?
    private(set) var rows: [HelpKeywordIndex.Row] = []
    private var shown = false
    private var monitors: [Any] = []
    private weak var anchor: NSButton?
    var onChoose: ((HelpKeywordIndex.Entry) -> Void)?
    var isVisible: Bool { shown && panel.isVisible }

    override init() {
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.hidesOnDeactivate = true
        panel.worksWhenModal = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.delegate = self
        panel.title = "Help index"
        panel.setAccessibilityLabel("Help index")
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.layer?.cornerRadius = 8
        panel.contentView = content
        filter.placeholderString = "Type a keyword"
        filter.setAccessibilityLabel("Filter index keywords")
        filter.delegate = self
        filter.sendsSearchStringImmediately = true
        count.font = .systemFont(ofSize:11)
        count.textColor = .secondaryLabelColor
        target.font = .systemFont(ofSize:11)
        target.maximumNumberOfLines = 2
        target.lineBreakMode = .byTruncatingTail
        target.setAccessibilityLabel("Selected index topic")
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("keyword"))
        column.width = 410
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 23
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clickedRow)
        table.setAccessibilityLabel("Help keyword index")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        for item in [filter,count,scroll,target] {
            item.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(item)
        }
        NSLayoutConstraint.activate([
            filter.topAnchor.constraint(equalTo:content.topAnchor,constant:10),
            filter.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:10),
            filter.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-10),
            count.topAnchor.constraint(equalTo:filter.bottomAnchor,constant:5),
            count.leadingAnchor.constraint(equalTo:filter.leadingAnchor),count.trailingAnchor.constraint(equalTo:filter.trailingAnchor),
            count.heightAnchor.constraint(equalToConstant:18),
            scroll.topAnchor.constraint(equalTo:count.bottomAnchor,constant:4),
            scroll.leadingAnchor.constraint(equalTo:filter.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:filter.trailingAnchor),
            target.topAnchor.constraint(equalTo:scroll.bottomAnchor,constant:6),
            target.leadingAnchor.constraint(equalTo:filter.leadingAnchor),target.trailingAnchor.constraint(equalTo:filter.trailingAnchor),
            target.heightAnchor.constraint(equalToConstant:38),target.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-8)
        ])
        filter.nextKeyView = table
        table.nextKeyView = filter
    }

    func show(_ catalog: HelpKeywordIndex, relativeTo button: NSButton) {
        close()
        self.catalog = catalog
        anchor = button
        applyFilter()
        guard let owner = button.window else { return }
        let screen = owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? owner.frame
        let buttonRect = owner.convertToScreen(button.convert(button.bounds,to:nil))
        let size = NSSize(width:min(440,screen.width - 16),height:min(460,screen.height - 16))
        var point = NSPoint(x:buttonRect.minX,y:buttonRect.minY - size.height - 4)
        point.x = max(screen.minX + 8,min(point.x,screen.maxX - size.width - 8))
        point.y = max(screen.minY + 8,min(point.y,screen.maxY - size.height - 8))
        panel.setFrame(NSRect(origin:point,size:size),display:false)
        owner.addChildWindow(panel,ordered:.above)
        shown = true
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleKey(event) == true }
                return handled ? nil : event
            },
            NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible, event.window !== self.panel else { return }
                    if let anchor = self.anchor, event.window === anchor.window,
                       anchor.bounds.contains(anchor.convert(event.locationInWindow,from:nil)) { return }
                    self.close()
                }
                return event
            }
        ].compactMap { $0 }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(filter)
        filter.selectText(nil)
    }

    func close(returnFocus: Bool = false) {
        let wasVisible = shown
        shown = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if returnFocus, wasVisible, NSApp.isActive, let anchor, let window = anchor.window {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(anchor)
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible, event.window === panel || panel.isKeyWindow,
              event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: close(returnFocus:true); return true
        case 36,76: choose(); return true
        case 48:
            if filter.currentEditor() != nil, !rows.isEmpty { panel.makeFirstResponder(table) }
            else { panel.makeFirstResponder(filter); filter.selectText(nil) }
            return true
        case 125,126:
            guard !rows.isEmpty else { return true }
            if filter.currentEditor() != nil {
                panel.makeFirstResponder(table)
                if table.selectedRow < 0 { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
            } else {
                let delta = event.keyCode == 125 ? 1 : -1
                let row = min(rows.count - 1,max(0,table.selectedRow + delta))
                table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
            }
            table.scrollRowToVisible(table.selectedRow)
            return true
        default: return false
        }
    }

    func controlTextDidChange(_ notification: Notification) { applyFilter() }

    private func applyFilter() {
        let selected = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].entry : nil
        rows = catalog?.filteredRows(filter.stringValue) ?? []
        table.reloadData()
        if !rows.isEmpty {
            let row = selected.flatMap { previous in rows.firstIndex { $0.entry == previous } } ?? 0
            table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
            table.scrollRowToVisible(row)
        }
        let total = catalog?.rows.count ?? 0
        if rows.isEmpty { count.stringValue = "No matching index entries" }
        else if filter.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { count.stringValue = "\(total) index entries" }
        else { count.stringValue = "\(rows.count) of \(total) entries" }
        table.tableColumns.first?.width = max(410,rows.map { ($0.text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width + 16 }.max() ?? 0)
        updateTarget()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let text = NSTextField(labelWithString:rows[row].text)
        text.font = .systemFont(ofSize:12)
        text.lineBreakMode = .byClipping
        return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateTarget() }
    private func updateTarget() {
        guard rows.indices.contains(table.selectedRow) else { target.stringValue = ""; return }
        let row = rows[table.selectedRow]
        target.stringValue = row.entry.title + (row.showPath ? "\n" + row.entry.path : "")
    }
    @objc private func clickedRow() {
        guard isVisible, let event = NSApp.currentEvent, event.buttonNumber == 0,
              [.leftMouseDown,.leftMouseUp].contains(event.type) else { return }
        let point = table.convert(event.locationInWindow,from:nil)
        let row = table.row(at:point)
        guard rows.indices.contains(row), row == table.clickedRow, table.rect(ofRow:row).contains(point) else { return }
        choose()
    }
    private func choose() {
        guard isVisible, rows.indices.contains(table.selectedRow) else { return }
        let entry = rows[table.selectedRow].entry
        close()
        onChoose?(entry)
    }
    func windowDidResignKey(_ notification: Notification) { close() }
}
