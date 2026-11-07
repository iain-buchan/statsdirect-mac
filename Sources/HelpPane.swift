import Cocoa
import WebKit
import UniformTypeIdentifiers

@MainActor
private final class HelpNavigationButton: NSButton {
    // Like AppKit's own buttons, these take keyboard focus only when enabled and Keyboard navigation is on, so with it off
    // a click leaves focus in the page and Escape from Index returns there.
    override var acceptsFirstResponder: Bool { HelpPane.keyboardNavigation() && isEnabled }
    override var canBecomeKeyView: Bool { HelpPane.keyboardNavigation() && isEnabled && !isHiddenOrHasHiddenAncestor && window != nil }
    override func keyDown(with event: NSEvent) {
        if [36,76].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            performClick(nil)
        } else if event.keyCode == 48, event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        } else { super.keyDown(with:event) }
    }
}

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
    let backButton: NSButton = HelpNavigationButton(title:"‹",target:nil,action:nil)
    let forwardButton: NSButton = HelpNavigationButton(title:"›",target:nil,action:nil)
    let homeButton: NSButton = HelpNavigationButton(title:"Home",target:nil,action:nil)
    let contentsButton: NSButton = HelpNavigationButton(title:"Contents",target:nil,action:nil)
    let indexButton: NSButton = HelpNavigationButton(title:"Index",target:nil,action:nil)
    let indexPicker = HelpIndexPicker()
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
    // Data/Alias.xml's maps in Windows's order, for topics and the keyword index, which ignore the case of names and IDs.
    private var aliasMaps: [(key: String, link: String)] = []
    // HelpCatalog's aliases and packaged pages, listed on the first topic request.
    private lazy var topics = HelpKeywordIndex.Topics(root:resources.root,aliases:HelpKeywordIndex.Aliases(aliasMaps))
    private var hasDocument = false
    private var commandGeneration = 0
    private var pendingContents: (id: Int, completion: ((Bool) -> Void)?)?
    private var pendingIndex: (id: Int, completion: ((Bool) -> Void)?)?
    private var notifications: [NSObjectProtocol] = []
    private var toolbarKeyMonitor: Any?
    private var stopped = false
    // Loaded once it succeeds; a missing or failed index is looked at again on the next Index, as on Windows.
    private var keywordIndex: HelpKeywordIndex?
    /// The system's Keyboard navigation setting; the native driver replaces it to check both behaviours.
    static var keyboardNavigation: () -> Bool = { NSApp.isFullKeyboardAccessEnabled }
    // Injectable only for native verification; normal clicks use the system browser.
    var willShow: (() -> Void)?
    var externalLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    // The help pages are the web reader. Inside this pane its banner, search box and menu button repeat the native
    // Home, Contents, Index and search controls, so they are hidden here only, as in the Windows help window (5.3.4).
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
    // The native hosts execute the same reader commands.
    static let contentsScript = """
    (() => {
        const contents = document.getElementById('contents');
        if (!contents) return 'no-contents';
        const navigation = document.getElementById('help-navigation');
        const toggle = document.getElementById('navigation-toggle');
        if (toggle && navigation && getComputedStyle(navigation).display === 'none') toggle.click();
        if (contents.hidden || document.getElementById('results')?.hidden === false)
            document.getElementById('contents-tab')?.click();
        const path = location.pathname.slice(1);
        const folder = path.slice(0, path.lastIndexOf('/') + 1);
        const overview = folder ? [...contents.querySelectorAll('details > ul > li:first-child > a')]
            .find(a => a.dataset.link?.startsWith(folder)) : null;
        const link = contents.querySelector('a[aria-current="page"]') ?? overview ?? contents.querySelector('a');
        if (!link) return 'not-focused';
        for (let p = link.parentElement; p && p !== contents; p = p.parentElement)
            if (p.tagName === 'DETAILS') p.open = true;
        if (!link.getClientRects().length) return 'not-focused';
        (link.closest('li') ?? link).scrollIntoView({block: 'nearest', inline: 'nearest'});
        link.focus({preventScroll: true});
        return document.activeElement === link ? 'focused' : 'not-focused';
    })()
    """
    static let closeContentsScript = """
    (() => {
        if (document.body.classList.contains('navigation-open')) {
            const toggle = document.getElementById('navigation-toggle');
            if (!toggle) return false;
            toggle.click();
        }
        return !document.body.classList.contains('navigation-open');
    })()
    """

    init(root: URL) {
        resources = HelpResources(root:root)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(resources, forURLScheme:"app")
        // Tab moves link by link through the help, as in the Windows help window, so the entry Contents focuses starts a
        // keyboard route through the tree.
        config.preferences.tabFocusesLinks = true
        config.userContentController.addUserScript(WKUserScript(source:HelpPane.nativeToolbarStyle,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        config.userContentController.addUserScript(WKUserScript(source:"for(const type of ['wheel','pointerdown','keydown']) addEventListener(type,()=>{window.__sdHelpPosition=null;},{capture:true,passive:true});",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        web = WKWebView(frame:.zero,configuration:config)
        super.init()
        web.navigationDelegate = self; web.uiDelegate = self
        // XMLParser handles attribute order and XML escaping in Flare's alias file.
        let catalog = HelpAliasParser()
        if let parser = XMLParser(contentsOf:root.appendingPathComponent("Data/Alias.xml")) { parser.delegate = catalog; if parser.parse() { aliasMaps = catalog.maps } }
        let top = NSStackView(); top.spacing = 6
        heading.font = .systemFont(ofSize:12,weight:.semibold); heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        modeButton.target = self; modeButton.action = #selector(toggleMode)
        let close = NSButton(title:"×",target:self,action:#selector(hide)); close.setAccessibilityLabel("Close help"); close.toolTip = "Close help"
        // Print sits beside Pop out so the navigation row keeps Home, Contents, Index and search at the narrowest dock.
        let print = NSButton(title:"Print",target:self,action:#selector(printHelp)); print.toolTip = "Print this help topic"
        for button in [print,modeButton,close] { button.refusesFirstResponder = true; button.controlSize = .small }
        // The title takes the leading side and the buttons stay at the trailing edge whatever the page title.
        top.addView(heading,in:.leading); for button in [print,modeButton,close] { top.addView(button,in:.trailing) }
        let navigation = NSStackView(); navigation.spacing = 4
        backButton.target = self; backButton.action = #selector(back); backButton.setAccessibilityLabel("Help back")
        forwardButton.target = self; forwardButton.action = #selector(forward); forwardButton.setAccessibilityLabel("Help forward")
        homeButton.target = self; homeButton.action = #selector(contents); homeButton.toolTip = "Open the help home page"
        contentsButton.target = self; contentsButton.action = #selector(browseTopicsAction); contentsButton.isEnabled = false
        contentsButton.toolTip = "Show the help contents"
        indexButton.target = self; indexButton.action = #selector(indexAction); indexButton.isEnabled = false
        indexButton.toolTip = "Find a topic by an index keyword"
        indexPicker.fallbackFocus = web
        indexPicker.onChoose = { [weak self] entry in
            guard let self, let url = URL(string:entry.path,relativeTo:HelpResources.origin)?.absoluteURL else { return }
            self.open(url)
            self.web.window?.makeFirstResponder(self.web)
        }
        // With the page's own Contents button hidden, these keep a keyboard route: Tab reaches them when Keyboard navigation is on.
        for button in [backButton,forwardButton,homeButton,contentsButton,indexButton] { button.controlSize = .small; navigation.addArrangedSubview(button) }
        searchField.placeholderString = "Search help"; searchField.setAccessibilityLabel("Search all help topics")
        searchField.target = self; searchField.action = #selector(search); searchField.sendsSearchStringImmediately = false; searchField.sendsWholeSearchString = true
        navigation.addArrangedSubview(searchField)
        linkNavigationKeyViews()
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
                        web.observe(\.canGoForward,options:[.initial,.new]) { [weak self] _,_ in MainActor.assumeIsolated { self?.forwardButton.isEnabled = self?.web.canGoForward == true } },
                        web.observe(\.url,options:[.new]) { [weak self] _,_ in MainActor.assumeIsolated { self?.cancelHelpCommands() } }]
        notifications = [
            NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelHelpCommands() }
            },
            NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:nil,queue:.main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let window = notification.object as? NSWindow,
                          window === self.web.window, !self.indexPicker.isVisible else { return }
                    self.cancelHelpCommands()
                }
            }
        ]
        // The search field editor does not reliably follow this toolbar's reverse key loop.
        toolbarKeyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.visible, event.window === self.searchField.window,
                      event.keyCode == 48, event.modifierFlags.contains(.shift), self.indexButton.canBecomeKeyView,
                      event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
                      let editor = self.searchField.currentEditor(),
                      self.searchField.window?.firstResponder === editor else { return false }
                return self.searchField.window?.makeFirstResponder(self.indexButton) == true
            }
            return handled ? nil : event
        }
    }
    private func linkNavigationKeyViews() {
        let controls: [NSView] = [backButton,forwardButton,homeButton,contentsButton,indexButton,searchField,web]
        for (previous,next) in zip(controls,controls.dropFirst()) { previous.nextKeyView = next }
    }
    func attach(to split: NSSplitView, owner: NSWindow) {
        self.split = split; self.owner = owner; split.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshModalPresentation() } }
    }
    func shutdown() {
        stopped = true
        cancelHelpCommands()
        timer?.invalidate(); timer = nil
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
        notifications.removeAll()
        if let toolbarKeyMonitor { NSEvent.removeMonitor(toolbarKeyMonitor) }
        toolbarKeyMonitor = nil
        floatingWindow?.orderOut(nil)
    }
    var isFocused: Bool {
        guard visible else { return false }
        if let panel = floatingWindow, NSApp.keyWindow === panel { return true }
        if indexPicker.isVisible, NSApp.keyWindow === indexPicker.panel { return true }
        return NSApp.keyWindow === owner && (owner?.firstResponder as? NSView)?.isDescendant(of:view) == true
    }
    /// Close (Cmd-W) with help focused: the Index picker when it has the keyboard, otherwise the pane.
    func closeFocused() {
        if indexPicker.isVisible, NSApp.keyWindow === indexPicker.panel { indexPicker.close(returnFocus:true) } else { hide() }
    }
    var hasModal: Bool { owner?.attachedSheet != nil || (NSApp.modalWindow != nil && NSApp.modalWindow !== floatingWindow) }
    /// HelpCatalog.Resolve: the packaged page named by a help ID or alias name, compared without regard to case, by a page's
    /// path, or by its address under statsdirect.com/help/, on the help's GitHub pages or at the Windows help origin; else nil.
    func url(for topic: String) -> URL? {
        topics.resolve(topic).flatMap { URL(string:$0,relativeTo:HelpResources.origin)?.absoluteURL }
    }
    static let unavailableTopicMessage = "This topic is unavailable; showing the help contents."
    /// HelpView.ShowTopic: opens the page a topic names. An http, https or mailto address that names no packaged page, and is
    /// not at the Windows help origin, opens in the system browser instead and leaves the pane and its status line alone; any
    /// other topic that names no page shows the help contents with Windows's status line.
    func showTopic(_ topic: String) {
        guard !stopped else { return }
        cancelHelpCommands()
        let page = url(for:topic)
        if page == nil, HelpKeywordIndex.isExternal(topic) { openExternal(topic); return }
        open(page)
        if page == nil { notice.stringValue = HelpPane.unavailableTopicMessage }
    }
    /// HelpView.OpenExternal for an address given as a topic, which Uri reads without its surrounding white space.
    private func openExternal(_ address: String) {
        guard let url = URL(string:address.trimmingCharacters(in:CharacterSet(charactersIn:" \t\r\n"))) else {
            notice.stringValue = "Could not open the link: the address is not valid."
            return
        }
        externalLink(url)
    }
    func open(_ file: URL? = nil) {
        guard !stopped else { return }
        cancelHelpCommands()
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
        // Each topic request clears the status line, even for the page already shown, as the Windows help window's ShowTopic does.
        notice.stringValue = ""
        if !visible { visible = true; place(floating:prefersFloating || hasModal,activate:false); temporarilyFloating = hasModal && !prefersFloating; restorePosition() }
        refreshModalPresentation()
        if web.url != target || needsReload { needsReload = false; web.load(URLRequest(url:target)) }
    }
    // Home, as Windows's ShowTopic("1000").
    @objc func contents() { showTopic("1000") }
    @objc func browseTopicsAction() { showContents() }
    @objc func indexAction() {
        if indexPicker.isVisible { cancelHelpCommands() }
        else if indexPicker.takeAnchorClick() { cancelHelpCommands() }
        else { showIndex() }
    }

    func showContents(_ completion: ((Bool) -> Void)? = nil) {
        cancelHelpCommands()
        guard !stopped, visible, !moving, let source = web.url, resources.localURL(source) != nil else { completion?(false); return }
        let id = commandGeneration
        let window = web.window
        pendingContents = (id,completion)
        web.window?.makeFirstResponder(web)
        DispatchQueue.main.asyncAfter(deadline:.now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingContents?.id == id else { return }
                self.notice.stringValue = "Could not open the help topics: the help page did not respond."
                self.finishContents(id,false)
            }
        }
        web.evaluateJavaScript(HelpPane.contentsScript) { [weak self] result,error in
            MainActor.assumeIsolated {
                guard let self, self.pendingContents?.id == id else { return }
                guard self.commandIsCurrent(id,source:source,window:window) else { self.finishContents(id,false); return }
                // Windows's script call answers null for a script error or a value it cannot return, so those read as a
                // failure to focus; any other error is reported with its message.
                if let error {
                    let code = (error as? WKError)?.code
                    if code != .javaScriptExceptionOccurred && code != .javaScriptResultTypeIsUnsupported {
                        self.notice.stringValue = "Could not open the help topics: " + error.localizedDescription
                        self.finishContents(id,false)
                        return
                    }
                }
                let answer = error == nil ? result as? String : nil
                if answer == "focused" {
                    if self.notice.stringValue.hasPrefix("Could not open the help topics") { self.notice.stringValue = "" }
                    self.finishContents(id,true)
                    return
                }
                if answer == "no-contents", source.path != "/index.html",
                   let parts = URLComponents(url:source,resolvingAgainstBaseURL:false) {
                    var topic = String(parts.percentEncodedPath.drop(while:{ $0 == "/" }))
                    if let fragment = parts.percentEncodedFragment { topic += "#" + fragment }
                    let unreserved = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                    if let encoded = topic.addingPercentEncoding(withAllowedCharacters:unreserved),
                       let reader = URL(string:"index.html#topic=" + encoded,relativeTo:HelpResources.origin)?.absoluteURL {
                        self.finishContents(id,false)
                        self.web.load(URLRequest(url:reader))
                        return
                    }
                }
                self.notice.stringValue = "Could not open the help topics. Use Home or search to find a topic."
                self.finishContents(id,false)
            }
        }
    }

    func showIndex(_ completion: ((Bool) -> Void)? = nil) {
        cancelHelpCommands()
        guard !stopped, visible, !moving, let source = web.url, resources.localURL(source) != nil else { completion?(false); return }
        guard keywordIndex != nil || HelpKeywordIndex.exists(root:resources.root) else {
            notice.stringValue = HelpKeywordIndex.unavailableMessage
            completion?(false)
            return
        }
        let id = commandGeneration
        let window = web.window
        pendingIndex = (id,completion)
        DispatchQueue.main.asyncAfter(deadline:.now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingIndex?.id == id else { return }
                self.notice.stringValue = "Could not open the help index: the help page did not respond."
                self.finishIndex(id,false)
            }
        }
        web.evaluateJavaScript(HelpPane.closeContentsScript) { [weak self] result,error in
            MainActor.assumeIsolated {
                guard let self, self.pendingIndex?.id == id else { return }
                guard self.commandIsCurrent(id,source:source,window:window) else { self.finishIndex(id,false); return }
                // A script error answers null on Windows, so it reads as a drawer that did not close.
                if let error {
                    let code = (error as? WKError)?.code
                    if code != .javaScriptExceptionOccurred && code != .javaScriptResultTypeIsUnsupported {
                        self.notice.stringValue = "Could not open the help index: " + error.localizedDescription
                        self.finishIndex(id,false)
                        return
                    }
                }
                guard error == nil, result as? Bool == true else {
                    self.notice.stringValue = "Could not close Contents to open the help index."
                    self.finishIndex(id,false)
                    return
                }
                let catalog: HelpKeywordIndex
                do {
                    guard let loaded = try self.keywordIndex ?? HelpKeywordIndex.load(root:self.resources.root,aliases:HelpKeywordIndex.Aliases(self.aliasMaps)) else {
                        self.notice.stringValue = HelpKeywordIndex.unavailableMessage
                        self.finishIndex(id,false)
                        return
                    }
                    catalog = loaded
                } catch {
                    self.notice.stringValue = "Could not open the help index: " + error.localizedDescription
                    self.finishIndex(id,false)
                    return
                }
                self.keywordIndex = catalog
                self.indexPicker.show(catalog,relativeTo:self.indexButton)
                self.finishIndex(id,self.indexPicker.isVisible)
            }
        }
    }

    private func commandIsCurrent(_ id: Int, source: URL, window: NSWindow?) -> Bool {
        !stopped && visible && !moving && commandGeneration == id && web.url == source && web.window === window
    }
    private func finishContents(_ id: Int, _ opened: Bool) {
        guard let pending = pendingContents, pending.id == id else { return }
        pendingContents = nil
        pending.completion?(opened)
    }
    private func finishIndex(_ id: Int, _ opened: Bool) {
        guard let pending = pendingIndex, pending.id == id else { return }
        pendingIndex = nil
        pending.completion?(opened)
    }
    private func cancelHelpCommands() {
        commandGeneration += 1
        let contents = pendingContents, index = pendingIndex
        pendingContents = nil; pendingIndex = nil
        indexPicker.close()
        contents?.completion?(false)
        index?.completion?(false)
    }
    @objc func search() {
        let query = searchField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? ""
        open(URL(string:"index.html#searchQuery=" + encoded,relativeTo:HelpResources.origin)!.absoluteURL)
    }
    @objc func back() { cancelHelpCommands(); web.goBack() }
    @objc func forward() { cancelHelpCommands(); web.goForward() }
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
        cancelHelpCommands()
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
        cancelHelpCommands()
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
        linkNavigationKeyViews()
        if restoreOwner { (owner.attachedSheet ?? owner).makeKeyAndOrderFront(nil) }
    }
    @objc func hide() {
        cancelHelpCommands()
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
        if resources.localURL(url) != nil {
            if action.targetFrame?.isMainFrame != false { cancelHelpCommands() }
            decisionHandler(.allow); return
        }
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
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!) {
        cancelHelpCommands()
        contentsButton.isEnabled = false; indexButton.isEnabled = false
    }
    func webView(_ webView:WKWebView,didCommit navigation:WKNavigation!) { hasDocument = false }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        hasDocument = true; contentsButton.isEnabled = true; indexButton.isEnabled = true
        linkNavigationKeyViews()
        heading.stringValue = web.title ?? "Help"; floatingWindow?.title = (web.title ?? "Help") + " · StatsDirect"
        // Windows's NavigationCompleted leaves the status line alone, so the line ShowTopic gives an unavailable topic stays
        // beside the contents it opened. Other lines, such as an earlier failure to load, clear once a page loads.
        if notice.stringValue != HelpPane.unavailableTopicMessage { notice.stringValue = "" }
        restorePosition()
    }
    // A load that fails before it commits leaves the previous page on screen, so Contents follows that page.
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { contentsButton.isEnabled = hasDocument; indexButton.isEnabled = hasDocument; failed(error) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { contentsButton.isEnabled = (error as NSError).code == NSURLErrorCancelled; indexButton.isEnabled = contentsButton.isEnabled; failed(error) }
    private func failed(_ error:Error) { if (error as NSError).code != NSURLErrorCancelled { notice.stringValue = "Help could not load: " + error.localizedDescription } }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { cancelHelpCommands(); needsReload = true; hasDocument = false; contentsButton.isEnabled = false; indexButton.isEnabled = false; notice.stringValue = "Help stopped. Choose a help topic to reopen it." }
}

private final class HelpAliasParser: NSObject, XMLParserDelegate {
    /// Each Map's Name and then its ResolvedId, skipping blank keys, in document order, as HelpCatalog's constructor reads them.
    var maps: [(key: String, link: String)] = []
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes:[String:String]) {
        guard elementName == "Map", let link = attributes["Link"] else { return }
        for key in [attributes["Name"], attributes["ResolvedId"]] {
            if let key, !key.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) { maps.append((key, link)) }
        }
    }
}
