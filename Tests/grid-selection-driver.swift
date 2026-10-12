import Cocoa
import WebKit

@main struct GridSelectionTests {
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:650),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="StatsDirect column selection checks"
        let web=WKWebView(); window.contentView=web
        web.loadFileURL(root.appendingPathComponent("Content/Grid/index.html"),allowingReadAccessTo:root.appendingPathComponent("Content"))
        // These are synthetic WebKit events, not physical desktop gestures. Keep
        // the rendered window inactive so another app's activation cannot
        // interrupt a drag. The JavaScript still explicitly tests blur cancellation.
        window.center(); window.orderFrontRegardless()
        let watchdog=DispatchWorkItem { print("FAIL: column selection checks timed out"); fflush(stdout); exit(1) }
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:watchdog)
        Task { @MainActor in
            do {
                var ready=false
                for _ in 0..<100 {
                    if (try? await web.evaluateJavaScript("!!window.statsDirectGrid && !!document.querySelector('.dvn-scroller') && document.querySelector('canvas')?.getBoundingClientRect().width > 0")) as? Bool==true { ready=true; break }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                guard ready else {print("FAIL: grid did not acquire a rendered canvas");fflush(stdout);exit(1)}
                let script=try String(contentsOf:root.appendingPathComponent("Tests/grid-selection-ui.js"),encoding:.utf8)
                let result=try await web.callAsyncJavaScript(script,arguments:[:],in:nil,contentWorld:.page)
                print(result ?? "No result"); fflush(stdout)
                watchdog.cancel()
                if !CommandLine.arguments.contains("--stay-open") { app.terminate(nil) }
            } catch { print("FAIL: \(error); keyWindow=\(window.isKeyWindow); appActive=\(app.isActive); frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")"); fflush(stdout); exit(1) }
        }
        app.run()
    }
}
