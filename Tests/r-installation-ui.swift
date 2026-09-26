// Isolated native UI fixture. It never opens Installer or changes the machine's R installation.
// Create <app support>/R Setup UI/ready to simulate Installer completing, then choose Check Again.
import Cocoa

@MainActor final class SetupUITest: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var pane: RPane!
    var installer: RInstaller!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.statsdirect.r-setup-ui")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appendingPathComponent("ready")
        try? FileManager.default.removeItem(at: marker) // Reset only this fixture's simulated installation state.
        let executable = RRuntime.executable()!
        let available: () -> String? = { FileManager.default.fileExists(atPath: marker.path) ? executable : nil }
        var attempts = 0
        installer = RInstaller(findExecutable: available, probe: { available() != nil && RRuntime.ready() }, download: { _, progress in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            for tick in 1...5 { try await Task.sleep(for: .seconds(1)); progress(Double(tick) / 5) }
            let staging = folder.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let file = staging.appendingPathComponent("Fixture.pkg")
            try Data("UI fixture only — not an installer".utf8).write(to: file)
            return file
        }, openPackage: { _ in print("PASS: verified-download handoff requested (Installer deliberately not launched by this fixture)"); return true })
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "StatsDirect R Setup — isolated test"
        pane = RPane(script: "# Retain this script while R is installed.\ncat('SETUP_RESUMED_SUCCESSFULLY\\n')\nplot(1:5)\n", installer: installer, executable: available)
        window.contentView = pane.view
        let menu = NSMenu(), appMenu = NSMenu()
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        appMenu.addItem(withTitle: "Quit R Setup Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        pane.runScript()
    }
    func applicationWillTerminate(_ notification: Notification) { pane.shutdown(); installer.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct SetupUI {
    @MainActor static func main() {
        let delegate = SetupUITest()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
