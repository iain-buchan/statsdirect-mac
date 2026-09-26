import Cocoa

extension Viewer {
    var automaticUpdates: Bool { UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true }
    @objc func toggleAutomaticUpdates() {
        UserDefaults.standard.set(!automaticUpdates, forKey: "automaticUpdateChecks")
        if automaticUpdates { checkForUpdates(manual: false) }
    }
    @objc func checkUpdates() { checkForUpdates(manual: true) }
    func startUpdateChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.checkForUpdates(manual: false) }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates(manual: false) }
        }
    }
    func checkForUpdates(manual: Bool) {
        guard !checkingUpdates else { return }
        if !manual {
            guard automaticUpdates, window.attachedSheet == nil else { return }
            let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            guard Date().timeIntervalSince(last) >= 86400 else { return }
        }
        checkingUpdates = true
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if manual { status.stringValue = "Checking GitHub for a newer StatsDirect version…" }
        Task { @MainActor in
            defer { checkingUpdates = false }
            do {
                let result = try await UpdateService.check(installed: installed)
                let alert = NSAlert()
                switch result {
                case .available(let release):
                    if !manual && UserDefaults.standard.string(forKey: "notifiedUpdateVersion") == release.version { return }
                    guard window.attachedSheet == nil else { return }
                    alert.messageText = "StatsDirect \(release.version) is available"
                    alert.informativeText = "You are using \(installed). Open the GitHub release to read the changes and download the new version. Your open work will stay here."
                    alert.addButton(withTitle: "View Update"); alert.addButton(withTitle: "Later")
                    UserDefaults.standard.set(release.version, forKey: "notifiedUpdateVersion")
                    alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) } }
                case .current:
                    guard manual else { return }
                    alert.messageText = "StatsDirect is up to date"
                    alert.informativeText = "You are using version \(installed). No newer published release is available."
                    alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window) { _ in }
                case .noRelease:
                    guard manual else { return }
                    alert.messageText = "No published update is available"
                    alert.informativeText = "There is no published Mac application download on GitHub yet. You are using version \(installed)."
                    alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window) { _ in }
                }
                if manual { status.stringValue = "Update check complete · Version \(installed)" }
            } catch {
                if manual {
                    status.stringValue = "Unable to check for updates · Version \(installed)"
                    guard window.attachedSheet == nil else { return }
                    let alert = NSAlert(); alert.messageText = "Could not check for updates"
                    alert.informativeText = UpdateService.message(for: error)
                    alert.addButton(withTitle: "Try Again"); alert.addButton(withTitle: "Open Downloads"); alert.addButton(withTitle: "Cancel")
                    alert.beginSheetModal(for: window) { response in
                        if response == .alertFirstButtonReturn { self.checkForUpdates(manual: true) }
                        else if response == .alertSecondButtonReturn { NSWorkspace.shared.open(UpdateService.releases) }
                    }
                }
            }
        }
    }
}
