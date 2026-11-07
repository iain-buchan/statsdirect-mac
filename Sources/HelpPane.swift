import Cocoa
import WebKit
import UniformTypeIdentifiers

// Flare recognises app: as a desktop protocol (its XML loader ignores unknown schemes).
// A private origin serves only the bundled help. No worksheet/report bridges are
// registered here; CSP also prevents help scripts fetching remote content.
@MainActor
final class HelpResources: NSObject, WKURLSchemeHandler {
    static let origin = URL(string: "app://statsdirect-help/")!
    let root: URL
    private(set) var missing: [String] = []
    private var files: [String: URL] = [:]
    init(root: URL) {
        self.root = root.resolvingSymlinksInPath()
        super.init()
        // Flare's Windows output contains mixed-case links (Scripts vs scripts).
        // Resolve using a catalogue so help also works on case-sensitive Mac volumes.
        // Key files by the path the enumerator reports relative to the root. Absolute paths fail when the bundle is under
        // /private, as App Translocation runs a downloaded app opened in place: resolving symlinks drops /private from the
        // root but not from the enumerated files, which shifted every key and left the help empty.
        if let entries = FileManager.default.enumerator(atPath:self.root.path) {
            while let relative = entries.nextObject() as? String {
                guard entries.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
                files["/" + relative.lowercased()] = self.root.appendingPathComponent(relative)
            }
        }
    }
    func localURL(_ url: URL) -> URL? {
        guard url.scheme == "app", url.host == "statsdirect-help", url.user == nil, url.password == nil, url.port == nil else { return nil }
        let file = root.appendingPathComponent(url.path).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        return files[String(file.path.dropFirst(root.path.count)).lowercased()]
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, task.request.httpMethod == "GET" else { task.didFailWithError(URLError(.noPermissionsToReadFile)); return }
        guard let file = localURL(url) else {
            if url.scheme == "app", url.host == "statsdirect-help" { missing.append(url.path) }
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        guard var data = try? Data(contentsOf: file) else { missing.append(url.path); task.didFailWithError(URLError(.fileDoesNotExist)); return }
        // Preserve the imported Windows bundle and its hashes; present the Mac menu
        // location in the calculator topic, including when it is copied or printed.
        if file == root.appendingPathComponent("basics/calculator.htm"), let html = String(data:data,encoding:.utf8) {
            data = Data(html.replacingOccurrences(of:"Tools &gt; Calculator",with:"Analysis &gt; Calculator")
                .replacingOccurrences(of:"selected from the Tools menu",with:"selected from the Analysis menu").utf8)
        }
        let types = ["js":"text/javascript", "css":"text/css", "htm":"text/html", "html":"text/html", "xml":"application/xml", "json":"application/json", "svg":"image/svg+xml"]
        let type = types[file.pathExtension.lowercased()] ?? UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type":type + (type.hasPrefix("text/") ? "; charset=utf-8" : ""),
                       "Content-Security-Policy":"default-src 'self' app: data: blob:; script-src 'self' app: 'unsafe-inline' 'unsafe-eval'; style-src 'self' app: 'unsafe-inline'; connect-src 'self' app:; object-src 'none'; frame-src 'none'; base-uri 'self'; form-action 'none'",
                       "Access-Control-Allow-Origin":"*", "Cache-Control":"no-cache"]
        task.didReceive(HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:headers)!)
        task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@MainActor
final class HelpPane: NSObject, WKNavigationDelegate, WKUIDelegate, NSSplitViewDelegate, NSWindowDelegate {
    let view = NSView()
    let web: WKWebView
    let resources: HelpResources
    let searchField = NSSearchField()
    let modeButton = NSButton(title:"Pop out",target:nil,action:nil)
    let backButton = NSButton(title:"‹",target:nil,action:nil)
    let forwardButton = NSButton(title:"›",target:nil,action:nil)
    let browseButton = NSButton(title:"Browse topics",target:nil,action:nil)
    let heading = NSTextField(labelWithString:"Help")
    let notice = NSTextField(labelWithString:"")
    weak var owner: NSWindow?
    weak var split: NSSplitView?
    private(set) var floatingWindow: NSPanel?
    private(set) var visible = false
    private(set) var prefersFloating = false
    private(set) var temporarilyFloating = false
    private(set) var dockWidth: CGFloat = 460
    private var moving = false
    private var needsReload = false
    private var timer: Timer?
    private var observations: [NSKeyValueObservation] = []
    private var aliases: [String:String] = [:]
    private var hasDocument = false
    private var browseRequests = 0
    private var pendingBrowse: (id: Int, completion: ((Bool) -> Void)?)?
    // Injectable only for native verification; normal clicks use the system browser.
    var willShow: (() -> Void)?
    var externalLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    // The help pages are the web reader. Inside this pane its banner, search box and menu button repeat the native
    // Home, Browse topics and search controls, so they are hidden here only, as in the Windows help window (5.3.4).
    static let nativeToolbarStyle = """
    (() => {
        if (window !== window.top || location.protocol !== 'app:' || location.host !== 'statsdirect-help') return;
        const style = document.createElement('style');
        style.textContent = `
            :root[data-help-skin]:has(> body > header > .help-identity){--help-height:0px !important}
            html[data-help-skin] > body > header:has(> .help-identity),
            html[data-help-skin] > body > main > aside > #search-form{display:none !important}
        `;
        if (document.head) document.head.append(style);
        else {
            const observer = new MutationObserver(() => {
                if (!document.head) return;
                document.head.append(style);
                observer.disconnect();
            });
            observer.observe(document,{childList:true,subtree:true});
        }
    })();
    """
    // Opens the reader's own contents tree at the current topic, as the Windows Browse topics command does.
    static let browseTopicsScript = """
    (() => {
        const contents = document.getElementById('contents');
        if (!contents) return false;
        const navigation = document.getElementById('help-navigation');
        const toggle = document.getElementById('navigation-toggle');
        if (toggle && navigation && getComputedStyle(navigation).display === 'none') toggle.click();
        if (contents.hidden) document.getElementById('contents-tab')?.click();
        const link = contents.querySelector('a[aria-current="page"]') ?? contents.querySelector('a');
        if (!link?.getClientRects().length) return false;
        link.focus({preventScroll:true});
        return true;
    })()
    """

    init(root: URL) {
        resources = HelpResources(root:root)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(resources, forURLScheme:"app")
        config.userContentController.addUserScript(WKUserScript(source:HelpPane.nativeToolbarStyle,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        config.userContentController.addUserScript(WKUserScript(source:"for(const type of ['wheel','pointerdown','keydown']) addEventListener(type,()=>{window.__sdHelpPosition=null;},{capture:true,passive:true});",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        web = WKWebView(frame:.zero,configuration:config)
        super.init()
        web.navigationDelegate = self; web.uiDelegate = self
        // XMLParser handles attribute order and XML escaping in Flare's alias file.
        let catalog = HelpAliasParser()
        if let parser = XMLParser(contentsOf:root.appendingPathComponent("Data/Alias.xml")) { parser.delegate = catalog; if parser.parse() { aliases = catalog.aliases } }
        let top = NSStackView(); top.spacing = 6
        heading.font = .systemFont(ofSize:12,weight:.semibold); heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        modeButton.target = self; modeButton.action = #selector(toggleMode)
        let close = NSButton(title:"×",target:self,action:#selector(hide)); close.setAccessibilityLabel("Close help"); close.toolTip = "Close help"
        // Print sits beside Pop out so the navigation row keeps Home, Browse topics and search at the narrowest dock.
        let print = NSButton(title:"Print",target:self,action:#selector(printHelp)); print.toolTip = "Print this help topic"
        for button in [print,modeButton,close] { button.refusesFirstResponder = true; button.controlSize = .small }
        // The title takes the leading side and the buttons stay at the trailing edge whatever the page title.
        top.addView(heading,in:.leading); for button in [print,modeButton,close] { top.addView(button,in:.trailing) }
        let navigation = NSStackView(); navigation.spacing = 4
        backButton.target = self; backButton.action = #selector(back); backButton.setAccessibilityLabel("Help back")
        forwardButton.target = self; forwardButton.action = #selector(forward); forwardButton.setAccessibilityLabel("Help forward")
        let home = NSButton(title:"Home",target:self,action:#selector(contents)); home.toolTip = "Open the help home page"
        browseButton.target = self; browseButton.action = #selector(browseTopicsAction); browseButton.isEnabled = false
        browseButton.toolTip = "Show the help contents"
        // With the page's own Browse topics button hidden, these keep a keyboard route: Tab reaches them when Keyboard navigation is on.
        for button in [backButton,forwardButton,home,browseButton] { button.controlSize = .small; navigation.addArrangedSubview(button) }
        searchField.placeholderString = "Search help"; searchField.setAccessibilityLabel("Search all help topics")
        searchField.target = self; searchField.action = #selector(search); searchField.sendsSearchStringImmediately = false; searchField.sendsWholeSearchString = true
        navigation.addArrangedSubview(searchField)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant:80).isActive = true
        notice.font = .systemFont(ofSize:10); notice.textColor = .secondaryLabelColor; notice.lineBreakMode = .byTruncatingTail
        for child in [top,navigation,web,notice] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:view.topAnchor,constant:4),top.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),top.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),top.heightAnchor.constraint(equalToConstant:25),
            navigation.topAnchor.constraint(equalTo:top.bottomAnchor,constant:3),navigation.leadingAnchor.constraint(equalTo:top.leadingAnchor),navigation.trailingAnchor.constraint(equalTo:top.trailingAnchor),navigation.heightAnchor.constraint(equalToConstant:26),
            web.topAnchor.constraint(equalTo:navigation.bottomAnchor,constant:4),web.leadingAnchor.constraint(equalTo:view.leadingAnchor),web.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            notice.topAnchor.constraint(equalTo:web.bottomAnchor,constant:2),notice.leadingAnchor.constraint(equalTo:top.leadingAnchor),notice.trailingAnchor.constraint(equalTo:top.trailingAnchor),notice.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-2),notice.heightAnchor.constraint(equalToConstant:13)
        ])
        observations = [web.observe(\.canGoBack,options:[.initial,.new]) { [weak self] _,_ in MainActor.assumeIsolated { self?.backButton.isEnabled = self?.web.canGoBack == true } },
                        web.observe(\.canGoForward,options:[.initial,.new]) { [weak self] _,_ in MainActor.assumeIsolated { self?.forwardButton.isEnabled = self?.web.canGoForward == true } }]
    }
    func attach(to split: NSSplitView, owner: NSWindow) {
        self.split = split; self.owner = owner; split.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshModalPresentation() } }
    }
    func shutdown() { timer?.invalidate(); timer = nil; floatingWindow?.orderOut(nil) }
    var isFocused: Bool {
        guard visible else { return false }
        if let panel = floatingWindow, NSApp.keyWindow === panel { return true }
        return NSApp.keyWindow === owner && (owner?.firstResponder as? NSView)?.isDescendant(of:view) == true
    }
    var hasModal: Bool { owner?.attachedSheet != nil || (NSApp.modalWindow != nil && NSApp.modalWindow !== floatingWindow) }
    func url(for topic: String) -> URL? {
        guard let relative = aliases[topic] else { return nil }
        return URL(string:relative,relativeTo:HelpResources.origin)?.absoluteURL
    }
    func open(_ file: URL? = nil) {
        willShow?()
        var target = url(for:"1000") ?? HelpResources.origin.appendingPathComponent("index.html")
        if let file {
            if file.isFileURL {
                let path = file.resolvingSymlinksInPath().path
                guard path.hasPrefix(resources.root.path + "/") else { return }
                let relative = String(path.dropFirst(resources.root.path.count + 1))
                var parts = URLComponents(url:HelpResources.origin.appendingPathComponent(relative),resolvingAgainstBaseURL:false)!
                parts.percentEncodedFragment = URLComponents(url:file,resolvingAgainstBaseURL:false)?.percentEncodedFragment
                target = parts.url!
            } else if resources.localURL(file) != nil { target = file } else { return }
        }
        if !visible { visible = true; place(floating:prefersFloating || hasModal,activate:false); temporarilyFloating = hasModal && !prefersFloating; restorePosition() }
        refreshModalPresentation()
        if web.url != target || needsReload { needsReload = false; web.load(URLRequest(url:target)) }
    }
    @objc func contents() { open() }
    @objc func browseTopicsAction() { browseTopics() }
    /// Shows the reader's contents tree with the current topic focused. A page without a tree opens the reader at the
    /// same topic. The completion receives true when the tree opened in place.
    func browseTopics(_ completion: ((Bool) -> Void)? = nil) {
        guard let source = web.url, resources.localURL(source) != nil else { completion?(false); return }
        finishBrowse(pendingBrowse?.id ?? -1, false)
        browseRequests += 1; let id = browseRequests
        pendingBrowse = (id, completion)
        web.window?.makeFirstResponder(web)
        // The Windows help window gives the page five seconds.
        DispatchQueue.main.asyncAfter(deadline:.now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingBrowse?.id == id else { return }
                self.notice.stringValue = "Could not open the help topics: the help page did not respond."
                self.finishBrowse(id, false)
            }
        }
        web.evaluateJavaScript(HelpPane.browseTopicsScript) { [weak self] result, error in
            MainActor.assumeIsolated {
                guard let self, self.pendingBrowse?.id == id else { return }
                if let error { self.notice.stringValue = "Could not open the help topics: " + error.localizedDescription; self.finishBrowse(id, false); return }
                let opened = result as? Bool == true
                // Standalone topics in the alternative layouts have no tree: open the reader with the same topic selected, as on
                // Windows. The page's percent-encoded path is encoded again, as Windows's Uri.EscapeDataString does.
                if !opened, self.visible, self.web.url == source, source.path != "/index.html",
                   let parts = URLComponents(url:source,resolvingAgainstBaseURL:false) {
                    var topic = String(parts.percentEncodedPath.drop(while:{ $0 == "/" }))
                    if let fragment = parts.percentEncodedFragment { topic += "#" + fragment }
                    let unreserved = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                    if let encoded = topic.addingPercentEncoding(withAllowedCharacters:unreserved),
                       let reader = URL(string:"index.html#topic=" + encoded, relativeTo:HelpResources.origin)?.absoluteURL { self.web.load(URLRequest(url:reader)) }
                }
                self.finishBrowse(id, opened)
            }
        }
    }
    private func finishBrowse(_ id: Int, _ opened: Bool) {
        guard let pending = pendingBrowse, pending.id == id else { return }
        pendingBrowse = nil
        pending.completion?(opened)
    }
    @objc func search() {
        let query = searchField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? ""
        open(URL(string:"index.html#searchQuery=" + encoded,relativeTo:HelpResources.origin)!.absoluteURL)
    }
    @objc func back() { web.goBack() }
    @objc func forward() { web.goForward() }
    @objc func printHelp() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        web.printOperation(with:info).runModal(for:floatingWindow?.isVisible == true ? floatingWindow! : owner!,delegate:nil,didRun:nil,contextInfo:nil)
    }
    @objc func toggleMode() {
        guard !hasModal, !moving else { return }
        prefersFloating.toggle(); move(floating:prefersFloating,activate:prefersFloating)
    }
    func refreshModalPresentation() {
        guard visible, !moving else { return }
        let modal = hasModal
        modeButton.isEnabled = !modal
        if modal && view.window === owner { temporarilyFloating = !prefersFloating; move(floating:true,activate:false) }
        else if !modal && temporarilyFloating { temporarilyFloating = false; move(floating:prefersFloating,activate:false) }
        floatingWindow?.level = modal ? .modalPanel : .normal
    }
    private func move(floating: Bool, activate: Bool) {
        moving = true
        web.evaluateJavaScript("window.__sdHelpPosition ??= [...document.querySelectorAll('*')].filter(e=>e.scrollTop || e.scrollLeft).map(e=>({e,x:e.scrollLeft,y:e.scrollTop})); void 0;") { [weak self] _,_ in
            guard let self else { return }
            if self.visible {
                self.place(floating:floating,activate:activate)
                self.restorePosition()
            }
            self.moving = false
        }
    }
    private func restorePosition() {
        web.evaluateJavaScript("requestAnimationFrame(()=>requestAnimationFrame(()=>{for(const p of window.__sdHelpPosition || []) if(p.e.isConnected) p.e.scrollTo(p.x,p.y);})); void 0;")
    }
    private func place(floating: Bool, activate: Bool) {
        guard let split, let owner else { return }
        let restoreOwner = !floating && floatingWindow?.isKeyWindow == true
        if view.superview === split { dockWidth = view.frame.width }
        view.removeFromSuperview()
        if floating {
            if floatingWindow == nil {
                let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:650,height:750),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
                panel.title = "StatsDirect Help"; panel.minSize = NSSize(width:360,height:360); panel.isReleasedWhenClosed = false
                panel.worksWhenModal = true; panel.hidesOnDeactivate = false; panel.delegate = self; panel.center(); floatingWindow = panel
            }
            view.autoresizingMask = [.width,.height]; view.translatesAutoresizingMaskIntoConstraints = true
            floatingWindow!.contentView = view
            floatingWindow!.level = hasModal ? .modalPanel : .normal
            if activate { floatingWindow!.makeKeyAndOrderFront(nil) } else { floatingWindow!.orderFront(nil) }
            modeButton.title = "Dock"
        } else {
            floatingWindow?.contentView = nil; floatingWindow?.orderOut(nil)
            view.translatesAutoresizingMaskIntoConstraints = true; view.autoresizingMask = [.width,.height]
            split.addArrangedSubview(view); split.adjustSubviews()
            split.setPosition(max(320,split.bounds.width - min(dockWidth,split.bounds.width - 320) - split.dividerThickness),ofDividerAt:0)
            modeButton.title = "Pop out"
        }
        split.adjustSubviews(); modeButton.isEnabled = !hasModal
        if restoreOwner { (owner.attachedSheet ?? owner).makeKeyAndOrderFront(nil) }
    }
    @objc func hide() {
        guard visible else { return }
        if view.superview === split { dockWidth = view.frame.width }
        // Keep the view attached to its hidden companion or offscreen, never reload it.
        web.evaluateJavaScript("window.__sdHelpPosition ??= [...document.querySelectorAll('*')].filter(e=>e.scrollTop || e.scrollLeft).map(e=>({e,x:e.scrollLeft,y:e.scrollTop})); void 0;")
        visible = false; temporarilyFloating = false
        view.removeFromSuperview(); floatingWindow?.orderOut(nil); split?.adjustSubviews()
        if owner?.isVisible == true { (owner?.attachedSheet ?? owner)?.makeKeyAndOrderFront(nil) }
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool { hide(); return false }
    func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int) -> CGFloat { 320 }
    func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int) -> CGFloat { max(320,splitView.bounds.width - 340) }
    func splitView(_ splitView:NSSplitView,shouldAdjustSizeOfSubview view:NSView) -> Bool { view !== self.view }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if resources.localURL(url) != nil { decisionHandler(.allow); return }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false, ["https","http","mailto"].contains(url.scheme ?? "") { externalLink(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if action.navigationType == .linkActivated, let url = action.request.url {
            if resources.localURL(url) != nil { open(url) }
            else if ["https","http","mailto"].contains(url.scheme ?? "") { externalLink(url) }
        }
        return nil
    }
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!) { browseButton.isEnabled = false }
    func webView(_ webView:WKWebView,didCommit navigation:WKNavigation!) { hasDocument = false }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        hasDocument = true; browseButton.isEnabled = true
        heading.stringValue = web.title ?? "Help"; floatingWindow?.title = (web.title ?? "Help") + " · StatsDirect"
        notice.stringValue = ""
        restorePosition()
    }
    // A load that fails before it commits leaves the previous page on screen, so Browse topics follows that page.
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { browseButton.isEnabled = hasDocument; failed(error) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { browseButton.isEnabled = (error as NSError).code == NSURLErrorCancelled; failed(error) }
    private func failed(_ error:Error) { if (error as NSError).code != NSURLErrorCancelled { notice.stringValue = "Help could not load: " + error.localizedDescription } }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { needsReload = true; hasDocument = false; browseButton.isEnabled = false; notice.stringValue = "Help stopped. Choose a help topic to reopen it." }
}

private final class HelpAliasParser: NSObject, XMLParserDelegate {
    var aliases:[String:String] = [:]
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes:[String:String]) {
        guard elementName == "Map", let link = attributes["Link"] else { return }
        if let id = attributes["ResolvedId"] { aliases[id] = link }
        if let name = attributes["Name"] { aliases[name] = link }
    }
}
