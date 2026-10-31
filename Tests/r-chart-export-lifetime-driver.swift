import Cocoa
import WebKit

/// Test-only probes inserted into the compiled helper copy by the runner.
@MainActor private final class RendererReference {
    weak var renderer: NSObject?
    weak var web: WKWebView?
    init(_ renderer: NSObject, _ web: WKWebView) { self.renderer = renderer; self.web = web }
}
@MainActor enum RChartLifetimeProbe {
    private static var instances: [RendererReference] = []
    static var renderer: NSObject? { instances.last?.renderer }
    static var web: WKWebView? { instances.last?.web }
    static var liveCount: Int { instances.filter { $0.renderer != nil }.count }
    static var liveWebCount: Int { instances.filter { $0.web != nil }.count }
    static func record(renderer: NSObject, web: WKWebView) { instances.append(RendererReference(renderer, web)) }
}

@MainActor private final class ChartOwnerReference {
    weak var value: RConsoleSVGWindow?
    init(_ value: RConsoleSVGWindow) { self.value = value }
}

@main enum RChartExportLifetimeChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    @MainActor static func run() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = folder.appendingPathComponent("chart.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='80'><rect width='100' height='80' fill='white'/><circle cx='50' cy='40' r='20' fill='blue'/></svg>".utf8).write(to: source)
        func wait(_ seconds: Double, _ predicate: () async throws -> Bool) async throws -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while ProcessInfo.processInfo.systemUptime < deadline {
                if try await predicate() { return true }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            return try await predicate()
        }
        func heldDecode() async throws -> Bool {
            guard let web = RChartLifetimeProbe.web else { return false }
            return (try? await web.evaluateJavaScript("window.__statsDirectDecodeHeld === true")) as? Bool == true
        }
        var failures: [String] = []
        for command in ["copy", "savePNG"] {
            var owner: RConsoleSVGWindow? = try RConsoleSVGWindow(url: source, title: "Chart lifetime test")
            let weakOwner = ChartOwnerReference(owner!)
            let boardChange = NSPasteboard.general.changeCount
            if command == "copy" {
                let menu = NSMenu(); owner!.prepareChartMenu(menu)
                guard let action = menu.items.first?.action else { throw LegacyReportError("Copy command is missing") }
                _ = NSApp.sendAction(action, to: owner, from: menu.items.first)
            } else { owner!.savePNG() }
            guard try await wait(10, heldDecode) else { throw LegacyReportError("The helper did not reach its held post-load decode") }
            owner?.window?.close(); owner = nil
            let released = try await wait(3) { RChartLifetimeProbe.liveCount == 0 && RChartLifetimeProbe.liveWebCount == 0 && weakOwner.value == nil }
            if released { print("PASS: \(command) completes bounded cleanup after the owner closes during held decode") }
            else {
                failures.append("\(command) still retains its helper/closed owner after held post-load decode")
                // Public navigation invalidates only this owned helper's JS
                // context. No shared WebKit process is killed or inspected.
                RChartLifetimeProbe.web?.loadHTMLString("<html><body>Test cleanup</body></html>", baseURL: nil)
                let cleanup = try await wait(3) { RChartLifetimeProbe.liveCount == 0 && RChartLifetimeProbe.liveWebCount == 0 && weakOwner.value == nil }
                print("INFO: public helper navigation cleanup=\(cleanup)")
            }
            guard NSPasteboard.general.changeCount == boardChange,
                  !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else {
                throw LegacyReportError("A closed owner's pending export changed the clipboard or opened a save/error sheet")
            }
            print("PASS: \(command) publishes no late clipboard data or save/error sheet")
        }
        let cancelled = Task { @MainActor in
            do { _ = try await RChartExport.pngData(fromSVG: Data(contentsOf: source)); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        guard try await wait(10, heldDecode) else { throw LegacyReportError("Cancellation case did not reach held decode") }
        cancelled.cancel()
        guard try await wait(1, { RChartLifetimeProbe.liveCount == 0 && RChartLifetimeProbe.liveWebCount == 0 }), await cancelled.value else {
            throw LegacyReportError("Cancellation did not complete promptly and release its helper")
        }
        print("PASS: task cancellation completes promptly with CancellationError and releases the held renderer")
        let terminated = Task { @MainActor in
            do { _ = try await RChartExport.pngData(fromSVG: Data(contentsOf: source)); return false }
            catch { return true }
        }
        guard try await wait(10, heldDecode) else { throw LegacyReportError("Termination case did not reach held decode") }
        if let web = RChartLifetimeProbe.web { web.navigationDelegate?.webViewWebContentProcessDidTerminate?(web) }
        guard try await wait(1, { RChartLifetimeProbe.liveCount == 0 && RChartLifetimeProbe.liveWebCount == 0 }), await terminated.value else {
            throw LegacyReportError("Post-load WebKit termination did not complete and release its helper")
        }
        print("PASS: post-load WebKit process-termination callback errors and releases the held renderer")
        // A navigation after initial load simulates invalidation of the
        // awaited JavaScript context, exercising WebKit's error completion.
        let navigationTask = Task { @MainActor in
            do { _ = try await RChartExport.pngData(fromSVG: Data(contentsOf: source)); return false }
            catch { return true }
        }
        guard try await wait(10, heldDecode) else { throw LegacyReportError("Navigation case did not reach held decode") }
        RChartLifetimeProbe.web?.loadHTMLString("<html><body>New context</body></html>", baseURL: nil)
        let navigationReleased = try await wait(3) { RChartLifetimeProbe.liveCount == 0 && RChartLifetimeProbe.liveWebCount == 0 }
        var navigationErrored = false
        if navigationReleased { navigationErrored = await navigationTask.value }
        if navigationReleased && navigationErrored { print("PASS: invalidated post-load JavaScript context completes with an error and releases its helper") }
        else { failures.append("Invalidated post-load JavaScript context did not release its helper") }
        guard failures.isEmpty else { throw LegacyReportError("FAIL: " + failures.joined(separator: "; ")) }
        print("All chart render lifetime checks passed.")
    }
}
