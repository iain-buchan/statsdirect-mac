import Cocoa

@main struct UpdateHostChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                exit(EXIT_SUCCESS)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fputs("FAIL: update host checks timed out\n", stderr)
            exit(EXIT_FAILURE)
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let defaults = UserDefaults.standard
        let legacy: [String: Any] = [
            "lastUpdateCheck": Date(),
            "notifiedUpdateVersion": "v999.0.0"
        ]
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(legacy.merging(["automaticUpdateChecks": false]) { _, new in new },
                                   forName: UserDefaults.argumentDomain)
        let release = PublishedUpdate(version: "v999.0.0",
                                      url: UpdateService.releases.appendingPathComponent("tag/v999.0.0"))
        var requests = 0
        let check: (String) async throws -> UpdateStatus = { _ in
            requests += 1
            return .available(release)
        }
        let first = makeViewer()
        first.startUpdateChecks(check: check)
        try verify(first.updateCheckTask == nil && requests == 0, "Disabled automatic checks skip startup discovery")

        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(legacy.merging(["automaticUpdateChecks": true]) { _, new in new },
                                   forName: UserDefaults.argumentDomain)
        let blocker = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                               styleMask: [.titled], backing: .buffered, defer: false)
        first.window.beginSheet(blocker, completionHandler: nil)
        first.startUpdateChecks(check: check)
        await first.updateCheckTask?.value
        try verify(requests == 1 && first.window.attachedSheet === blocker && first.pendingUpdateNotice != nil,
                   "Startup checks despite legacy timestamps and keeps the offer pending behind an attached sheet")
        dismiss(first)
        try await wait { first.window.attachedSheet != nil }
        try verify(buttons(first).contains("View Update") && buttons(first).contains("Later") && !buttons(first).contains("Install Now"),
                   "An update without verified asset metadata offers the browser after the sheet closes")
        dismiss(first, response: .alertSecondButtonReturn)

        first.startUpdateChecks(check: check)
        await first.updateCheckTask?.value
        try verify(requests == 2 && first.window.attachedSheet == nil, "Later suppresses repeat automatic offers for this launch")
        first.checkForUpdates(manual: true, check: check)
        await first.updateCheckTask?.value
        try verify(requests == 3 && buttons(first).contains("View Update"), "A manual check can show the release again")
        dismiss(first, response: .alertSecondButtonReturn)

        let nextLaunch = makeViewer()
        nextLaunch.startUpdateChecks(check: check)
        await nextLaunch.updateCheckTask?.value
        try verify(requests == 4 && buttons(nextLaunch).contains("View Update"), "The next launch can offer the same release")
        dismiss(nextLaunch, response: .alertSecondButtonReturn)
        nextLaunch.checkForUpdates(manual: true) { _ in throw URLError(.notConnectedToInternet) }
        await nextLaunch.updateCheckTask?.value
        try verify(buttons(nextLaunch).contains("Try Again") && buttons(nextLaunch).contains("Open Downloads"),
                   "An offline manual check offers retry and downloads")
        dismiss(nextLaunch, response: .alertThirdButtonReturn)

        nextLaunch.downloadUpdate(release) { _ in
            try await Task.sleep(for: .seconds(10))
            throw UpdateService.failure("The test download should be cancelled")
        }
        try verify(buttons(nextLaunch).contains("Cancel"), "The download sheet offers Cancel")
        dismiss(nextLaunch, response: .alertFirstButtonReturn)
        await nextLaunch.updateDownloadTask?.value
        try verify(nextLaunch.stagedUpdate == nil && nextLaunch.status.stringValue == "Update download cancelled",
                   "Cancelling download leaves the app running without a staged update")

        nextLaunch.running = true
        try verify(nextLaunch.applicationShouldTerminate(NSApp) == .terminateCancel && !nextLaunch.updateHostStopped,
                   "The normal running-analysis guard can cancel quit and keep the update host active")
        dismiss(nextLaunch)
        nextLaunch.running = false
        try verify(nextLaunch.applicationShouldTerminate(NSApp) == .terminateNow && nextLaunch.updateHostStopped,
                   "An approved quit stops further update checks")
    }

    @MainActor static func makeViewer() -> Viewer {
        let viewer = Viewer()
        viewer.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        viewer.window.isReleasedWhenClosed = false
        viewer.window.delegate = viewer
        viewer.status = NSTextField(labelWithString: "")
        return viewer
    }

    @MainActor static func buttons(_ viewer: Viewer) -> [String] {
        func titles(_ view: NSView) -> [String] {
            if let button = view as? NSButton { return [button.title] }
            return view.subviews.flatMap(titles)
        }
        return viewer.window.attachedSheet?.contentView.map(titles) ?? []
    }

    @MainActor static func dismiss(_ viewer: Viewer, response: NSApplication.ModalResponse = .cancel) {
        if let sheet = viewer.window.attachedSheet {
            viewer.window.endSheet(sheet, returnCode: response)
            sheet.orderOut(nil)
        }
    }

    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw UpdateService.failure("Timed out waiting for the deferred update offer")
    }

    static func verify(_ condition: Bool, _ message: String) throws {
        guard condition else { throw UpdateService.failure(message) }
        print("PASS: " + message)
    }
}
