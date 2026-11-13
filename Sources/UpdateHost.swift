import Cocoa

enum UpdateNotice {
    case available(PublishedUpdate, installed: String, manual: Bool)
    case current(installed: String)
    case noRelease(installed: String)
    case checkFailed(String)
    case downloadFailed(PublishedUpdate, String)
}

extension Viewer {
    var automaticUpdates: Bool { UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true }

    @objc func toggleAutomaticUpdates() {
        UserDefaults.standard.set(!automaticUpdates, forKey: "automaticUpdateChecks")
        if automaticUpdates { checkForUpdates(manual: false) }
    }

    @objc func checkUpdates() { checkForUpdates(manual: true) }

    @objc func openUpdateRevisions() { NSWorkspace.shared.open(UpdateService.revisions) }

    func startUpdateChecks(check: @escaping (String) async throws -> UpdateStatus = { try await UpdateService.check(installed: $0) }) {
        DispatchQueue.global(qos: .utility).async { UpdateInstaller.removeStaleStaging() }
        checkForUpdates(manual: false, check: check)
    }

    func checkForUpdates(manual: Bool, check: @escaping (String) async throws -> UpdateStatus = { try await UpdateService.check(installed: $0) }) {
        guard !updateHostStopped, updateCheckTask == nil, updateDownloadTask == nil else { return }
        guard manual || automaticUpdates else { return }
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if manual { status.stringValue = "Checking GitHub for a newer StatsDirect version…" }
        updateCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.updateCheckTask = nil }
            do {
                let result = try await check(installed)
                guard !Task.isCancelled, !self.updateHostStopped else { return }
                switch result {
                case .available(let release):
                    self.pendingUpdateNotice = .available(release, installed: installed, manual: manual)
                case .current:
                    if manual { self.pendingUpdateNotice = .current(installed: installed) }
                case .noRelease:
                    if manual { self.pendingUpdateNotice = .noRelease(installed: installed) }
                }
                if manual { self.status.stringValue = "Update check complete · Version \(installed)" }
            } catch {
                guard manual, !Task.isCancelled, !self.updateHostStopped else { return }
                self.status.stringValue = "Unable to check for updates · Version \(installed)"
                self.pendingUpdateNotice = .checkFailed(UpdateService.message(for: error))
            }
            self.presentPendingUpdate()
        }
    }

    func windowDidEndSheet(_ notification: Notification) {
        // Defer until AppKit has removed the dismissed sheet and run its completion.
        Task { @MainActor [weak self] in self?.presentPendingUpdate() }
    }

    func presentPendingUpdate() {
        guard !updateHostStopped, window.attachedSheet == nil,
              let notice = pendingUpdateNotice else { return }
        pendingUpdateNotice = nil
        let alert = NSAlert()
        switch notice {
        case let .available(release, installed, manual):
            guard manual || (automaticUpdates && !offeredUpdate) else { return }
            offeredUpdate = true
            let installable = release.archive != nil && UpdateInstaller.canInstall
            // The wording follows the Windows program's update question.
            let version = release.version.hasPrefix("v") ? String(release.version.dropFirst()) : release.version
            let running = "You are presently running StatsDirect version \(installed). Version \(version) is available."
            alert.messageText = "StatsDirect \(version) is available"
            if installable {
                alert.informativeText = running + " Would you like to close StatsDirect and install the new version? StatsDirect will ask first if you have unsaved work."
                alert.addButton(withTitle: "Install Now")
            } else {
                alert.informativeText = running + " This copy of StatsDirect cannot install it for you. Choose View Update to download it."
            }
            let news = NSButton(title: "What’s new in StatsDirect", target: self, action: #selector(openUpdateRevisions))
            news.isBordered = false
            news.contentTintColor = .linkColor
            news.sizeToFit()
            alert.accessoryView = news
            alert.addButton(withTitle: "View Update")
            alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, !self.updateHostStopped else { return }
                if installable && response == .alertFirstButtonReturn { self.downloadUpdate(release) }
                else if response == (installable ? .alertSecondButtonReturn : .alertFirstButtonReturn) { NSWorkspace.shared.open(release.url) }
            }
        case .current(let installed):
            alert.messageText = "StatsDirect is up to date"
            alert.informativeText = "You are using version \(installed). No newer published release is available."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window) { _ in }
        case .noRelease(let installed):
            alert.messageText = "No published update is available"
            alert.informativeText = "There is no published Mac application download on GitHub yet. You are using version \(installed)."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window) { _ in }
        case .checkFailed(let message):
            alert.messageText = "Could not check for updates"
            alert.informativeText = message
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Open Downloads")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.checkForUpdates(manual: true) }
                else if response == .alertSecondButtonReturn { NSWorkspace.shared.open(UpdateService.releases) }
            }
        case .downloadFailed(let release, let message):
            alert.messageText = "Could not prepare the update"
            alert.informativeText = message
            alert.addButton(withTitle: "View Update")
            alert.addButton(withTitle: "Close").keyEquivalent = "\u{1b}"
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) }
            }
        }
    }

    func downloadUpdate(_ release: PublishedUpdate, prepare: @escaping (PublishedUpdate) async throws -> StagedUpdate = { try await UpdateInstaller.prepare($0) }) {
        guard !updateHostStopped, updateDownloadTask == nil else { return }
        status.stringValue = "Downloading and verifying StatsDirect \(release.version)…"
        let alert = NSAlert()
        alert.messageText = "Preparing StatsDirect \(release.version)"
        alert.informativeText = "Downloading and verifying the update. You can cancel before installation."
        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 16))
        progress.isIndeterminate = true
        progress.style = .bar
        alert.accessoryView = progress
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let sheet = alert.window
        updateDownloadSheet = sheet
        alert.beginSheetModal(for: window) { [weak self, weak sheet] _ in
            guard let self, let sheet, self.updateDownloadSheet === sheet else { return }
            self.updateDownloadSheet = nil
            self.updateDownloadTask?.cancel()
            self.status.stringValue = "Update download cancelled"
        }
        progress.startAnimation(nil)
        updateDownloadTask = Task { @MainActor [weak self] in
            defer { self?.updateDownloadTask = nil }
            do {
                let update = try await prepare(release)
                guard let self, !Task.isCancelled, !self.updateHostStopped else { update.discard(); return }
                self.closeUpdateDownloadSheet()
                self.stagedUpdate = (update, release.url)
                self.status.stringValue = "Update verified · Ready to restart"
                NSApp.terminate(nil)
            } catch {
                guard let self, !Task.isCancelled, !self.updateHostStopped else { return }
                self.closeUpdateDownloadSheet()
                self.status.stringValue = "Unable to prepare the update"
                self.pendingUpdateNotice = .downloadFailed(release, error.localizedDescription)
                self.presentPendingUpdate()
            }
        }
    }

    func stopUpdateHost() {
        updateHostStopped = true
        pendingUpdateNotice = nil
        updateCheckTask?.cancel()
        updateDownloadTask?.cancel()
        closeUpdateDownloadSheet()
    }

    func cancelStagedUpdate() {
        guard let (update, _) = stagedUpdate else { return }
        stagedUpdate = nil
        update.discard()
        status.stringValue = "Update installation cancelled"
    }

    func launchStagedUpdate() {
        guard let (update, releaseURL) = stagedUpdate else { return }
        stagedUpdate = nil
        do { try update.launchInstaller() }
        catch {
            update.discard()
            let alert = NSAlert()
            alert.messageText = "Could not start the update installer"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "View Update")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releaseURL) }
        }
    }

    private func closeUpdateDownloadSheet() {
        guard let sheet = updateDownloadSheet else { return }
        updateDownloadSheet = nil
        if window.attachedSheet === sheet { window.endSheet(sheet) }
        sheet.orderOut(nil)
    }
}
