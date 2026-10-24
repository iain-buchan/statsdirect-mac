import Cocoa

extension Viewer: NSMenuDelegate {
    // Finder can deliver its open event before the window has been constructed.
    // Queue only those early events; normal opens use the same path as File/Open.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard finishedLaunching else { pendingOpenURLs.append(contentsOf: urls); return }
        openDocumentURLs(urls)
        window.makeKeyAndOrderFront(nil)
    }

    func openDocumentURLs(_ urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { showError("Open a file saved on this computer."); continue }
            switch url.pathExtension.lowercased() {
            case let ext where Self.excelExtensions.contains(ext): openExcelURL(url)
            case "csv", "tsv": openCSVURL(url)
            case "rds", "rdata", "rda": openRDataURL(url)
            case "r", "cs", "vb": openRScriptURL(url)
            case "html", "htm", "rtf", "txt": openReportURL(url)
            case "ipynb": openNotebookURL(url)
            case "sdw": showError("This legacy StatsDirect workbook needs the StatsDirect 2 converter on Windows. Open it there and save it as an Excel workbook (.xlsx or .xls), then open that file here. The original SDW file has not been changed.")
            default: showError("Choose an Excel, CSV, TSV or R data file, an R, C# or Visual Basic script, an HTML, RTF or text report, or a StatsDirect Jupyter notebook.")
            }
        }
    }

    func addRecentDocumentsMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "Open Recent"); recent.delegate = self
        item.submenu = recent; menu.addItem(item); recentDocumentsMenu = recent
        refreshRecentDocumentsMenu(recent)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        // The in-window menu is a copy of the menu-bar menu.
        if menu.title == "Open Recent" { refreshRecentDocumentsMenu(menu) }
    }
    func refreshRecentDocumentsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let repeated = urls.filter { $0.lastPathComponent == url.lastPathComponent }.count > 1
            let title = url.lastPathComponent + (repeated ? " — " + url.deletingLastPathComponent().lastPathComponent : "")
            let item = NSMenuItem(title: title, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; item.toolTip = url.path
            menu.addItem(item)
        }
        if urls.isEmpty { let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: ""); empty.isEnabled = false; menu.addItem(empty) }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = self; menu.addItem(clear)
    }
    @objc func openRecentDocument(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { openDocumentURLs([url]) }
    }
    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        if let menu = recentDocumentsMenu { refreshRecentDocumentsMenu(menu) }
    }
    func noteRecentDocument(_ url: URL) {
        // Bundled examples already have their own Help command; don't keep
        // paths into a particular application build in the user's recent list.
        guard url.isFileURL, !url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { return }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        if let menu = recentDocumentsMenu { refreshRecentDocumentsMenu(menu) }
    }
    func didOpenDocument(_ doc: Document, url: URL? = nil) {
        guard let url = url ?? doc.openedFileURL else { return }
        doc.openedFileURL = url
        noteRecentDocument(url)
        // Discard only the untouched startup sheet after an import succeeds.
        // A failed import or a sheet edited while the file loads keeps it intact.
        if let id = startupWorksheetID, let initial = documents.first(where: { $0.id == id }), initial !== doc,
           !initial.gridDirty, initial.gridVersion == 0, initial.workbookID == nil, initial.openedFileURL == nil {
            remove(initial)
        }
        startupWorksheetID = nil
    }
}
