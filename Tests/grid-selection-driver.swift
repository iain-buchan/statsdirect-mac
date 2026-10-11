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
        window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
        let watchdog=DispatchWorkItem { print("FAIL: column selection checks timed out"); fflush(stdout); exit(1) }
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:watchdog)
        Task { @MainActor in
            do {
                for _ in 0..<100 {
                    if (try? await web.evaluateJavaScript("!!window.statsDirectGrid && !!document.querySelector('.dvn-scroller')")) as? Bool==true { break }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                let script=try String(contentsOf:root.appendingPathComponent("Tests/grid-selection-ui.js"),encoding:.utf8)
                let result=try await web.callAsyncJavaScript(script,arguments:[:],in:nil,contentWorld:.page)
                print(result ?? "No result"); fflush(stdout)
                watchdog.cancel()
                if !CommandLine.arguments.contains("--stay-open") { app.terminate(nil) }
            } catch { print("FAIL: \(error)"); fflush(stdout); exit(1) }
        }
        app.run()
    }
}
