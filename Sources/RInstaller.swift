import Cocoa

/// One setup window for all R entry points; concurrent requests share the same download.
@MainActor
final class RInstaller: NSObject, NSWindowDelegate {
    static let shared = RInstaller()
    private let findExecutable: () -> String?
    private let probe: () async -> Bool
    private let download: (RInstallPackage, @escaping @Sendable (Double?) -> Void) async throws -> URL
    private let openPackage: (URL) -> Bool
    private var panel: NSPanel?
    private var callbacks: [(Bool) -> Void] = []
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var package: RInstallPackage?
    private var downloadedFile: URL?
    private var openedInstaller = false
    private var checking = false
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let primary = NSButton(title: "Download and Install R", target: nil, action: nil)
    private let reopen = NSButton(title: "Open Installer Again", target: nil, action: nil)
    private let cancel = NSButton(title: "Not Now", target: nil, action: nil)

    init(findExecutable: @escaping () -> String? = { RRuntime.executable() },
         probe: @escaping () async -> Bool = { await Task.detached { RRuntime.ready() }.value },
         download: @escaping (RInstallPackage, @escaping @Sendable (Double?) -> Void) async throws -> URL = { package, progress in
             let parent = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.statsdirect.viewer/R Installers", isDirectory: true)
             return try await RPackageDownload(package: package, progress: progress).fetch(into: parent)
         }, openPackage: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.findExecutable = findExecutable; self.probe = probe; self.download = download; self.openPackage = openPackage
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func ensureInstalled(_ completion: @escaping (Bool) -> Void) {
        if panel == nil, findExecutable() != nil { completion(true); return }
        callbacks.append(completion)
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        token = UUID(); downloadedFile = nil; openedInstaller = false; checking = false
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Install R for StatsDirect"; window.delegate = self; window.isReleasedWhenClosed = false
        panel = window
        let heading = NSTextField(labelWithString: "R is needed for this feature")
        heading.font = .boldSystemFont(ofSize: 18)
        primary.target = self; primary.action = #selector(primaryAction); primary.isEnabled = true
        primary.title = "Download and Install R"; primary.keyEquivalent = "\r"
        cancel.target = self; cancel.action = #selector(cancelSetup); cancel.title = "Not Now"; cancel.keyEquivalent = "\u{1b}"
        reopen.target = self; reopen.action = #selector(openInstaller); reopen.isHidden = true
        progress.style = .bar; progress.minValue = 0; progress.maxValue = 1; progress.isHidden = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.stringValue = ""
        let buttons = NSStackView(views: [cancel, reopen, primary]); buttons.spacing = 8
        let stack = NSStackView(views: [heading, detail, progress, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        do {
            let selected = try RInstallPackage.current(); package = selected
            detail.stringValue = "StatsDirect can download R \(selected.version) from the R Project (about 101 MB). macOS Installer will guide you through installation and may ask for an administrator password. Your work will stay open."
        } catch { package = nil; detail.stringValue = error.localizedDescription; primary.isEnabled = false }
        window.center(); window.makeKeyAndOrderFront(nil)
    }

    @objc private func primaryAction() {
        if openedInstaller { checkInstallation(); return }
        if downloadedFile != nil { openInstaller(); return }
        guard task == nil, let package else { return }
        let request = token
        progress.isHidden = false; progress.isIndeterminate = false; progress.doubleValue = 0
        primary.isEnabled = false; cancel.title = "Cancel Download"
        status.stringValue = "Downloading R from cran.r-project.org…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await self.download(package) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.token == request, self.task != nil else { return }
                        if let fraction {
                            self.progress.isIndeterminate = false; self.progress.doubleValue = fraction
                            self.status.stringValue = "Downloading R… \(Int(fraction * 100))%"
                        } else {
                            self.progress.isIndeterminate = true; self.progress.startAnimation(nil)
                            self.status.stringValue = "Checking the download and Apple installer signature…"
                        }
                    }
                }
                guard self.token == request, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); return
                }
                self.task = nil; self.downloadedFile = file
                self.progress.stopAnimation(nil); self.progress.isHidden = true
                self.openInstaller()
            } catch {
                guard self.token == request else { return }
                self.task = nil; self.progress.stopAnimation(nil); self.progress.isHidden = true
                self.primary.title = "Retry Download"; self.primary.isEnabled = true; self.cancel.title = "Not Now"
                self.status.stringValue = (error is URLError ? "The R download could not be completed. Check your connection and try again." : error.localizedDescription)
            }
        }
    }

    @objc private func openInstaller() {
        guard let file = downloadedFile else { return }
        primary.isEnabled = true; cancel.title = "Later"
        guard openPackage(file) else {
            primary.title = "Open Installer"; status.stringValue = "macOS Installer could not be opened. You can try again."; return
        }
        openedInstaller = true
        primary.title = "Check Again"; reopen.isHidden = false
        status.stringValue = "Finish installing R in macOS Installer, then return here. StatsDirect will check for R and continue automatically."
    }
    @objc private func applicationActivated() { if openedInstaller { checkInstallation() } }
    private func checkInstallation() {
        guard panel != nil, !checking else { return }
        checking = true; primary.isEnabled = false
        let request = token
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.probe()
            guard self.token == request else { return }
            self.checking = false; self.primary.isEnabled = true
            if ready { self.finish(true) }
            else { self.status.stringValue = "R is not ready yet. Complete the steps in macOS Installer, then click Check Again or return to StatsDirect." }
        }
    }
    @objc private func cancelSetup() { finish(false) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(false); return false }
    func shutdown() { finish(false) }
    private func finish(_ installed: Bool) {
        token = UUID(); task?.cancel(); task = nil
        panel?.orderOut(nil); panel = nil
        // Installer may still be using the package if the user chooses Later.
        if let file = downloadedFile, installed || !openedInstaller { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        downloadedFile = nil; openedInstaller = false; checking = false
        let pending = callbacks; callbacks.removeAll()
        for callback in pending { callback(installed) }
    }
}
