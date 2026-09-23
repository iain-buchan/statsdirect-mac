import Cocoa

/// Explicit window controls, separate from the document-tab controls.
@MainActor
final class WindowFrameControls: NSObject {
    private weak var window: NSWindow?
    private let accessory = NSTitlebarAccessoryViewController()
    init(window: NSWindow) {
        self.window = window
        super.init()
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.toolTip = "Close the viewer window"
        let minimise = NSButton(title: "Minimise", target: self, action: #selector(minimiseWindow))
        minimise.toolTip = "Minimise the viewer to the Dock"
        let resize = NSButton(title: "Resize / Restore", target: self, action: #selector(resizeWindow))
        resize.toolTip = "Enlarge or restore the window. Drag any window edge for a custom size."
        let move = WindowMoveButton(title: "Move", target: nil, action: nil)
        move.toolTip = "Drag this control to move the viewer window"
        let buttons = [close, minimise, resize, move]
        for button in buttons { button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize: 11) }
        let stack = NSStackView(views: buttons); stack.spacing = 6; stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 10)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 28)
        accessory.view = stack; accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
        window.isMovable = true
    }
    @objc private func closeWindow() { window?.performClose(nil) }
    @objc private func minimiseWindow() { window?.miniaturize(nil) }
    @objc private func resizeWindow() { window?.performZoom(nil) }
}

@MainActor
private final class WindowMoveButton: NSButton {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
