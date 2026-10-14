import Cocoa
import WebKit

@main struct StartupRSetupTests {
    @MainActor static func check(_ ok: Bool, _ message: String) throws {
        guard ok else { throw NSError(domain: "StartupRSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: " + message); fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(30)
        while Date() < end {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "StartupRSetup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for document or R setup"])
    }
    @MainActor static func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
    @MainActor static var setupWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Install R for StatsDirect" && $0.isVisible }
    }
    @MainActor static func setupButton(_ title: String) -> NSButton? {
        setupWindow?.contentView.flatMap { buttons($0).first { $0.title == title && $0.isEnabled && !$0.isHidden } }
    }
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        let viewer = Viewer(); app.delegate = viewer
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-startup-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { print("FAIL: \(error)"); exit(1) }
        let script = folder.appendingPathComponent("Requested.R")
        let source = "stop('Opening a script must not run it')\n"
        if CommandLine.arguments.contains("--startup-file") {
            try! source.write(to: script, atomically: true, encoding: .utf8)
            viewer.application(app, open: [script])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: folder) }
                do {
                    if let index = CommandLine.arguments.firstIndex(of: "--finder-file"), CommandLine.arguments.indices.contains(index + 1) {
                        let requested = URL(fileURLWithPath: CommandLine.arguments[index + 1]).resolvingSymlinksInPath()
                        try await wait { viewer.active?.openedFileURL?.resolvingSymlinksInPath() == requested }
                        try check(viewer.documents.count == 1 && viewer.active?.rPane?.editor.string == source && viewer.active?.rPane?.isRunning == false, "Launch Services opens the actual requested file without a chooser or automatic execution")
                    } else if CommandLine.arguments.contains("--startup-file") {
                        try check(viewer.finishedLaunching && viewer.pendingOpenURLs.isEmpty, "early Finder open event is drained after window construction")
                        try check(viewer.documents.count == 1 && viewer.active?.rPane?.editor.string == source, "file launch opens the requested document without an extra blank worksheet")
                        try check(viewer.active?.rPane?.isRunning == false && viewer.active?.rPane?.console.string.isEmpty == true && viewer.active?.rPane?.outputFolder == nil, "opening a script at startup neither runs it nor starts an R process")
                    } else { try await run(viewer, folder: folder) }
                    viewer.clearRecentDocuments(nil)
                    print("PASS: startup and R setup checks completed"); fflush(stdout)
                } catch { print("FAIL: \(error)"); fflush(stdout); exit(1) }
                viewer.closeApproved = true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { print("FAIL: startup and R setup timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer, folder: URL) async throws {
        v.clearRecentDocuments(nil)
        let initial = v.active!
        try await wait { initial.pendingWorkbook == nil && !initial.web.isLoading }
        try check(v.documents.count == 1 && initial.kind == "grid" && !initial.gridDirty && initial.gridVersion == 0, "ordinary startup goes straight to a clean blank worksheet")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as! [[String: Any]]
        try check(types.allSatisfy { $0["LSHandlerRank"] as? String == "Alternate" } && types.contains { ($0["CFBundleTypeExtensions"] as? [String])?.contains("xlsx") == true }, "Finder supports StatsDirect files without claiming their default application")
        let csv = folder.appendingPathComponent("Measurements.csv")
        try "Before,After\n12,10\n18,15\n".write(to: csv, atomically: true, encoding: .utf8)
        v.application(NSApp, open: [csv])
        try await wait { v.documents.contains { $0.openedFileURL == csv && $0.pendingCSV == nil } && !v.documents.contains { $0 === initial } }
        let data = v.documents.first { $0.openedFileURL == csv }!
        let text = try await data.web.evaluateJavaScript("statsDirectGrid.csvSnapshot().text") as! String
        try check(text.contains("12,10") && v.documents.count == 1, "Finder CSV open loads data and removes only the unused startup sheet")
        func recentURLs() -> [URL] { NSDocumentController.shared.recentDocumentURLs.map { $0.resolvingSymlinksInPath() } }
        try check(recentURLs().contains(csv.resolvingSymlinksInPath()), "successful file opens populate Open Recent")
        v.noteRecentDocument(csv)
        try check(recentURLs().filter { $0 == csv.resolvingSymlinksInPath() }.count == 1, "Open Recent does not duplicate a reopened file")

        v.newWorksheet(); let edited = v.active!; v.startupWorksheetID = edited.id
        try await wait { edited.pendingWorkbook == nil }
        _ = try await edited.web.evaluateJavaScript("statsDirectGrid.pasteText('42')")
        try await wait { edited.gridDirty }
        let script = folder.appendingPathComponent("Keep my work.R")
        try "stop('not executed')\n".write(to: script, atomically: true, encoding: .utf8)
        v.application(NSApp, open: [script])
        try check(v.documents.contains { $0 === edited } && edited.gridDirty && v.active?.rPane?.isRunning == false, "file open preserves an edited startup sheet and does not execute R code")
        let recent = v.recentDocumentsMenu!; v.menuNeedsUpdate(recent)
        let item = recent.items.first { ($0.representedObject as? URL)?.resolvingSymlinksInPath() == csv.resolvingSymlinksInPath() }!
        let count = v.documents.count
        try check(NSApp.sendAction(item.action!, to: item.target, from: item), "Open Recent dispatches its actual menu command")
        try await wait { v.documents.count == count + 1 && v.active?.pendingCSV == nil }
        try check(v.active?.openedFileURL?.resolvingSymlinksInPath() == csv.resolvingSymlinksInPath(), "Open Recent reopens the selected file")

        v.newWorksheet(); let untouched = v.active!; v.startupWorksheetID = untouched.id
        try await wait { untouched.pendingWorkbook == nil }
        v.openCSVURL(folder.appendingPathComponent("Missing.csv"))
        try await wait { v.window.attachedSheet != nil }
        try check(v.documents.contains { $0 === untouched } && v.startupWorksheetID == untouched.id, "failed import preserves the startup worksheet and other open work")
        if let sheet = v.window.attachedSheet { v.window.endSheet(sheet); sheet.orderOut(nil) }

        let report = folder.appendingPathComponent("Report.html")
        try "<!doctype html><html><body><h1>Imported result</h1><table><tr><td>42</td></tr></table></body></html>".write(to: report, atomically: true, encoding: .utf8)
        v.openDocumentURLs([report])
        try await wait { v.documents.contains { $0.openedFileURL == report } && !v.documents.contains { $0 === untouched } }
        try check(v.active?.kind == "report", "HTML report file uses the same open path and replaces an untouched placeholder")
        let workbook = folder.appendingPathComponent("Test workbook.xlsx")
        try FileManager.default.copyItem(at: v.root.appendingPathComponent("Examples/test.xlsx"), to: workbook)
        v.openDocumentURLs([workbook, script])
        try await wait { v.documents.contains { $0.openedFileURL == workbook && $0.pendingWorkbook == nil } }
        try check(v.documents.first { $0.openedFileURL == workbook }?.workbookID != nil, "multiple-file opening includes a real Excel workbook through the calculation host")
        let example = v.root.appendingPathComponent("Examples/test.xlsx")
        v.noteRecentDocument(example)
        try check(!NSDocumentController.shared.recentDocumentURLs.contains(example), "bundled examples do not leave build-specific entries in Open Recent")
        v.clearRecentDocuments(nil)
        try check(NSDocumentController.shared.recentDocumentURLs.isEmpty && recent.items.first?.title == "No Recent Documents", "Clear Menu updates the system recent list and its empty state")
        try await testRSetup(folder)
    }

    @MainActor static func testRSetup(_ folder: URL) async throws {
        guard let installedR = RRuntime.executable() else { throw CocoaError(.fileNoSuchFile) }
        var available = false, attempts = 0, handoffs = 0
        let installer = RInstaller(findExecutable: { available ? installedR : nil }, probe: { available }, download: { _, progress in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            progress(0.5)
            let stage = folder.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            let package = stage.appendingPathComponent("Fixture.pkg")
            try Data("Test fixture; never installed".utf8).write(to: package)
            return package
        }, openPackage: { _ in handoffs += 1; return true })
        let pane = RPane(script: "cat('ORIGINAL\\n')", installer: installer, executable: { available ? installedR : nil })
        pane.scriptName = "Startup test " + UUID().uuidString
        let originalExternal = RPane.opensExternally; RPane.opensExternally = true
        defer { pane.shutdown(); installer.shutdown(); RPane.opensExternally = originalExternal }
        let copy = pane.openInR()!
        defer { try? FileManager.default.removeItem(at: copy) }
        try check(setupButton("Download and Install R") != nil && !pane.isRunning, "Open in R offers guided installation when R is missing")
        setupButton("Download and Install R")!.performClick(nil)
        try await wait { setupButton("Retry Download") != nil }
        try check(pane.editor.string.contains("ORIGINAL") && handoffs == 0, "failed download offers retry and preserves the script without opening Installer")
        setupButton("Retry Download")!.performClick(nil)
        try await wait { setupButton("Check Again") != nil }
        try check(attempts == 2 && handoffs == 1, "retry downloads once and hands the verified package to the OS installer")
        setupButton("Check Again")!.performClick(nil)
        try await wait { setupButton("Check Again") != nil }
        try check(setupWindow != nil && !pane.isRunning, "unfinished installation keeps setup open and does not run the pending script")
        pane.editor.string = "cat('EDIT_RETAINED\\n')"
        // The resumed open writes the exact script but deliberately suppresses an
        // external R/RStudio launch in this isolated fixture.
        RPane.opensExternally = false; available = true
        setupButton("Check Again")!.performClick(nil)
        try await wait { setupWindow == nil && (try? String(contentsOf: copy, encoding: .utf8)) == pane.editor.string }
        try check(pane.state.stringValue.hasPrefix("Saved ") && !pane.console.string.contains("EDIT_RETAINED"), "successful installation resumes Open in R with edits made during setup")

        available = false
        let runInstaller = RInstaller(findExecutable: { available ? installedR : nil }, probe: { available }, download: { _, _ in
            let stage = folder.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            let file = stage.appendingPathComponent("Fixture.pkg"); try Data().write(to: file); return file
        }, openPackage: { _ in true })
        let runPane = RPane(script: "cat('SETUP_RESUMED_ONCE\\n')", installer: runInstaller, executable: { available ? installedR : nil })
        defer { runPane.shutdown(); runInstaller.shutdown() }
        runPane.runScript(); setupButton("Not Now")!.performClick(nil)
        try check(!runPane.isRunning && runPane.editor.string.contains("SETUP_RESUMED_ONCE") && setupWindow == nil, "postponing R setup preserves the script and performs no analysis")
        runPane.runScript(); runPane.runScript()
        setupButton("Download and Install R")!.performClick(nil)
        try await wait { setupButton("Check Again") != nil }
        available = true; setupButton("Check Again")!.performClick(nil)
        try await wait { !runPane.isRunning && runPane.console.string.contains("SETUP_RESUMED_ONCE") }
        try check(runPane.console.string.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces) == "SETUP_RESUMED_ONCE" }.count == 1, "repeated Run while setup is open resumes the original analysis exactly once")

        available = false; RPane.opensExternally = true
        _ = pane.openInR()
        pane.stopSession(); installer.shutdown()
        let previousCopy = try String(contentsOf: copy, encoding: .utf8)
        pane.editor.string = "cat('RUN_AFTER_RESET\\n')"
        pane.runScript(); setupButton("Download and Install R")!.performClick(nil)
        try await wait { setupButton("Check Again") != nil }
        available = true; RPane.opensExternally = false
        setupButton("Check Again")!.performClick(nil)
        try await wait { !pane.isRunning && pane.console.string.contains("RUN_AFTER_RESET") }
        try check(try String(contentsOf: copy, encoding: .utf8) == previousCopy, "Reset discards an old external-open request before a later Run installs R")

        let cancelInstaller = RInstaller(findExecutable: { nil }, download: { _, _ in
            try await Task.sleep(for: .seconds(30)); throw URLError(.cancelled)
        }, openPackage: { _ in false })
        let cancelPane = RPane(script: "# Keep this", installer: cancelInstaller, executable: { nil })
        defer { cancelPane.shutdown(); cancelInstaller.shutdown() }
        cancelPane.runScript(); setupButton("Download and Install R")!.performClick(nil)
        try await wait { setupButton("Cancel Download") != nil }
        setupButton("Cancel Download")!.performClick(nil)
        try check(setupWindow == nil && cancelPane.editor.string == "# Keep this" && !cancelPane.isRunning, "cancelling an active download closes setup and preserves unsaved code")
    }
}
