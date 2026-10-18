import Cocoa
import WebKit

@main struct GridSelectionTests {
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:650),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="StatsDirect column selection checks"
        let web=WKWebView(); window.contentView=web
        web.loadFileURL(root.appendingPathComponent("Content/Grid/index.html"),allowingReadAccessTo:root.appendingPathComponent("Content"))
        // Synthetic events still need the same focused, laid-out worksheet as
        // a user's gesture. An inactive window can have a canvas before Glide's
        // visible-region and input effects have settled.
        window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
        window.contentView?.layoutSubtreeIfNeeded(); window.makeFirstResponder(web)
        let watchdog=DispatchWorkItem { print("FAIL: column selection checks timed out"); fflush(stdout); exit(1) }
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:watchdog)
        Task { @MainActor in
            do {
                var ready=false
                for _ in 0..<100 {
                    if window.isKeyWindow, app.isActive, (try? await web.evaluateJavaScript("document.hasFocus() && document.visibilityState==='visible' && !!window.statsDirectGrid && !!document.querySelector('.dvn-scroller') && document.querySelector('canvas')?.getBoundingClientRect().width > 0")) as? Bool==true { ready=true; break }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                guard ready else {throw NSError(domain:"GridSelectionTests",code:1,userInfo:[NSLocalizedDescriptionKey:"Grid did not acquire native/browser focus and a rendered canvas before the gesture"])}
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
