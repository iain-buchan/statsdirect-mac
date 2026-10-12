import Cocoa

/// The two AI entry points share one first-use setup; merely opening a pane never calls it.
@MainActor final class TutorRuntimeInstaller: NSObject, NSWindowDelegate {
    let root: URL
    let resources: URL
    let package: TutorRuntimePackage?
    var executable: URL { root.appendingPathComponent(package?.folderName ?? "unavailable").appendingPathComponent("bin/codex-app-server") }
    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath:executable.path) }
    private let prepare: (@Sendable (TutorRuntimePackage, URL, URL, @escaping @Sendable (Double?) -> Void) async throws -> URL)
    private var panel: NSPanel?
    private var task: Task<Void,Never>?
    private var callbacks: [CheckedContinuation<Bool,Never>] = []
    private var generation=UUID()
    private let detail=NSTextField(wrappingLabelWithString:"The ChatGPT connection component is installed once for your Mac account. Then sign in with ChatGPT in your browser. No administrator password is needed.")
    private let status=NSTextField(wrappingLabelWithString:"")
    private let progress=NSProgressIndicator()
    private let retry=NSButton(title:"Retry",target:nil,action:nil)
    private let cancel=NSButton(title:"Cancel",target:nil,action:nil)
    init(resources: URL, root: URL, prepare: @escaping @Sendable (TutorRuntimePackage,URL,URL,@escaping @Sendable (Double?) -> Void) async throws -> URL = { package,root,resources,progress in
        try await TutorRuntimeInstallation.install(package,root:root,resources:resources,progress:progress)
    }) {
        self.resources=resources; self.root=root; package=try? TutorRuntimePackage.load(resources); self.prepare=prepare
        super.init()
    }
    func verifyInstalled() async throws {
        guard let package else { throw TutorRuntimePackage.failure("The AI setup information is missing. Install the latest StatsDirect build.") }
        try await TutorRuntimeInstallation.verify(package,at:executable.deletingLastPathComponent().deletingLastPathComponent())
    }
    func ensureAvailable() async -> Bool {
        if TutorPolicy.disabled { return false }
        return await withCheckedContinuation { continuation in
            callbacks.append(continuation)
            if let panel { panel.makeKeyAndOrderFront(nil); return }
            let window=NSPanel(contentRect:NSRect(x:0,y:0,width:470,height:235),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title="Set up ChatGPT"; window.delegate=self; window.isReleasedWhenClosed=false
            let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=14
            stack.translatesAutoresizingMaskIntoConstraints=false; window.contentView!.addSubview(stack)
            let title=NSTextField(labelWithString:"Preparing your ChatGPT connection"); title.font = .boldSystemFont(ofSize:16)
            progress.style = .bar; progress.minValue=0; progress.maxValue=1
            progress.widthAnchor.constraint(equalToConstant:430).isActive=true
            retry.target=self; retry.action=#selector(attempt); cancel.target=self; cancel.action=#selector(cancelSetup)
            cancel.keyEquivalent="\u{1b}"
            let buttons=NSStackView(views:[retry,cancel]); buttons.spacing=8
            for view in [title,detail,progress,status,buttons] { stack.addArrangedSubview(view) }
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),stack.bottomAnchor.constraint(lessThanOrEqualTo:window.contentView!.bottomAnchor,constant:-16)])
            panel=window; window.center(); window.makeKeyAndOrderFront(nil); attempt()
        }
    }
    @objc private func attempt() {
        guard task == nil else { return }
        guard !TutorPolicy.disabled else { finish(false); return }
        guard let package else { status.stringValue="AI setup information is missing. Install the latest StatsDirect build."; retry.isHidden=true; return }
        let token=generation
        retry.isHidden=true; cancel.title="Cancel"; progress.isHidden=false; progress.isIndeterminate=true; progress.startAnimation(nil)
        status.stringValue=isInstalled ? "Checking the installed AI component…" : "Downloading the ChatGPT connection component (about 94 MB)…"
        task=Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.prepare(package,self.root,self.resources) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.task != nil else { return }
                        if let fraction {
                            self.progress.isIndeterminate=false; self.progress.doubleValue=fraction
                            self.status.stringValue="Downloading the ChatGPT connection component… \(Int(fraction*100))%"
                        } else {
                            self.progress.isIndeterminate=true; self.progress.startAnimation(nil)
                            self.status.stringValue="Verifying and installing the AI component…"
                        }
                    }
                }
                guard self.generation == token else { return }
                guard !Task.isCancelled, !TutorPolicy.disabled else { self.finish(false); return }
                self.task=nil; self.finish(true)
            } catch {
                guard self.generation == token else { return }
                guard !Task.isCancelled else { self.finish(false); return }
                self.task=nil; self.progress.stopAnimation(nil); self.progress.isHidden=true
                self.retry.isHidden=false; self.cancel.title="Not Now"
                self.status.stringValue=error is URLError ? "The download could not finish. Check your connection, then choose Retry." : error.localizedDescription
            }
        }
    }
    @objc private func cancelSetup() {
        guard let task else { finish(false); return }
        cancel.isEnabled=false; retry.isEnabled=false; status.stringValue="Cancelling setup…"
        task.cancel() // Keep the panel until the download and staging cleanup have stopped.
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelSetup(); return false }
    func shutdown() { finish(false) }
    private func finish(_ success: Bool) {
        generation=UUID(); task?.cancel(); task=nil
        panel?.orderOut(nil); panel=nil; progress.stopAnimation(nil); cancel.title="Cancel"
        cancel.isEnabled=true; retry.isEnabled=true
        let pending=callbacks; callbacks.removeAll(); pending.forEach { $0.resume(returning:success) }
    }
}
