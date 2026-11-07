import Cocoa
import WebKit
import Darwin

@MainActor
final class ToolbarLayoutProbe: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let root: URL
    let expectedStyle: String
    var window: NSWindow!
    var web: WKWebView!
    var loaded = false
    var navigationError: Error?

    init(root: URL, expectedStyle: String) {
        self.root = root
        self.expectedStyle = expectedStyle
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "R toolbar layout probe"
        web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(web)
        // The real R document has 16 points less WebKit width than its window content.
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            web.topAnchor.constraint(equalTo: content.topAnchor),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        Task { @MainActor in
            do {
                try await run()
                fflush(stdout)
                exit(0)
            } catch {
                print("LAYOUT_PROBE_ERROR \(error.localizedDescription)")
                fflush(stdout)
                exit(1)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationError = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationError = error }

    func wait(_ name: String, _ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let navigationError { throw navigationError }
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw NSError(domain: "ToolbarLayoutProbe", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(name)"])
    }

    func run() async throws {
        try await wait("local HTML") { self.loaded }
        let actualStyle = NSScroller.preferredScrollerStyle == .legacy ? "legacy" : "overlay"
        guard (expectedStyle == "Always" && actualStyle == "legacy") ||
              (expectedStyle == "WhenScrolling" && actualStyle == "overlay") else {
            throw NSError(domain: "ToolbarLayoutProbe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Requested \(expectedStyle), got \(actualStyle)"])
        }
        _ = try await web.callAsyncJavaScript("""
        await document.fonts.ready;
        const toolbar = document.querySelector('.toolbar');
        if (!toolbar || !toolbar.querySelector('.toolbar-controls')) throw new Error('Expected exact v2 toolbar markup');
        window.__toolbarLayoutBase = {markup:toolbar.innerHTML, style:toolbar.getAttribute('style') || '',
          bodyStyle:document.body.getAttribute('style') || ''};
        return true;
        """, arguments: [:], in: nil, contentWorld: .page)
        let variants = ["original-flex", "v2", "body-grid", "block-scrollport-in-flex-shell",
                        "flex-basis-max-content", "flex-basis-content", "height-fit-content",
                        "forced-horizontal-scroll-diagnostic"]
        var rows = 0
        var classicOverflowMeasured = false
        for variant in variants {
            _ = try await web.callAsyncJavaScript("""
            const toolbar = document.querySelector('.toolbar'), base = window.__toolbarLayoutBase;
            const shell = toolbar.parentElement;
            if (shell !== document.body) { document.body.insertBefore(toolbar, shell); shell.remove(); }
            toolbar.innerHTML = base.markup;
            toolbar.style.cssText = base.style;
            document.body.style.cssText = base.bodyStyle;
            document.getElementById('open-in-r').hidden = false;
            switch (variant) {
              case 'original-flex': {
                const row = toolbar.querySelector('.toolbar-controls');
                while (row.firstChild) toolbar.insertBefore(row.firstChild, row);
                row.remove();
                toolbar.style.display = 'flex';
                toolbar.style.alignItems = 'center';
                toolbar.style.gap = matchMedia('(max-width:570px)').matches ? '1px' : '4px';
                break;
              }
              case 'body-grid':
                document.body.style.display = 'grid';
                document.body.style.gridTemplateRows = 'auto minmax(0,1fr) auto';
                break;
              case 'block-scrollport-in-flex-shell': {
                const frame = document.createElement('div');
                frame.className = 'toolbar-frame';
                frame.style.flexShrink = '0';
                toolbar.before(frame); frame.append(toolbar);
                break;
              }
              case 'flex-basis-max-content': toolbar.style.flexBasis = 'max-content'; break;
              case 'flex-basis-content': toolbar.style.flexBasis = 'content'; break;
              case 'height-fit-content': toolbar.style.height = 'fit-content'; break;
              case 'forced-horizontal-scroll-diagnostic': toolbar.style.overflowX = 'scroll'; break;
            }
            return true;
            """, arguments: ["variant": variant], in: nil, contentWorld: .page)
            for (pass, width) in [420, 320, 420, 320, 900].enumerated() {
                window.setContentSize(NSSize(width: CGFloat(width), height: 700))
                window.contentView?.layoutSubtreeIfNeeded()
                var previous: (native: Double, web: Double)?
                var stable = 0
                try await wait("viewport \(variant)/\(width)") {
                    self.window.contentView?.layoutSubtreeIfNeeded()
                    let native = Double(self.web.bounds.width)
                    let rendered = try await self.web.evaluateJavaScript("window.innerWidth") as? Double ?? 0
                    if native > 200 && abs(native-rendered) <= 1 {
                        if let previous, abs(previous.native-native) <= 0.5, abs(previous.web-rendered) <= 0.5 { stable += 1 }
                        else { stable = 1 }
                    } else { stable = 0 }
                    previous = (native, rendered)
                    return stable >= 3
                }
                var row = try await web.callAsyncJavaScript("""
                const toolbar = document.querySelector('.toolbar');
                // The original-layout gap responds to every resize, as its original media query did.
                if (variant==='original-flex') toolbar.style.gap=matchMedia('(max-width:570px)').matches?'1px':'4px';
                const frame=()=>new Promise(resolve=>{
                  const timeout=setTimeout(resolve,100);
                  requestAnimationFrame(()=>{clearTimeout(timeout);resolve();});
                });
                const rect=r=>({left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height});
                const view=()=>{
                  const outer=toolbar.getBoundingClientRect(),s=getComputedStyle(toolbar);
                  const left=outer.left+toolbar.clientLeft,top=outer.top+toolbar.clientTop;
                  return {outer:rect(outer),clip:{left,top,right:left+toolbar.clientWidth,bottom:top+toolbar.clientHeight},
                    clientWidth:toolbar.clientWidth,clientHeight:toolbar.clientHeight,
                    scrollWidth:toolbar.scrollWidth,scrollHeight:toolbar.scrollHeight,
                    scrollLeft:toolbar.scrollLeft,scrollTop:toolbar.scrollTop,
                    display:s.display,flexBasis:s.flexBasis,height:s.height,
                    horizontalScrollbar:Math.max(0,toolbar.offsetHeight-toolbar.clientHeight-parseFloat(s.borderTopWidth)-parseFloat(s.borderBottomWidth)),
                    verticalScrollbar:Math.max(0,toolbar.offsetWidth-toolbar.clientWidth-parseFloat(s.borderLeftWidth)-parseFloat(s.borderRightWidth))};
                };
                toolbar.scrollLeft=0;toolbar.scrollTop=0;await frame();await frame();
                const buttons=Array.from(toolbar.querySelectorAll('button'));
                let reachable=buttons.length>0;const failures=[];
                for(let index=0;index<buttons.length;index++){
                  const button=buttons[index];button.scrollIntoView({block:'nearest',inline:'nearest'});
                  const deadline=performance.now()+1000;let metric;
                  do{
                    await frame();
                    const b=button.getBoundingClientRect(),v=view();
                    const hit=document.elementFromPoint((b.left+b.right)/2,(b.top+b.bottom)/2);
                    metric={id:button.id,index,button:rect(b),...v,hit:hit?hit.tagName+'#'+hit.id:null,
                      reachable:b.width>0&&b.height>0&&b.left>=v.clip.left-1&&b.right<=v.clip.right+1&&b.top>=v.clip.top&&b.bottom<=v.clip.bottom&&button.contains(hit)};
                    if(metric.reachable)break;
                  }while(performance.now()<deadline);
                  if(!metric.reachable){reachable=false;failures.push(metric);break;}
                }
                const v=view(),main=document.querySelector('main').getBoundingClientRect(),footer=document.querySelector('footer').getBoundingClientRect();
                const needsScroll=toolbar.scrollWidth>toolbar.clientWidth;
                const didScroll=toolbar.scrollLeft>0;
                const noVerticalOverflow=toolbar.scrollHeight<=toolbar.clientHeight+1;
                const noBodyOverflow=document.documentElement.scrollWidth<=document.documentElement.clientWidth+1&&document.body.scrollWidth<=document.documentElement.clientWidth+1;
                const nativeScroll=['auto','scroll'].includes(getComputedStyle(toolbar).overflowX);
                const paneLayout=main.height>0&&main.top>=v.outer.bottom-1&&footer.top>=main.bottom-1&&footer.bottom<=innerHeight+1;
                return {variant,...v,viewportWidth:innerWidth,viewportHeight:innerHeight,
                  main:rect(main),footer:rect(footer),buttonCount:buttons.length,failures,
                  needsScroll,didScroll,noVerticalOverflow,noBodyOverflow,nativeScroll,paneLayout,
                  fitsWithoutExtraBar:needsScroll||v.horizontalScrollbar===0,
                  wideHeightWhenFits:needsScroll||Math.abs(v.outer.height-42)<=1,
                  toolbarOK:reachable&&noVerticalOverflow&&noBodyOverflow&&nativeScroll&&paneLayout&&(!needsScroll||didScroll)};
                """, arguments: ["variant": variant], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
                row["setting"] = expectedStyle
                row["nativeScrollerStyle"] = actualStyle
                row["requestedWindowWidth"] = width
                row["nativeWebWidth"] = Double(web.bounds.width)
                row["pass"] = pass+1
                if expectedStyle == "Always", row["needsScroll"] as? Bool == true,
                   (row["horizontalScrollbar"] as? Double ?? 0) > 0 { classicOverflowMeasured = true }
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("LAYOUT_PROBE_ROW " + String(decoding: data, as: UTF8.self))
                fflush(stdout)
                rows += 1
            }
        }
        guard expectedStyle != "Always" || classicOverflowMeasured else {
            throw NSError(domain: "ToolbarLayoutProbe", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Always run never measured a real classic horizontal scrollbar"])
        }
        print("LAYOUT_PROBE_COMPLETED setting=\(expectedStyle) rows=\(rows) style=\(actualStyle)")
    }
}

guard CommandLine.arguments.count == 3 else {
    print("Usage: swift ToolbarLayoutProbe.swift <Content/RConsole directory> <Always|WhenScrolling>")
    exit(2)
}
let contentRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let setting = CommandLine.arguments[2]
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ToolbarLayoutProbe(root: contentRoot, expectedStyle: setting)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}

