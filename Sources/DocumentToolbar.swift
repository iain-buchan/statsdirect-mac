import Cocoa

/// The Mac host's web and native controls draw the same Windows-style paths.
@MainActor enum DocumentToolbarIcons {
    static func image(_ name: String, resources: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent("Mac/toolbar-icons.json")),
              let icons = try? JSONSerialization.jsonObject(with: data) as? [String: [[Any]]], let parts = icons[name] else { return nil }
        let path = CGMutablePath()
        for part in parts {
            guard let op = part.first as? String else { continue }
            let v: [CGFloat] = part[1...].compactMap { value in
                guard let number = value as? NSNumber else { return nil }; return CGFloat(number.doubleValue)
            }
            switch op {
            case "M" where v.count == 2: path.move(to: CGPoint(x: v[0], y: v[1]))
            case "L" where v.count == 2: path.addLine(to: CGPoint(x: v[0], y: v[1]))
            case "C" where v.count == 6: path.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
            case "E" where v.count == 4: path.addEllipse(in: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
            case "R" where v.count == 4: path.addRect(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
            case "Z": path.closeSubpath()
            default: break
            }
        }
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState(); defer { context.restoreGState() }
            context.scaleBy(x: bounds.width / 24, y: bounds.height / 24)
            context.setStrokeColor(NSColor.labelColor.cgColor); context.setLineWidth(1.8)
            context.setLineCap(.round); context.setLineJoin(.round); context.addPath(path); context.strokePath()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = name
        return image
    }
}

/// One row, with secondary controls in a native, keyboard-accessible More menu.
/// Buttons remain the action owners so overflow always uses the current state.
@MainActor final class DocumentToolbar: NSView, NSMenuDelegate {
    struct Item { let button: NSButton; let priority: Int; var groupStart = false }
    let items: [Item]
    private let wrappers: [NSView]
    private let more = NSButton()
    private var overflow: [Item] = []
    var validate: (() -> Void)?
    override var isFlipped: Bool { true }
    init(items: [Item], resources: URL) {
        self.items = items; wrappers = items.map { _ in NSView() }
        super.init(frame: .zero)
        setAccessibilityRole(.toolbar); setAccessibilityLabel("Script commands")
        wantsLayer = true; layer?.cornerRadius = 6; layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for (item, wrapper) in zip(items, wrappers) {
            addSubview(wrapper); wrapper.addSubview(item.button)
            item.button.refusesFirstResponder = true; item.button.bezelStyle = .texturedRounded
            item.button.isBordered = false; item.button.font = .systemFont(ofSize: 12)
            // Untinted template images use AppKit's muted toolbar grey even when enabled.
            // Label colour keeps enabled commands legible and still adapts to dark mode
            // and AppKit's disabled/inactive states.
            item.button.contentTintColor = .labelColor
        }
        more.image = DocumentToolbarIcons.image("more", resources: resources); more.imagePosition = .imageOnly
        more.title = "More commands"; more.imagePosition = .imageOnly; more.toolTip = more.title; more.setAccessibilityLabel(more.title)
        more.refusesFirstResponder = false; more.isBordered = false; more.target = self; more.action = #selector(openMore)
        more.contentTintColor = .labelColor
        addSubview(more)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() { validate?(); needsLayout = true }
    override func layout() {
        super.layout(); validate?()
        let available = max(0, bounds.width - 10)
        let visible = items.indices.filter { !items[$0].button.isHidden }
        let widths = items.map { $0.button.imagePosition == .imageOnly ? CGFloat(30) : max(30, $0.button.intrinsicContentSize.width + 10) }
        var used = visible.reduce(CGFloat(34)) { $0 + widths[$1] + 4 + (items[$1].groupStart ? 6 : 0) }
        var hidden = Set<Int>()
        for i in visible.sorted(by: { items[$0].priority == items[$1].priority ? $0 > $1 : items[$0].priority > items[$1].priority }) {
            if used <= available { break }
            hidden.insert(i); used -= widths[i] + 4 + (items[i].groupStart ? 6 : 0)
        }
        overflow = visible.filter { hidden.contains($0) }.map { items[$0] }
        var x: CGFloat = 5
        for i in items.indices {
            wrappers[i].isHidden = hidden.contains(i) || items[i].button.isHidden
            if wrappers[i].isHidden { continue }
            if items[i].groupStart { x += 6 }
            wrappers[i].frame = NSRect(x: x, y: 5, width: widths[i], height: 30)
            items[i].button.frame = wrappers[i].bounds; x += widths[i] + 4
        }
        more.isHidden = overflow.isEmpty; more.frame = NSRect(x: min(x, max(5, bounds.width - 35)), y: 5, width: 30, height: 30)
    }
    func overflowMenu() -> NSMenu {
        refresh(); layoutSubtreeIfNeeded()
        let menu = NSMenu(); menu.autoenablesItems = false
        for item in overflow {
            if item.groupStart && !menu.items.isEmpty { menu.addItem(.separator()) }
            let entry = NSMenuItem(title: item.button.title, action: #selector(invoke(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = item.button; entry.image = item.button.image
            entry.isEnabled = item.button.isEnabled; entry.toolTip = item.button.toolTip; menu.addItem(entry)
        }
        return menu
    }
    @objc private func openMore() {
        let menu = overflowMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: more.frame.minX, y: more.frame.maxY + 3), in: self)
    }
    @objc private func invoke(_ sender: NSMenuItem) { (sender.representedObject as? NSButton)?.performClick(sender) }
}
