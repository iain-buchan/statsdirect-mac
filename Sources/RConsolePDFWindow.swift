import Cocoa
import PDFKit
import UniformTypeIdentifiers

/// Opens the original immutable chart PDF without depending on an external reader.
@MainActor final class RConsolePDFWindow: NSWindowController, NSWindowDelegate {
    let fileURL: URL
    let pdfDocument: PDFDocument
    let pdfView: PDFView
    private let pageIndex: Int
    var onClose: (() -> Void)?

    init(url: URL, page: Int, title: String) throws {
        guard url.isFileURL, let document = PDFDocument(url: url), !document.isLocked,
              page >= 0, page < document.pageCount, document.page(at: page) != nil else {
            throw NSError(domain: "StatsDirect.RConsolePDF", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The chart PDF could not be read or its selected page is unavailable."])
        }
        fileURL = url
        pdfDocument = document
        pageIndex = page
        pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 850, height: 700))
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        pdfView.autoresizingMask = [.width, .height]

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("StatsDirectRConsolePDF")
        window.title = title
        window.minSize = NSSize(width: 450, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(pdfView)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(url:page:title:)") }

    func present() { present(page: pageIndex) }

    func present(page: Int) {
        guard page >= 0, page < pdfDocument.pageCount, let target = pdfDocument.page(at: page) else { return }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        pdfView.go(to: target)
        NSApp.activate(ignoringOtherApps: true)
    }

    func savePDF() {
        guard let owner = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "R chart.pdf"
        panel.beginSheetModal(for: owner) { [weak self] response in
            guard let self, response == .OK, let target = panel.url else { return }
            do {
                let original = try Data(contentsOf: self.fileURL)
                try original.write(to: target, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "The chart PDF could not be saved."
                alert.beginSheetModal(for: owner)
            }
        }
    }

    func printPDF() { pdfView.print(with: NSPrintInfo.shared, autoRotate: true) }

    func windowWillClose(_ notification: Notification) { onClose?() }
}
