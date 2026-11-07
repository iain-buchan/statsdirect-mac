import Cocoa
import WebKit

@main struct HelpPaneTests {
    @MainActor static func check(_ condition:Bool,_ message:String) throws {
        if !condition { throw NSError(domain:"HelpPaneTests",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        print("PASS: " + message); fflush(stdout)
    }
    @MainActor static func js(_ web:WKWebView,_ expression:String) async throws -> Any? {
        try await web.callAsyncJavaScript("return (" + expression + ");",arguments:[:],in:nil,contentWorld:.page)
    }
    @MainActor static func until(_ web:WKWebView,_ expression:String) async throws {
        let deadline=Date().addingTimeInterval(20)
        while Date()<deadline {
            if !web.isLoading, (try? await js(web,expression)) as? Bool == true { return }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let details = try? await js(web,"JSON.stringify({errors:window.helpErrors,body:document.body.innerText.slice(0,1200),blocked:window.cspBlocked})")
        print("PAGE DIAGNOSTICS: \(details ?? "unavailable")")
        throw NSError(domain:"HelpPaneTests",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out: \(expression), URL: \(web.url?.absoluteString ?? "nil")"])
    }
    @MainActor static func settle() async throws { try await Task.sleep(nanoseconds:600_000_000) }
    // The web reader's header (banner, search box, its own Contents button), as the native pane presents it.
    static let chrome = "JSON.stringify({identity:!!document.querySelector('body > header > .help-identity'),header:getComputedStyle(document.querySelector('body > header')).display,height:getComputedStyle(document.documentElement).getPropertyValue('--help-height').trim(),injected:[...document.querySelectorAll('style')].some(s=>s.textContent.includes('header:has(> .help-identity)')),toggle:document.getElementById('navigation-toggle').getClientRects().length,narrow:matchMedia('(max-width:1279px)').matches})"
    static let hiddenChrome = #"{"identity":true,"header":"none","height":"0px","injected":true,"toggle":0,"narrow":true}"#
    @MainActor static func paneButton(_ h:HelpPane,_ title:String) -> NSButton? {
        h.view.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }.first { $0.title == title }
    }
    @MainActor static func nativeUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        throw NSError(domain:"HelpPaneTests",code:4,userInfo:[NSLocalizedDescriptionKey:"Timed out waiting for a native help control"])
    }
    static func literal(_ value: String) -> String {
        String(data:try! JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]),encoding:.utf8)!
    }
    static func visibleFocus(_ path: String) -> String {
        """
        (() => {
            const link=[...document.querySelectorAll('#contents a')].find(a=>new URL(a.href).pathname==='/' + \(literal(path)));
            if(!link || document.activeElement!==link || !link.getClientRects().length)return false;
            const navigation=document.getElementById('help-navigation'),r=link.getBoundingClientRect(),b=navigation.getBoundingClientRect();
            return r.top>=Math.max(0,b.top)-1 && r.bottom<=Math.min(innerHeight,b.bottom)+1;
        })()
        """
    }
    @MainActor static func rememberPage(_ web: WKWebView) async throws {
        _ = try await js(web,"(()=>{window.__contentsPage={url:location.href,history:history.length};window.__contentsToken='retained';return true})()")
    }
    @MainActor static func checkPageUnchanged(_ web: WKWebView,_ message: String) async throws {
        try check((try await js(web,"location.href===window.__contentsPage.url && history.length===window.__contentsPage.history && window.__contentsToken==='retained'")) as? Bool == true,message)
    }
    @MainActor static func webHasFocus(_ web: WKWebView) -> Bool { (web.window?.firstResponder as? NSView)?.isDescendant(of:web) == true }
    /// A real key press, delivered through the application's event queue as a person's would be.
    @MainActor static func press(_ window: NSWindow,_ characters: String,_ code: UInt16,_ modifiers: NSEvent.ModifierFlags = []) async throws {
        for type in [NSEvent.EventType.keyDown,.keyUp] {
            let event=NSEvent.keyEvent(with:type,location:.zero,modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
            NSApp.postEvent(event,atStart:false)
        }
        try await Task.sleep(nanoseconds:150_000_000)
    }
    @MainActor static var clickNumber = 1000
    enum MouseButton { case left, right, middle }
    /// A real click in the middle of a view. As the system's do, the press and its release share one event number.
    @MainActor static func click(_ view: NSView,_ button: MouseButton = .left) async throws {
        guard let window=view.window else { return }
        let location=view.convert(NSPoint(x:view.bounds.midX,y:view.bounds.midY),to:nil)
        clickNumber += 1
        let types: [NSEvent.EventType] = switch button {
        case .left: [.leftMouseDown,.leftMouseUp]
        case .right: [.rightMouseDown,.rightMouseUp]
        case .middle: [.otherMouseDown,.otherMouseUp]
        }
        for type in types {
            let pressed = [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type)
            var event=NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:clickNumber,clickCount:1,pressure:pressed ? 1 : 0)!
            // AppKit's constructor gives every mouse event button 0, so the middle button's number, 2, is set on its CGEvent.
            if button == .middle, let cg = event.cgEvent { cg.setIntegerValueField(.mouseEventButtonNumber,value:2); event = NSEvent(cgEvent:cg) ?? event }
            NSApp.postEvent(event,atStart:false)
        }
        try await Task.sleep(nanoseconds:300_000_000)
    }
    /// A left press on a view, dragged away and released there, so the view's button sends no action.
    @MainActor static func pressAway(_ view: NSView) async throws {
        guard let window=view.window else { return }
        let inside=view.convert(NSPoint(x:view.bounds.midX,y:view.bounds.midY),to:nil)
        let away=NSPoint(x:inside.x,y:inside.y - 120)
        clickNumber += 1
        for (type,location) in [(NSEvent.EventType.leftMouseDown,inside),(.leftMouseDragged,away),(.leftMouseUp,away)] {
            let event=NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:clickNumber,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!
            NSApp.postEvent(event,atStart:false)
        }
        try await Task.sleep(nanoseconds:300_000_000)
    }
    @MainActor static func keyboardNavigation(_ on: Bool) { HelpPane.keyboardNavigation = { on } }
    static let topicFailure = "Could not open the help topics. Use Home or search to find a topic."
    static let drawerFailure = "Could not close Contents to open the help index."
    // The page's next getElementById call, or the next class-list test, keeps it busy for the given time and then answers normally.
    static func busyPage(_ milliseconds: Int) -> String { "(()=>{const original=Document.prototype.getElementById;document.getElementById=function(id){delete document.getElementById;const end=Date.now()+\(milliseconds);while(Date.now()<end){}return original.call(this,id)};return true})()" }
    static func busyClassList(_ milliseconds: Int) -> String { "(()=>{const original=DOMTokenList.prototype.contains;DOMTokenList.prototype.contains=function(token){DOMTokenList.prototype.contains=original;const end=Date.now()+\(milliseconds);while(Date.now()<end){}return original.call(this,token)};return true})()" }
    @MainActor static func contents(_ h: HelpPane,_ focusedPath: String) async throws {
        let opened = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(opened,"Contents command completes in place")
        try await until(h.web,visibleFocus(focusedPath))
    }
    @MainActor static func checkContents(_ h: HelpPane) async throws {
        let web=h.web, paired="parametric_methods/paired_t.htm"
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        try await contents(h,paired)
        try await press(web.window!,"\t",48)
        try await until(web,"(()=>{const c=document.getElementById('contents'),links=[...c.querySelectorAll('a')],current=c.querySelector('a[aria-current=\"page\"]');return !!current&&document.activeElement===links[links.indexOf(current)+1]})()")
        try check(true,"Tab from the entry Contents focused moves to the next topic link, as in the Windows help window")
        try await contents(h,paired)
        try await rememberPage(web)
        _ = try await js(web,"(()=>{for(let p=document.querySelector('#contents a[aria-current=\"page\"]').parentElement;p&&p.id!=='contents';p=p.parentElement)if(p.tagName==='DETAILS')p.open=false;return true})()")
        try await contents(h,paired)
        try await checkPageUnchanged(web,"Contents expands collapsed ancestors and confirms visible focus without changing the live page or history")
        if CommandLine.arguments.contains("--check-reader-escape") {
            _ = try await js(web,"(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()")
            try await until(web,"document.activeElement===document.getElementById('topic') && !document.body.classList.contains('navigation-open')")
            try check(true,"Escape from docked Contents focuses the topic when the reader toggle is hidden")
        }
        h.open(HelpResources.origin.appendingPathComponent("graphics/markers.htm"))
        try await until(web,"location.pathname==='/graphics/markers.htm' && document.readyState==='complete'")
        try check((try await js(web,"!document.querySelector('#contents a[aria-current=\"page\"]')")) as? Bool == true,"the unlisted Markers topic has no current Contents link")
        try await rememberPage(web)
        try await contents(h,"graphics/graphics.htm")
        try await checkPageUnchanged(web,"An unlisted topic focuses its same-folder Overview without navigation")
        h.open(HelpResources.origin.appendingPathComponent("menus/analysis_options.htm"))
        try await until(web,"location.pathname==='/menus/analysis_options.htm' && document.readyState==='complete'")
        try await rememberPage(web)
        try await contents(h,"contents.htm")
        try await checkPageUnchanged(web,"A topic without a same-folder branch focuses the first Contents entry without navigation")

        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        try await contents(h,paired)
        try await rememberPage(web)
        _ = try await js(web,"(()=>{window.__contentsTarget=document.querySelector('#contents a[aria-current=\"page\"]');document.activeElement.blur();document.getElementById('topic').tabIndex=-1;document.getElementById('topic').focus();window.__contentsTarget.focus=()=>{};return true})()")
        h.view.window?.makeFirstResponder(h.searchField)
        let focused = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!focused && h.notice.stringValue == topicFailure && webHasFocus(web),"A failed Contents focus confirmation reports Windows's failure text, with keyboard focus in the page as Windows's Browser.Focus() leaves it")
        try await checkPageUnchanged(web,"Failed Contents focus does not replace the page or add history")
        _ = try await js(web,"(()=>{delete window.__contentsTarget.focus;return true})()")
        try await contents(h,paired)
        try check(h.notice.stringValue.isEmpty,"Successful Contents clears the earlier failure status")
        try await rememberPage(web)
        _ = try await js(web,"(()=>{window.__originalGetElementById=document.getElementById;document.getElementById=function(id){if(id==='contents')throw new Error('deliberate Contents failure');return window.__originalGetElementById.call(this,id)};return true})()")
        let failed = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!failed && h.notice.stringValue == topicFailure,"A Contents script error reports Windows's failure text, as its script call answers null for one")
        try await checkPageUnchanged(web,"A Contents script error preserves the live page and history")
        _ = try await js(web,"(()=>{document.getElementById=window.__originalGetElementById;return true})()")
        try await contents(h,paired)
        try await rememberPage(web)
        _ = try await js(web,"(()=>{document.querySelectorAll('#contents a').forEach(a=>a.remove());return true})()")
        let empty = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!empty && h.notice.stringValue == topicFailure,"An existing Contents tree with no links reports failure")
        try await checkPageUnchanged(web,"An empty Contents tree does not trigger a reader fallback")

        _ = try await js(web,"(()=>{document.getElementById('contents').remove();history.replaceState(null,'','/index.html');return true})()")
        try await nativeUntil { web.url?.path=="/index.html" }
        try await rememberPage(web)
        let missingAtHome = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!missingAtHome && h.notice.stringValue == topicFailure,"Missing Contents on index.html reports failure instead of entering a reload loop")
        try await checkPageUnchanged(web,"A missing tree on the reader preserves its URL and history")

        h.contents()
        try await until(web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        try await rememberPage(web)
        h.notice.stringValue = topicFailure
        h.contents();try await settle()
        try check(h.notice.stringValue.isEmpty,"Home on the page already shown clears the status line, as Windows's ShowTopic does")
        try await checkPageUnchanged(web,"Home on the page already shown keeps the page and its history")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        var readerAddresses:[String] = []
        let readerWatch = web.observe(\.url,options:[.new]) { view,_ in MainActor.assumeIsolated { if let address=view.url?.absoluteString, address.contains("index.html#topic=") { readerAddresses.append(address) } } }
        _ = try await js(web,"(()=>{document.getElementById('contents').remove();window.__missingContentsToken='removed';return true})()")
        _ = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete' && window.__missingContentsToken===undefined")
        readerWatch.invalidate()
        try check(readerAddresses == ["app://statsdirect-help/index.html#topic=parametric_methods%2Fpaired_t.htm"],"Only a missing Contents tree opens the reader at the current topic, at the address Windows's Uri.EscapeDataString gives: \(readerAddresses)")
        h.searchField.stringValue="paired t";h.search()
        try await until(web,"document.querySelector('#results')?.hidden===false && document.querySelectorAll('a.result').length>0")
        _ = try await js(web,"(()=>{document.getElementById('contents').hidden=false;return true})()")
        _ = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try await until(web,"document.getElementById('results').hidden && !document.getElementById('topic').hidden && !!document.activeElement.closest('#contents')")
        try check(true,"Contents restores the reader mode after search even when contents.hidden is false")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        try check(h.contentsButton.keyEquivalent.isEmpty && h.indexButton.keyEquivalent.isEmpty,"Contents and Index introduce no permanent shortcut")
        try await rememberPage(web)
        _ = try await js(web,busyPage(6500))
        let started=Date()
        let late = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        let waited=Date().timeIntervalSince(started)
        try check(!late && h.notice.stringValue == "Could not open the help topics: the help page did not respond." && waited > 4.9 && waited < 6.5,"A page that gives Contents no answer within five seconds is reported (\(String(format:"%.1f",waited)) s)")
        try await Task.sleep(nanoseconds:2_000_000_000)
        try check(h.notice.stringValue == "Could not open the help topics: the help page did not respond.","The Contents answer that arrives after the time limit changes nothing")
        try await checkPageUnchanged(web,"A Contents time-out preserves the page and history")
        let system = HelpPane.keyboardNavigation
        keyboardNavigation(true)
        try await checkToolbarTraversal(h)
        try await checkDisabledButtonClick(h)
        keyboardNavigation(false)
        try await checkToolbarWithoutKeyboardNavigation(h)
        HelpPane.keyboardNavigation = system
    }
    @MainActor static func checkToolbarWithoutKeyboardNavigation(_ h: HelpPane) async throws {
        guard let window=h.view.window, let home=paneButton(h,"Home") else {
            throw NSError(domain:"HelpPaneTests",code:6,userInfo:[NSLocalizedDescriptionKey:"The Help toolbar is not attached"])
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(h.web)
        try check(!home.acceptsFirstResponder && !home.canBecomeKeyView && !h.indexButton.acceptsFirstResponder && !h.indexButton.canBecomeKeyView,"With Keyboard navigation off neither a click nor Tab gives the help buttons keyboard focus, like other Mac buttons")
        try await click(home)
        try await until(h.web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        try check(webHasFocus(h.web),"A click on Home with Keyboard navigation off leaves keyboard focus in the page")
        h.open(h.url(for:"1239")!)
        try await until(h.web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
    }
    @MainActor static func checkDisabledButtonClick(_ h: HelpPane) async throws {
        guard let window=h.view.window else { return }
        h.open(HelpResources.origin.appendingPathComponent("graphics/markers.htm"))
        try await until(h.web,"location.pathname==='/graphics/markers.htm' && document.readyState==='complete'")
        try await nativeUntil { !h.forwardButton.isEnabled }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(h.web)
        try check(!h.forwardButton.acceptsFirstResponder,"A disabled help button refuses keyboard focus, even with Keyboard navigation on")
        try await click(h.forwardButton)
        try check(webHasFocus(h.web),"A click on the disabled Forward button leaves keyboard focus in the page, as AppKit's own buttons do")
        h.open(h.url(for:"1239")!)
        try await until(h.web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
    }
    @MainActor static func checkToolbarTraversal(_ h: HelpPane) async throws {
        guard let window=h.view.window, let home=paneButton(h,"Home") else {
            throw NSError(domain:"HelpPaneTests",code:6,userInfo:[NSLocalizedDescriptionKey:"The Help toolbar is not attached"])
        }
        window.makeKeyAndOrderFront(nil)
        try check(window.makeFirstResponder(home),"Home accepts native keyboard focus")
        func tab(_ reverse: Bool = false) {
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:reverse ? .shift : [],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:reverse ? "\u{19}" : "\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
            NSApp.postEvent(event,atStart:false)
        }
        tab()
        try await nativeUntil { window.firstResponder === h.contentsButton }
        tab()
        try await nativeUntil { window.firstResponder === h.indexButton }
        tab()
        try await nativeUntil { window.firstResponder === h.searchField || (h.searchField.currentEditor() != nil && window.firstResponder === h.searchField.currentEditor()) }
        try check(true,"Tab traverses Home, Contents, Index and search in visual order")
        tab(true)
        try await nativeUntil { window.firstResponder === h.indexButton }
        tab(true)
        try await nativeUntil { window.firstResponder === h.contentsButton }
        tab(true)
        try await nativeUntil { window.firstResponder === home }
        try check(true,"Shift+Tab traverses search, Index, Contents and Home in reverse order")
    }

    @MainActor static func key(_ h: HelpPane,_ characters: String,_ code: UInt16,_ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:h.indexPicker.panel.windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
    }
    @MainActor static func filter(_ h: HelpPane,_ text: String) {
        h.indexPicker.filter.stringValue=text
        h.indexPicker.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:h.indexPicker.filter))
    }
    @MainActor static func rowText(_ h: HelpPane,_ row: Int) -> String {
        let view=h.indexPicker.table.view(atColumn:0,row:row,makeIfNecessary:true)
        if let text=view as? NSTextField { return text.stringValue }
        return (view as? NSTableCellView)?.textField?.stringValue ?? ""
    }
    @MainActor static func pickerFocused(_ h: HelpPane,_ filter: Bool) -> Bool {
        if filter { return h.indexPicker.panel.firstResponder === h.indexPicker.filter || (h.indexPicker.filter.currentEditor() != nil && h.indexPicker.panel.firstResponder === h.indexPicker.filter.currentEditor()) }
        return h.indexPicker.panel.firstResponder === h.indexPicker.table
    }
    @MainActor static func clickRow(_ h: HelpPane,_ row: Int,_ right: Bool = false) {
        let table=h.indexPicker.table
        let location: NSPoint
        if row >= 0 { location=table.convert(NSPoint(x:8,y:table.rect(ofRow:row).midY),to:nil) }
        else {
            let viewport=table.enclosingScrollView!.contentView
            location=viewport.convert(NSPoint(x:8,y:viewport.bounds.maxY-8),to:nil)
        }
        let down=NSEvent.mouseEvent(with:right ? .rightMouseDown : .leftMouseDown,location:location,modifierFlags:[],timestamp:0,windowNumber:h.indexPicker.panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let up=NSEvent.mouseEvent(with:right ? .rightMouseUp : .leftMouseUp,location:location,modifierFlags:[],timestamp:0,windowNumber:h.indexPicker.panel.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
        NSApp.postEvent(down,atStart:false)
        NSApp.postEvent(up,atStart:false)
    }
    @MainActor static func index(_ h: HelpPane) async throws -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showIndex { done.resume(returning:$0) } }
    }
    @MainActor static func checkIndex(_ h: HelpPane) async throws {
        let web=h.web
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
        try await rememberPage(web)
        if !FileManager.default.fileExists(atPath:h.resources.root.appendingPathComponent("keyword-index.json").path) {
            let opened=try await index(h)
            try check(!opened && !h.indexPicker.isVisible && h.notice.stringValue.localizedCaseInsensitiveContains("does not yet include a keyword index"),"The legacy bundle shows an Index availability notice without opening an empty picker")
            try await checkPageUnchanged(web,"Index availability on a legacy bundle preserves the topic and history")
            return
        }
        try await contents(h,"parametric_methods/paired_t.htm")
        try await rememberPage(web)
        try check((try await js(web,"document.body.classList.contains('navigation-open')")) as? Bool == true,"Contents opens the compact reader drawer before Index")
        try check(try await index(h),"Index opens after closing the reader drawer")
        try await nativeUntil { h.indexPicker.isVisible && pickerFocused(h,true) }
        try check((try await js(web,"!document.body.classList.contains('navigation-open')")) as? Bool == true,"The Index picker and temporary Contents drawer are mutually exclusive")
        try await checkPageUnchanged(web,"Switching from Contents to Index retains the live topic, URL and history")
        let expectedRows = ((try? HelpKeywordIndex.load(root:h.resources.root)) ?? nil)?.rows.count ?? -1
        try check(expectedRows > 0 && h.indexPicker.table.numberOfRows == expectedRows,"Index lists every authored term-target record of the bundle's map (\(expectedRows))")
        if let screen=h.indexPicker.panel.screen { try check(screen.visibleFrame.contains(h.indexPicker.panel.frame),"The native Index picker fits its monitor") }
        try await contents(h,"parametric_methods/paired_t.htm")
        try check(!h.indexPicker.isVisible,"Opening Contents closes Index first")
        h.showIndex()
        try await contents(h,"parametric_methods/paired_t.htm")
        try await settle()
        try check(!h.indexPicker.isVisible,"A later Contents command cancels a delayed Index open")
        h.showIndex()
        NotificationCenter.default.post(name:NSApplication.didResignActiveNotification,object:NSApp)
        try await settle()
        try check(!h.indexPicker.isVisible,"Application deactivation cancels a delayed Index open")

        try await rememberPage(web)
        h.indexButton.performClick(nil)
        h.hide()
        try await settle()
        try check(!h.indexPicker.isVisible,"Hiding Help cancels a pending Index open")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
        try await checkPageUnchanged(web,"Hide and reopen after a pending Index request retains the same live topic and history")
        h.indexButton.performClick(nil)
        h.toggleMode();try await settle()
        try check(!h.indexPicker.isVisible,"Reparenting Help cancels a pending Index open")
        h.toggleMode();try await settle()
        try await checkPageUnchanged(web,"Reparenting after a pending Index request retains the same live topic and history")
        h.indexButton.performClick(nil)
        h.open(HelpResources.origin.appendingPathComponent("graphics/markers.htm"))
        try await until(web,"location.pathname==='/graphics/markers.htm' && document.readyState==='complete'")
        try await settle()
        try check(!h.indexPicker.isVisible,"Navigation to another topic cancels a pending Index open")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")

        try await checkIndexFailures(h)
        try check(try await index(h),"Index reopens after cancellation")
        filter(h,"Cohen's kappa")
        try check(h.indexPicker.table.numberOfRows>0 && (0..<h.indexPicker.table.numberOfRows).allSatisfy { rowText(h,$0).localizedCaseInsensitiveContains("Cohen") },"Typing filters authored keywords and target titles")
        try await rememberPage(web)
        let panel = h.indexPicker.panel
        try await press(panel,"\u{f701}",125)
        try await nativeUntil { pickerFocused(h,false) }
        try await checkPageUnchanged(web,"Moving through Index rows does not navigate")
        try await press(panel,"\t",48)
        try await nativeUntil { pickerFocused(h,true) }
        try await press(panel,"\u{19}",48,.shift)
        try await nativeUntil { pickerFocused(h,false) }
        try check(true,"Tab and Shift+Tab reach both the Index filter and results")
        try await press(panel,"\r",36)
        try await until(web,"location.pathname==='/agreement/kappa.htm' && document.readyState==='complete'")
        try check(!h.indexPicker.isVisible,"Enter opens the chosen Index topic in the same Help browser")
        try check(try await index(h),"Index reopens for another query")
        try check(h.indexPicker.filter.stringValue=="Cohen's kappa","Reopening Index retains the filter")
        try await rememberPage(web)
        clickRow(h,0,true)
        try await settle()
        try await checkPageUnchanged(web,"Right-clicking an Index row does not navigate")
        let selectedBefore = h.indexPicker.table.selectedRow, titleBefore = h.indexPicker.selectedTopicText
        clickRow(h,-1)
        try await settle()
        try await checkPageUnchanged(web,"Clicking blank Index list space does not open its prior selection")
        try check(selectedBefore >= 0 && h.indexPicker.table.selectedRow == selectedBefore && h.indexPicker.selectedTopicText == titleBefore && !titleBefore.isEmpty,"Clicking blank Index list space keeps the selected entry and its title")
        filter(h,"Gaussian distribution")
        try check(h.indexPicker.table.numberOfRows==1,"Gaussian distribution has one authored Index target")
        clickRow(h,0)
        try await until(web,"location.pathname==='/distributions/normal.htm' && document.readyState==='complete'")
        try check(!h.indexPicker.isVisible,"A valid left-click opens the selected Index topic")
        try check(try await index(h),"Index reopens for no-match correction")
        filter(h,"__no_such_keyword__")
        try check(h.indexPicker.table.numberOfRows==0,"A no-match filter leaves no selectable target")
        try await rememberPage(web)
        try await press(panel,"\r",36)
        try check(h.indexPicker.isVisible,"Enter with no Index match leaves the picker open")
        try await checkPageUnchanged(web,"Enter with no Index match preserves the page and history")
        let system = HelpPane.keyboardNavigation
        keyboardNavigation(false)
        h.view.window?.makeFirstResponder(h.searchField)
        try check(!webHasFocus(web),"Help's search field holds the help window's focus behind the open Index picker")
        try await press(panel,"\u{1b}",53)
        try await nativeUntil { !h.indexPicker.isVisible }
        try check(webHasFocus(web),"With Keyboard navigation off, Escape closes Index and moves focus to the page, wherever it was before")
        keyboardNavigation(true)
        try check(try await index(h),"Index reopens with Keyboard navigation on")
        try await press(panel,"\u{1b}",53)
        try await nativeUntil { !h.indexPicker.isVisible }
        try check(h.view.window?.firstResponder === h.indexButton,"With Keyboard navigation on, Escape closes Index and restores its toolbar focus")
        HelpPane.keyboardNavigation = system
        try check(!h.indexPicker.handleKey(key(h,"\r",36)),"A hidden Index picker does not handle reader or toolbar Enter keys")

        try check(try await index(h),"Index reopens for accent-insensitive matching")
        filter(h,"Scheffe")
        try check(h.indexPicker.table.numberOfRows>0 && (0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0).contains("Scheff") },"English Index matching finds accented keywords without typed accents")
        filter(h,"AI assistance")
        try check(h.indexPicker.table.numberOfRows==2 && Set((0..<2).map { rowText(h,$0) }).count==2,"A keyword with multiple targets retains distinguishable target titles")
        filter(h,"ipynb")
        try check((0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0).contains("Jupyter notebook files (.ipynb)") },"The clarified Jupyter notebook keyword reaches the native Index")
        filter(h,"metafor")
        try check((0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0).contains("R package: metafor") },"The clarified metafor package keyword reaches the native Index")
        filter(h,"Shannon")
        try check((0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0).contains("Shannon-Wiener") }
                  && (0..<h.indexPicker.table.numberOfRows).allSatisfy { !rowText(h,$0).contains("Weiner") },"The corrected Shannon-Wiener keyword reaches the native Index without the old spelling")
        filter(h,"ANOVA")
        try check(h.indexPicker.table.numberOfRows>1 && (0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0) == "ANOVA: One way" },"Index retains authored ANOVA subentries with their colon text")
        h.indexPicker.panel.makeFirstResponder(h.indexPicker.filter)
        try await rememberPage(web)
        for (characters,code) in [("\u{f701}",UInt16(125)),("\u{f701}",125),("\u{f701}",125),("\u{f700}",126)] { try await press(panel,characters,code) }
        try check(pickerFocused(h,false) && h.indexPicker.table.selectedRow == 1,"Down moves from the filter into the list, then the arrow keys move the selection a row at a time: \(h.indexPicker.table.selectedRow)")
        try await checkPageUnchanged(web,"Moving the Index selection with the arrow keys does not navigate")
        filter(h,"I2")
        try check((0..<h.indexPicker.table.numberOfRows).contains { rowText(h,$0).hasPrefix("I²") },"Typing I2 finds I², as Windows's ICU match does")
        filter(h,"Cohen\u{2019}s kappa")
        try check(h.indexPicker.table.numberOfRows == 1 && rowText(h,0) == "Cohen's kappa","A typographic apostrophe finds the straight one, as on Windows")
        filter(h,"æ"); let ligature = h.indexPicker.table.numberOfRows
        filter(h,"ae")
        try check(ligature > 0 && ligature == h.indexPicker.table.numberOfRows,"æ and ae find the same entries, as on Windows")
        filter(h,"t-test")
        try check(h.indexPicker.table.numberOfRows == 0 && h.indexPicker.countText == "No matching index entries","Hyphens are not folded away, as on Windows")
        filter(h,"ANOVA")
        h.indexPicker.close()
        try check(try await index(h),"The same Index picker can be opened repeatedly")
        try check(h.indexPicker.filter.stringValue=="ANOVA","Repeated Index use keeps its last query")
        func ground(_ name: NSAppearance.Name) -> CGColor? { var color: CGColor?; NSAppearance(named:name)!.performAsCurrentDrawingAppearance { color = NSColor.windowBackgroundColor.cgColor }; return color }
        h.indexPicker.panel.appearance = NSAppearance(named:.darkAqua); h.indexPicker.panel.contentView?.needsDisplay = true; h.indexPicker.panel.displayIfNeeded(); try await settle()
        let dark = h.indexPicker.backgroundColor
        h.indexPicker.panel.appearance = NSAppearance(named:.aqua); h.indexPicker.panel.contentView?.needsDisplay = true; h.indexPicker.panel.displayIfNeeded(); try await settle()
        let light = h.indexPicker.backgroundColor
        h.indexPicker.panel.appearance = nil
        try check(dark != nil && light != nil && dark == ground(.darkAqua) && light == ground(.aqua) && dark != light,"The Index picker's ground follows Light and Dark")
        h.indexPicker.panel.makeFirstResponder(h.indexPicker.filter)
        let editor = h.indexPicker.filter.currentEditor() as? NSTextView
        editor?.setMarkedText("k",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        try await rememberPage(web)
        try await press(panel,"\r",36)
        try check(editor != nil && h.indexPicker.isVisible,"Return while an input method composes in the filter stays with the input method and opens nothing")
        try await checkPageUnchanged(web,"Return during an input method's composition preserves the page and history")
        editor?.unmarkText()
        try await click(h.indexButton)
        try await settle()
        try check(!h.indexPicker.isVisible,"A click on Index while the picker shows closes it, as a Windows drop-down button does")
        try await click(h.indexButton)
        try await nativeUntil { h.indexPicker.isVisible && pickerFocused(h,true) }
        try check(true,"The next click on Index opens the picker again")
        try await click(h.indexButton,.right)
        try await settle()
        try check(h.indexPicker.isVisible && pickerFocused(h,true),"A right-click on Index leaves the picker open, as Windows's drop-down button acts on the left button only")
        try await click(h.indexButton,.middle)
        try await settle()
        try check(h.indexPicker.isVisible && pickerFocused(h,true),"A middle click on Index leaves the picker open too")
        try await pressAway(h.indexButton)
        try await settle()
        try check(!h.indexPicker.isVisible,"A press on Index closes the picker even when released away from the button")
        try await click(h.indexButton)
        try await nativeUntil { h.indexPicker.isVisible }
        try check(true,"After a press on Index released away from it, the next click opens the picker at once")
        try await click(h.contentsButton)
        try await until(web,visibleFocus("distributions/normal.htm"))
        try check(!h.indexPicker.isVisible,"A click on Contents while the picker shows closes Index and opens Contents at once")
        try check(try await index(h),"Index reopens after Contents")
        h.toggleMode();try await settle()
        try check(!h.indexPicker.isVisible,"Reparenting Help closes its Index picker")
        h.toggleMode();try await settle()
        try check(try await index(h),"Index remains usable after reparenting")
        let responder=h.owner?.firstResponder
        NotificationCenter.default.post(name:NSApplication.didResignActiveNotification,object:NSApp)
        try await settle()
        try check(!h.indexPicker.isVisible && h.owner?.firstResponder === responder,"Closing Index on application deactivation does not force toolbar focus")
        try check(try await index(h),"Index remains usable after deactivation")
        h.hide();try await settle()
        try check(!h.indexPicker.isVisible,"Hiding Help closes its Index picker")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
        try await nativeUntil { h.contentsButton.isEnabled }
        try await rememberPage(web)
        let window=h.view.window!
        let systemNavigation = HelpPane.keyboardNavigation
        keyboardNavigation(true)
        try check(window.makeFirstResponder(h.contentsButton),"Contents accepts keyboard focus after Index has closed")
        try await press(window,"\r",36)
        try await until(web,visibleFocus("parametric_methods/paired_t.htm"))
        HelpPane.keyboardNavigation = systemNavigation
        try check(!h.indexPicker.isVisible,"A previously used hidden Index does not intercept native Enter on Contents")
        try await checkPageUnchanged(web,"Native Contents Enter after Index use preserves the same topic, URL and history")
    }
    @MainActor static func checkIndexFailures(_ h: HelpPane) async throws {
        let web=h.web, paired="parametric_methods/paired_t.htm"
        try await contents(h,paired)
        _ = try await js(web,"(()=>{document.getElementById('navigation-toggle').remove();return true})()")
        try await rememberPage(web)
        try check(!(try await index(h)) && !h.indexPicker.isVisible && h.notice.stringValue == drawerFailure,"A Contents drawer that cannot close cancels Index with Windows's message")
        try await checkPageUnchanged(web,"A drawer that cannot close leaves the page and history alone")
        h.open(HelpResources.origin.appendingPathComponent("graphics/markers.htm"))
        try await until(web,"location.pathname==='/graphics/markers.htm' && document.readyState==='complete'")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        _ = try await js(web,"(()=>{window.__classContains=DOMTokenList.prototype.contains;DOMTokenList.prototype.contains=function(){throw new Error('deliberate drawer failure')};return true})()")
        let thrown = try await index(h)
        _ = try await js(web,"(()=>{DOMTokenList.prototype.contains=window.__classContains;return true})()")
        try check(!thrown && !h.indexPicker.isVisible && h.notice.stringValue == drawerFailure,"A drawer script error reads as a drawer that did not close, as Windows's null answer does")
        h.notice.stringValue = "Help could not load: probe"
        try check(try await index(h),"Index opens with an earlier message on the status line")
        try check(h.notice.stringValue == "Help could not load: probe","Opening Index leaves the status line as it was, as on Windows")
        h.indexPicker.close()
        h.notice.stringValue = ""
        try await rememberPage(web)
        _ = try await js(web,busyClassList(6500))
        let started=Date()
        let late = try await index(h)
        let waited=Date().timeIntervalSince(started)
        try check(!late && !h.indexPicker.isVisible && h.notice.stringValue == "Could not open the help index: the help page did not respond." && waited > 4.9 && waited < 6.5,"A page that gives Index no answer within five seconds is reported (\(String(format:"%.1f",waited)) s)")
        try await Task.sleep(nanoseconds:2_000_000_000)
        try check(!h.indexPicker.isVisible,"The drawer answer that arrives after the time limit opens no picker")
        try await checkPageUnchanged(web,"An Index time-out preserves the page and history")
        h.notice.stringValue = ""
    }
    #if !HELP_NAVIGATION_ONLY
    /// Edit and Close shortcuts typed in the picker act on it, never on the worksheet behind it.
    @MainActor static func checkIndexRouting(_ h: HelpPane,_ v: Viewer,_ suiteWorksheet: Document) async throws {
        guard HelpKeywordIndex.exists(root:h.resources.root) else { return }
        // A worksheet of its own takes the edits: an edit and its undo still mark a sheet's formulas stale, which the
        // suite's worksheet must not show when it is compared with its starting state.
        let worksheet = v.newDocument(kind:"grid",title:"Index routing",url:v.root.appendingPathComponent("Grid/index.html"))
        defer { v.remove(worksheet); v.tabs.selectTabViewItem(suiteWorksheet.item) }
        try await until(worksheet.web,"!!window.statsDirectGrid")
        _ = try await js(worksheet.web,"statsDirectGrid.loadCSV('Before,After\\n1,2\\n3,4','Index routing.csv')")
        try await settle()
        try check(v.active === worksheet,"A worksheet is the active document beside help")
        // The clipboard the person had is put back afterwards, as the other suites do.
        let general = NSPasteboard.general
        let saved = (general.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType:type) { copy.setData(data,forType:type) } }
            return copy
        }
        defer { general.clearContents(); if !saved.isEmpty { general.writeObjects(saved) } }
        // An undoable edit and no selection, so that Undo or Select All reaching the worksheet would show.
        _ = try await js(worksheet.web,"(()=>{statsDirectGrid.setCellText({col:0,row:1,text:'4242'});statsDirectGrid.clearSelection();return true})()")
        try await settle()
        let state = "JSON.stringify({cells:statsDirectGrid.csvData(),source:statsDirectGrid.analysisSource()})"
        let before = try await js(worksheet.web,state) as? String
        try check(before?.contains("4242") == true,"The worksheet holds an undoable edit before Index opens")
        general.clearContents(); general.setString("Gaussian",forType:.string)
        try check(try await index(h),"Index opens beside the active worksheet")
        let panel = h.indexPicker.panel
        try check(h.isFocused,"The open Index picker counts as focused help")
        let query = h.indexPicker.filter.stringValue
        try await press(panel,"v",9,.command)
        try await nativeUntil { h.indexPicker.filter.stringValue == "Gaussian" }
        try await press(panel,"a",0,.command)
        let editor = h.indexPicker.filter.currentEditor() as? NSTextView
        try check(editor?.selectedRange() == NSRange(location:0,length:8),"Select All in the Index filter selects the filter's text")
        try await press(panel,"z",6,.command)
        try await nativeUntil { h.indexPicker.filter.stringValue == query }
        try check(true,"Undo in the Index filter takes back the paste")
        try check((try await js(worksheet.web,state)) as? String == before,"Paste, Select All and Undo typed in the Index filter edit the filter, not the worksheet behind it")
        // In the list nothing takes Cut, Copy or Paste, as in Windows's list box; none may reach the worksheet or the clipboard.
        filter(h,"Gaussian")
        try await press(panel,"\u{f701}",125)
        try await nativeUntil { pickerFocused(h,false) }
        general.clearContents(); general.setString("1\t2\n3\t4",forType:.string)
        for (characters,code) in [("v",UInt16(9)),("x",7),("c",8),("a",0),("z",6)] { try await press(panel,characters,code,.command) }
        try check(h.indexPicker.isVisible && pickerFocused(h,false),"Edit shortcuts in the Index list leave the picker open with the list focused")
        try check((try await js(worksheet.web,state)) as? String == before,"Cut, Copy, Paste, Select All and Undo in the Index list leave the worksheet behind it unchanged")
        try check(general.string(forType:.string) == "1\t2\n3\t4","Copy and Cut in the Index list leave the clipboard as it was")
        let documents = v.documents.count
        try await press(panel,"w",13,.command)
        try await nativeUntil { !h.indexPicker.isVisible }
        try check(h.visible && v.documents.count == documents && v.active === worksheet,"Close with the Index picker focused closes the picker, not the document or help")
    }
    /// Close in the Index picker over popped-out help closes the picker, not an AI pane whose composer keeps the main
    /// window's focus behind it.
    @MainActor static func checkIndexCloseBesideAI(_ h: HelpPane,_ v: Viewer,_ worksheet: Document) async throws {
        guard HelpKeywordIndex.exists(root:h.resources.root) else { return }
        let policy = UserDefaults.standard.object(forKey:"DisableOnlineTutor")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        let script = v.newDocument(kind:"r",title:"Help close fixture")
        let pane = RPane(script:"1 + 1"); script.rPane = pane; script.item.view = pane.view
        defer {
            v.scriptAI.hide()
            v.remove(script)
            v.tabs.selectTabViewItem(worksheet.item)
            if let policy { UserDefaults.standard.set(policy,forKey:"DisableOnlineTutor") } else { UserDefaults.standard.removeObject(forKey:"DisableOnlineTutor") }
        }
        if !h.prefersFloating { h.toggleMode(); try await settle() }
        defer { if h.prefersFloating { h.toggleMode() } }
        v.scriptAI.open(script)
        try await settle()
        try check(v.scriptAI.visible && v.scriptAI.isFocused && h.view.window === h.floatingWindow,"The AI pane's composer has the main window's focus beside popped-out help")
        try check(try await index(h),"Index opens in popped-out help beside the AI pane")
        try await press(h.indexPicker.panel,"w",13,.command)
        try await nativeUntil { !h.indexPicker.isVisible }
        try check(v.scriptAI.visible && h.visible,"Close with the Index picker focused closes only the picker, leaving the AI pane and help open")
    }
    #endif
    @MainActor static func checkWideContents(_ h: HelpPane) async throws {
        h.toggleMode();try await settle()
        guard let panel=h.floatingWindow else { throw NSError(domain:"HelpPaneTests",code:5,userInfo:[NSLocalizedDescriptionKey:"Help did not pop out for its wide-reader check"]) }
        panel.setContentSize(NSSize(width:1450,height:750))
        try await until(h.web,"innerWidth>=1280")
        h.open(HelpResources.origin.appendingPathComponent("references/support.htm"))
        try await until(h.web,"location.pathname==='/references/support.htm' && document.readyState==='complete'")
        _ = try await js(h.web,"(()=>{document.querySelectorAll('#contents details').forEach(d=>d.open=true);document.getElementById('help-navigation').scrollTop=0;return true})()")
        try await rememberPage(h.web)
        try await contents(h,"references/support.htm")
        try await checkPageUnchanged(h.web,"Wide Contents scrolls and focuses its current entry without replacing the topic")
        if HelpKeywordIndex.exists(root:h.resources.root) {
            try check(try await index(h),"Index opens beside the wide reader")
            try check((try await js(h.web,"!document.body.classList.contains('navigation-open') && document.getElementById('help-navigation').getClientRects().length>0")) as? Bool == true,"Index preserves the wide reader's permanent sidebar")
            try await contents(h,"references/support.htm")
            try check(!h.indexPicker.isVisible,"Wide Contents closes Index")
            try await checkPageUnchanged(h.web,"Wide Contents and Index switching retains the topic and history")
        }
        if CommandLine.arguments.contains("--check-reader-escape") {
            _ = try await js(h.web,"(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()")
            try await until(h.web,"document.activeElement===document.getElementById('topic') && !document.body.classList.contains('navigation-open')")
            try check(true,"Escape from the wide Contents tree returns focus to the topic")
        }
        h.toggleMode();try await settle()
    }
    @MainActor static func checkInvalidIndex(_ original: HelpPane) async throws {
        let fixtures: [(String,String)] = [
            ("malformed JSON", "{"),
            ("unsupported schema", #"{"schemaVersion":2,"entries":[{"term":"Valid","title":"Valid target","path":"index.html"}]}"#),
            ("unsafe parent target", #"{"schemaVersion":1,"entries":[{"term":"Unsafe","title":"Unsafe target","path":"../outside.htm"}]}"#),
            ("missing target", #"{"schemaVersion":1,"entries":[{"term":"Missing","title":"Missing target","path":"missing.htm"}]}"#),
            ("malformed entry", #"{"schemaVersion":1,"entries":[{"term":"Missing title","path":"index.html"}]}"#)
        ]
        for (name,source) in fixtures {
            let folder=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("help-invalid-index-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:folder) }
            try Data("<!doctype html><html><head><title>Invalid keyword fixture</title></head><body><p id='topic'>A retained help page.</p></body></html>".utf8).write(to:folder.appendingPathComponent("index.html"))
            try Data("<!doctype html><html><head><title>Repaired target</title></head><body><p>A keyword target.</p></body></html>".utf8).write(to:folder.appendingPathComponent("topic.htm"))
            try Data(source.utf8).write(to:folder.appendingPathComponent("keyword-index.json"))
            let pane=HelpPane(root:folder)
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            let split=NSSplitView(frame:NSRect(x:0,y:0,width:900,height:500));split.isVertical=true
            split.addArrangedSubview(NSView())
            window.contentView=split
            pane.attach(to:split,owner:window)
            window.makeKeyAndOrderFront(nil)
            defer { pane.shutdown();window.orderOut(nil);original.view.window?.makeKeyAndOrderFront(nil) }
            pane.open()
            try await until(pane.web,"document.readyState==='complete' && document.getElementById('topic')!==null")
            try await nativeUntil { pane.indexButton.isEnabled }
            // A compact reader's open Contents drawer, which Index closes before it reads the map.
            _ = try await js(pane.web,"(()=>{document.body.classList.add('navigation-open');const toggle=document.createElement('button');toggle.id='navigation-toggle';toggle.addEventListener('click',()=>document.body.classList.remove('navigation-open'));document.body.append(toggle);return true})()")
            try await rememberPage(pane.web)
            pane.indexButton.performClick(nil)
            try await nativeUntil { pane.notice.stringValue.hasPrefix("Could not open the help index") }
            try check(!pane.indexPicker.isVisible && pane.notice.window?.isVisible == true,"Index toolbar reports \(name) visibly without opening a picker")
            try check((try await js(pane.web,"!document.body.classList.contains('navigation-open')")) as? Bool == true,"Index reads the map with \(name) only after closing the Contents drawer, as on Windows")
            try await checkPageUnchanged(pane.web,"Index toolbar rejects \(name) without replacing the page or history")
            if name == "missing target" {
                // Windows keeps no failed load, so the next Index reads a repaired map.
                try Data(#"{"schemaVersion":1,"entries":[{"term":"Repaired","title":"Repaired target","path":"topic.htm"}]}"#.utf8).write(to:folder.appendingPathComponent("keyword-index.json"))
                pane.indexButton.performClick(nil)
                try await nativeUntil { pane.indexPicker.isVisible }
                try check(pane.indexPicker.rows.map(\.entry.term) == ["Repaired"],"Index reads a repaired map on the next request after a failed one")
                pane.indexPicker.close()
            }
            pane.hide()
        }
    }
    static let topicUnavailable = "This topic is unavailable; showing the help contents."
    /// HelpView.ShowTopic and HelpCatalog.Resolve at Windows d783a494, on the bundled help.
    @MainActor static func checkTopics(_ h: HelpPane) async throws {
        let web=h.web, paired="parametric_methods/paired_t.htm"
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        try check(h.url(for:"sms")?.path == "/methods/method_selection.htm" && h.url(for:"Calc")?.path == "/basics/calculator.htm" && h.url(for:"ptt")?.path == "/"+paired,"Help names resolve in any case, as Windows's catalogue compares names and IDs ordinally, ignoring case")
        h.notice.stringValue="probe"
        h.showTopic("Sms")
        try await until(web,"location.pathname==='/methods/method_selection.htm' && document.readyState==='complete'")
        try check(h.notice.stringValue.isEmpty,"A mapped help name in another case opens its topic and clears the status line")
        h.showTopic("9999")
        try await until(web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        try await settle()
        try check(h.notice.stringValue == topicUnavailable,"An unmapped help ID shows the help contents with Windows's status line, which stays once the page has loaded")
        try await rememberPage(web)
        h.notice.stringValue=""
        h.showTopic("NO_SUCH_TOPIC");try await settle()
        try check(h.notice.stringValue == topicUnavailable,"An unmapped help name with the contents already shown gives the status line")
        try await checkPageUnchanged(web,"An unmapped help name with the contents already shown keeps the page and its history")
        h.showTopic("https://www.statsdirect.com/help/basics/calculator.htm")
        try await until(web,"location.pathname==='/basics/calculator.htm' && document.readyState==='complete'")
        try check(web.url?.scheme == "app" && h.notice.stringValue.isEmpty,"A statsdirect.com/help address opens the packaged topic offline and clears the status line")
        var external:[URL]=[]
        let browser=h.externalLink
        h.externalLink={external.append($0)}
        defer { h.externalLink=browser }
        try await rememberPage(web)
        h.notice.stringValue="probe"
        for address in ["https://www.r-project.org/","https://www.statsdirect.com/"] { h.showTopic(address) }
        try await settle()
        try check(external.map(\.absoluteString) == ["https://www.r-project.org/","https://www.statsdirect.com/"] && h.notice.stringValue == "probe","An address outside the help, the StatsDirect home page included, opens in the browser and leaves the status line, as Windows's ShowTopic returns first")
        try await checkPageUnchanged(web,"An address outside the help leaves the help page and its history")
        h.notice.stringValue=""
    }
    /// A help folder of its own, docked in a window of its own. Its Alias.xml maps a statsdirect.com/help address, another
    /// site's address and one name twice in different cases, and has no Method Selection (1213) or Calculator (1020) topic.
    @MainActor static func topicFixture() throws -> (folder: URL, pane: HelpPane, window: NSWindow) {
        let folder=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("help-topics-"+UUID().uuidString)
        for directory in ["basics","Data"] { try FileManager.default.createDirectory(at:folder.appendingPathComponent(directory),withIntermediateDirectories:true) }
        for (page,body) in [("index.html","The reader"),("contents.htm","Help contents"),("basics/calculator.htm","<p id='keys'>Calculator keys</p>"),("first.htm","First mapping"),("second.htm","Second mapping")] {
            try Data("<!doctype html><html><head><title>\(page)</title></head><body>\(body)</body></html>".utf8).write(to:folder.appendingPathComponent(page))
        }
        try Data("""
            <CatapultAliasFile Version="1">
              <Map Name="CONTENTS" Link="contents.htm" ResolvedId="1000" />
              <Map Name="WEB_CALC" Link="https://www.statsdirect.com/help/basics/calculator.htm#keys" ResolvedId="5001" />
              <Map Name="R_PROJECT" Link="https://www.r-project.org/" ResolvedId="5002" />
              <Map Name="Twice" Link="first.htm" ResolvedId="5003" />
              <Map Name="TWICE" Link="second.htm" ResolvedId="5004" />
            </CatapultAliasFile>
            """.utf8).write(to:folder.appendingPathComponent("Data/Alias.xml"))
        let pane=HelpPane(root:folder)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        let split=NSSplitView(frame:NSRect(x:0,y:0,width:900,height:500));split.isVertical=true
        split.addArrangedSubview(NSView())
        window.contentView=split
        pane.attach(to:split,owner:window)
        window.makeKeyAndOrderFront(nil)
        return (folder,pane,window)
    }
    /// HelpCatalog.Resolve on the aliases of the fixture's own Alias.xml.
    @MainActor static func checkTopicAliases(_ original: HelpPane) async throws {
        let (folder,pane,window)=try topicFixture()
        defer { pane.shutdown();window.orderOut(nil);try? FileManager.default.removeItem(at:folder);original.view.window?.makeKeyAndOrderFront(nil) }
        var external:[URL]=[];pane.externalLink={external.append($0)}
        pane.showTopic("1000")
        try await until(pane.web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        pane.notice.stringValue="probe"
        pane.showTopic("web_calc")
        try await until(pane.web,"location.pathname==='/basics/calculator.htm' && location.hash==='#keys' && document.getElementById('keys')!==null")
        try check(pane.web.url?.scheme == "app" && pane.notice.stringValue.isEmpty && external.isEmpty,"An alias whose Link is a statsdirect.com/help address, named in another case, opens the packaged page at its anchor, as Windows's Resolve maps it")
        pane.showTopic("R_PROJECT")
        try await until(pane.web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        try await settle()
        try check(pane.notice.stringValue == topicUnavailable && external.isEmpty,"An alias whose Link is another site's address shows the help contents and Windows's status line without opening the browser, as ShowTopic tests only the topic as given")
        pane.showTopic("twice")
        try await until(pane.web,"location.pathname==='/second.htm' && document.readyState==='complete'")
        try check(pane.notice.stringValue.isEmpty,"Of two mappings of a name in different cases, the later wins, as in Windows's catalogue")
        try FileManager.default.removeItem(at:folder.appendingPathComponent("contents.htm"))
        pane.contents()
        try await until(pane.web,"location.pathname==='/index.html' && document.readyState==='complete'")
        try await settle()
        try check(pane.notice.stringValue == topicUnavailable,"Home without its topic (1000) shows the reader with Windows's status line, as ShowTopic(\"1000\") falls back to index.html")
        pane.hide()
    }
    #if HELP_NAVIGATION_ONLY
    @MainActor static var navigationWindow: NSWindow?
    @MainActor static var navigationSplit: NSSplitView?
    @MainActor static var navigationPane: HelpPane?
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--run-tests") else { print("Use Scripts/test-help-pane.sh --navigation-only"); exit(2) }
        let app=NSApplication.shared
        app.setActivationPolicy(.regular)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Help navigation verification"
        window.isReleasedWhenClosed=false
        let split=NSSplitView(frame:window.contentView!.bounds)
        split.isVertical=true
        split.autoresizingMask=[.width,.height]
        split.addArrangedSubview(NSView())
        window.contentView=split
        let root=Bundle.main.resourceURL!.appendingPathComponent("Content/Help")
        let pane=HelpPane(root:root)
        pane.attach(to:split,owner:window)
        navigationWindow=window;navigationSplit=split;navigationPane=pane
        window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) {
            Task { @MainActor in
                do {
                    pane.open(pane.url(for:"1239")!)
                    try await until(pane.web,"location.pathname==='/parametric_methods/paired_t.htm' && document.readyState==='complete'")
                    let row=pane.view.subviews.compactMap { $0 as? NSStackView }.first { $0.arrangedSubviews.contains(pane.searchField) }
                    try check(row?.arrangedSubviews.compactMap { ($0 as? NSButton)?.title } == ["‹","›","Home","Contents","Index"],"The navigation-only host uses Home, Contents and Index in the agreed toolbar order")
                    try await checkContents(pane)
                    try await checkIndex(pane)
                    try await checkInvalidIndex(pane)
                    try await checkWideContents(pane)
                    try await checkTopics(pane)
                    try await checkTopicAliases(pane)
                    print("PASS: native help navigation checks");fflush(stdout)
                } catch {
                    print("FAIL: \(error.localizedDescription) \((error as NSError).userInfo)")
                    print("Missing assets: \(pane.resources.missing)");fflush(stdout)
                    pane.shutdown();exit(1)
                }
                pane.shutdown()
                if !CommandLine.arguments.contains("--stay-open") { app.terminate(nil) }
            }
        }
        app.run()
    }
    #else
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--run-tests") else { print("Use Scripts/test-help-pane.sh"); exit(2) }
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        let viewer=Viewer();app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: native offline help checks"); fflush(stdout) }
                catch { print("FAIL: \(error.localizedDescription) \((error as NSError).userInfo)");print("Missing assets: \(viewer.helpPane.resources.missing)"); fflush(stdout); exit(1) }
                if !CommandLine.arguments.contains("--stay-open") { viewer.closeApproved=true; app.terminate(nil) }
            }
        }
        app.run()
    }
    @MainActor static func run(_ v:Viewer) async throws {
        let h=v.helpPane, web=h.web
        let worksheet=v.active!
        let startingDocuments=v.documents.count
        let help=NSApp.mainMenu!.items.first { $0.submenu?.title == "Help" }!.submenu!
        let helpCommands:[(String,Selector)]=[
            ("Learning",#selector(Viewer.openLearning)),
            ("Learning Options…",#selector(Viewer.openLearningOptions)),
            ("Contents and Index…",#selector(Viewer.helpLibrary)),
            ("Method Selection…",#selector(Viewer.methodSelectionHelp)),
            ("Example workbook",#selector(Viewer.openExampleWorkbook)),
            ("Check for Updates…",#selector(Viewer.checkUpdates)),
            ("About StatsDirect…",#selector(Viewer.showAbout))
        ]
        try check(help.items.filter { !$0.isSeparatorItem }.map(\.title)==helpCommands.map(\.0),"Help has the Windows commands, with Example workbook before updates and About last")
        try check(zip(help.items.filter { !$0.isSeparatorItem },helpCommands).allSatisfy { $0.0.action==$0.1.1 && ($0.0.target as? Viewer) === v },"each Help command targets its implemented native action")
        let appMenu=NSApp.mainMenu!.items.first!.submenu!
        let automatic=appMenu.items.first { $0.action == #selector(Viewer.toggleAutomaticUpdates) }!
        try check(v.validateMenuItem(automatic) && automatic.state == .off,"automatic update preference remains accessible in the StatsDirect menu")
        try await until(worksheet.web,"!!window.statsDirectGrid")
        _ = try await js(worksheet.web,"statsDirectGrid.loadCSV('Before,After\\n1,2\\n3,4','Help selection.csv')")
        try await settle()
        _ = try await js(worksheet.web,"statsDirectGrid.editCommand('selectAll','')")
        try await settle()
        let selectionBefore = try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())") as? String

        try check(h.url(for:"1213")?.path == "/methods/method_selection.htm","Windows Method Selection context ID resolves to the bundled guide")
        help.performActionForItem(at:help.indexOfItem(withTitle:"Method Selection…"))
        try await until(web,"location.pathname.endsWith('/methods/method_selection.htm') && document.querySelector('h1') !== null")
        try check(v.active === worksheet && v.documents.count==startingDocuments,"Method Selection opens the help dock without replacing the selected worksheet")
        try check((try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())")) as? String == selectionBefore,"Method Selection preserves selected worksheet data")
        help.performActionForItem(at:help.indexOfItem(withTitle:"Contents and Index…"))
        try await until(web,"location.pathname.endsWith('/contents.htm') && document.readyState==='complete'")
        try check(true,"Contents and Index opens the offline Help contents through the actual menu action")

        web.configuration.userContentController.addUserScript(WKUserScript(source:"window.helpErrors=[];window.cspBlocked=[];addEventListener('error',e=>helpErrors.push(e.message||e.target.src),true);addEventListener('securitypolicyviolation',e=>cspBlocked.push(e.blockedURI));",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        try check(h.url(for:"1239")?.path == "/parametric_methods/paired_t.htm","historical paired t context ID resolves")
        try check(h.url(for:"PTT") == h.url(for:"1239"),"named aliases can be resolved")
        try check(h.resources.localURL(URL(string:"app://statsdirect-help/../../Info.plist")!) == nil || !FileManager.default.fileExists(atPath:h.resources.localURL(URL(string:"app://statsdirect-help/../../Info.plist")!)!.path),"path traversal cannot read outside the help bundle")
        try check(h.resources.localURL(URL(string:"app://elsewhere/contents.htm")!) == nil,"foreign help origin rejected")
        try check(h.resources.localURL(URL(string:"app://statsdirect-help/dAtA/aLiAs.XmL")!)?.path == h.resources.root.appendingPathComponent("Data/Alias.xml").path,"mixed-case links resolve to the bundle’s exact filename in both readers")
        v.openHelp(v.root.appendingPathComponent("Help/parametric_methods/paired_t.htm"),title:"Paired t")
        let exampleToggle = "details.rcode > summary, .MCDropDownHotSpot"
        let exampleOpen = "(()=>{const details=document.querySelector('details.rcode');return details ? details.open : document.querySelector('.MCDropDownHotSpot')?.getAttribute('aria-expanded')==='true'})()"
        try await until(web,"document.querySelector('" + exampleToggle + "') !== null")
        try await settle()
        try check(h.visible && h.view.superview === v.workspaceSplit && v.workspaceSplit.subviews.count == 2,"help docks alongside the workspace")
        try check(v.active === worksheet && v.documents.count == startingDocuments,"opening help preserves the active worksheet and document tabs")
        try check((try await js(web,"document.querySelector('h1').textContent.includes('Paired')")) as? Bool == true,"paired t topic rendered offline")
        try await until(web,"[...document.images].filter(i=>i.offsetWidth>0).every(i=>i.complete&&i.naturalWidth>0)")
        try check(true,"topic images and equations load")
        try check((try await js(web,"window.helpErrors")) as? [String] == [],"topic scripts have no runtime errors")
        _ = try await js(web,"(()=>{document.querySelector('" + exampleToggle + "').click();return true})()")
        try await until(web,exampleOpen)
        try check(true,"R example expands offline")
        _ = try await js(web,"(()=>{let elements=[document.scrollingElement,...document.querySelectorAll('*')];for(let e of elements){e.scrollTop=700;if(e.scrollTop>0){window.readingElement=e;return e.scrollTop}}return 0})()")
        let position=(try await js(web,"window.readingElement.scrollTop")) as? Double ?? 0
        try check(position>0,"reading position can be scrolled")
        h.toggleMode();try await settle()
        try check(h.web === web && h.view.window === h.floatingWindow && h.floatingWindow?.isVisible == true,"Pop out moves the same browser into a companion window")
        try check(v.workspaceSplit.subviews.count == 1 && v.active === worksheet,"Pop out restores workspace width and selection")
        try check((try await js(web,exampleOpen)) as? Bool == true,"expanded R example survives Pop out")
        h.toggleMode();try await settle()
        try check(h.view.superview === v.workspaceSplit && h.floatingWindow?.isVisible == false,"Dock returns the same browser")
        let returned=(try await js(web,"window.readingElement.scrollTop")) as? Double ?? 0
        try check(abs(returned-position)<3,"reading position survives Pop out and Dock")
        v.workspaceSplit.setPosition(v.workspaceSplit.bounds.width-400,ofDividerAt:0);try await settle()
        let width=h.view.frame.width
        h.hide();try await settle()
        try check(!h.visible && v.workspaceSplit.subviews.count == 1,"Close hides help and restores workspace width")
        h.open(web.url!);try await settle()
        try check(abs(h.view.frame.width-width)<3,"docked width is remembered on reopen")
        try check((try await js(web,exampleOpen)) as? Bool == true,"Close/reopen retains the same page state")
        // Native sheet and input focus stand in for modal parameter dialogs.
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:150),styleMask:[.titled],backing:.buffered,defer:false)
        let input=NSTextField(frame:NSRect(x:20,y:60,width:240,height:25));sheet.contentView!.addSubview(input)
        v.window.beginSheet(sheet,completionHandler:nil);sheet.makeFirstResponder(input);let responder=sheet.firstResponder;let originalKey=NSApp.keyWindow
        h.refreshModalPresentation();try await settle()
        try check(h.temporarilyFloating && h.view.window === h.floatingWindow,"help floats automatically during a modal sheet")
        try check(sheet.firstResponder === responder && NSApp.keyWindow === originalKey,"automatic floating preserves parameter input focus")
        try check(!h.modeButton.isEnabled && h.floatingWindow?.worksWhenModal == true,"help remains interactive and Dock is disabled during the modal sheet")
        if HelpKeywordIndex.exists(root:h.resources.root) {
            try check(try await index(h) && h.indexPicker.isVisible && pickerFocused(h,true),"The keyword Index remains usable in Help beside a modal parameter dialog")
            h.indexPicker.close()
        }
        v.window.endSheet(sheet);sheet.orderOut(nil);h.refreshModalPresentation();try await settle()
        try check(h.view.superview === v.workspaceSplit && !h.temporarilyFloating,"help returns to the chosen presentation after the sheet")
        h.toggleMode();try await settle();h.hide();h.open(web.url!);try await settle()
        try check(h.prefersFloating && h.view.window === h.floatingWindow,"floating preference survives Close/reopen")
        h.toggleMode();try await settle()
        guard let homeButton = paneButton(h,"Home") else { throw NSError(domain:"HelpPaneTests",code:3,userInfo:[NSLocalizedDescriptionKey:"the help pane has no Home button"]) }
        homeButton.performClick(nil);try await until(web,"location.pathname.endsWith('/contents.htm') && document.readyState==='complete'")
        try check((try await js(web,chrome)) as? String == hiddenChrome,"Home opens the help home page (topic 1000), where the web reader's header is hidden too")
        try await settle()
        h.back();try await until(web,"location.pathname.endsWith('/paired_t.htm') && document.readyState==='complete'")
        try check(web.canGoForward,"history survives presentation changes")
        h.forward();try await until(web,"location.pathname.endsWith('/contents.htm') && document.readyState==='complete'")
        h.searchField.stringValue="paired t test";h.search()
        let searchLinks = "#resultList a, #results a.result"
        try await until(web,"document.querySelectorAll('" + searchLinks + "').length > 0")
        try check((try await js(web,"document.querySelector('#search-results, #results').textContent.toLowerCase().includes('paired')")) as? Bool == true,"full-text search returns offline results")
        try check((try await js(web,chrome)) as? String == hiddenChrome,"the native search box's results page also hides the web reader's own header and search box")
        print("SEARCH URL: \(web.url!.absoluteString)")
        h.toggleMode();try await settle();h.toggleMode();try await settle()
        try check((try await js(web,"document.querySelectorAll('" + searchLinks + "').length>0")) as? Bool == true,"search results survive Pop out and Dock")
        let resultHref = try await js(web,"document.querySelector('" + searchLinks + "').href") as! String
        let resultPath = URLComponents(string:resultHref)!.percentEncodedPath
        let resultPathJSON = String(data:try JSONSerialization.data(withJSONObject:resultPath,options:[.fragmentsAllowed]),encoding:.utf8)!
        _ = try await js(web,"(()=>{document.querySelector('" + searchLinks + "').click();return true})()")
        try await until(web,"location.pathname===" + resultPathJSON + " && document.readyState==='complete' && document.querySelector('h1')!==null")
        try check(web.url?.scheme == "app","search result opens inside the offline help session")
        var external:[URL]=[];h.externalLink={external.append($0)}
        _ = try await js(web,"(()=>{let a=document.createElement('a');a.href='https://www.statsdirect.com/';a.target='_blank';document.body.append(a);a.click();return true})()")
        try await settle();try check(external.count==1 && external[0].host=="www.statsdirect.com","external references open once in the system browser")
        let remote = try await js(web,"(async()=>{try{await fetch('https://help.statsdirect.invalid/not-allowed');return false}catch{return true}})()")
        try check(remote as? Bool == true,"external resource fetching is blocked")
        try check((try await js(web,"window.cspBlocked.length>0")) as? Bool == true,"CSP blocks remote resources before network access")
        try check(h.resources.missing.isEmpty,"all requested local help assets exist: \(h.resources.missing)")
        // F1 from an operation updates help while the worksheet/tab and range stay intact.
        worksheet.operationName="TPaired"
        v.currentMethodHelp();try await until(web,"location.pathname.endsWith('/paired_t.htm') && document.readyState==='complete'")
        try check(v.active === worksheet && v.documents.count==startingDocuments,"context help retains the active data document")
        // As in the Windows help window (5.3.4), the web reader's banner, search box and Contents button are hidden inside
        // the native pane, where Home, Contents and the native search replace them; the banner stays in the page.
        let topicChrome = try await js(web,chrome) as? String ?? ""
        try check(topicChrome == hiddenChrome,"the web reader's banner, search box and menu button are hidden in the native help pane: \(topicChrome)")
        let rows = h.view.subviews.compactMap { $0 as? NSStackView }
        let titles = rows.map { $0.arrangedSubviews.compactMap { ($0 as? NSButton)?.title } }
        let navigationRow = rows.first { $0.arrangedSubviews.contains(h.searchField) }
        let narrowest = v.workspaceSplit.bounds.width - h.splitView(v.workspaceSplit,constrainMaxCoordinate:0,ofSubviewAt:0) - v.workspaceSplit.dividerThickness
        try check(navigationRow.map { $0.arrangedSubviews.compactMap { ($0 as? NSButton)?.title } } == ["‹","›","Home","Contents","Index"]
                  && titles.contains(["Print",h.modeButton.title,"×"]) && (navigationRow?.fittingSize.width ?? .infinity) + 16 <= narrowest,
                  "Back, Forward, Home, Contents, Index and the search box fit one row of the narrowest dock (\(narrowest) points), with Print beside \(h.modeButton.title): \(titles)")
        guard let browse = paneButton(h,"Contents") else { throw NSError(domain:"HelpPaneTests",code:3,userInfo:[NSLocalizedDescriptionKey:"the help pane has no Contents button"]) }
        try check(browse.isEnabled,"Contents is available once the topic has loaded")
        _ = try await js(web,"(()=>{window.__browseToken='kept';return true})()")
        browse.performClick(nil)
        try await until(web,"window.__browseToken==='kept' && location.pathname.endsWith('/paired_t.htm') && getComputedStyle(document.getElementById('help-navigation')).display!=='none' && document.activeElement?.getAttribute('aria-current')==='page' && document.activeElement.closest('#contents')!==null")
        try check(true,"Contents opens the reader's contents tree in place, with the current topic focused")
        let again = await withCheckedContinuation { (done:CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        let stillOpen = try await js(web,"window.__browseToken==='kept' && getComputedStyle(document.getElementById('help-navigation')).display!=='none' && document.activeElement?.getAttribute('aria-current')==='page'") as? Bool == true
        try check(again && stillOpen,"a second Contents keeps the contents open at the current topic")
        _ = try await js(web,"(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()")
        try await until(web,"!document.body.classList.contains('navigation-open')")
        try await checkContents(h)
        try await checkIndex(h)
        try await checkIndexRouting(h,v,worksheet)
        try await checkIndexCloseBesideAI(h,v,worksheet)
        try await checkInvalidIndex(h)
        try await checkWideContents(h)
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname.endsWith('/paired_t.htm') && document.readyState==='complete'")
        // App Translocation runs a downloaded app opened in place from /private/var/folders/...; the catalogue must still find every topic.
        do {
            let temporary = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("help-catalogue-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:temporary) }
            try FileManager.default.createDirectory(at:temporary.appendingPathComponent("basics"),withIntermediateDirectories:true)
            for page in ["contents.htm","basics/r_script_window.htm"] { try Data("<!doctype html><title>t</title>".utf8).write(to:temporary.appendingPathComponent(page)) }
            let real = temporary.resolvingSymlinksInPath().path
            let forms = Set([temporary.path, real, real.hasPrefix("/private/") ? String(real.dropFirst(8)) : "/private" + real]).sorted()
            let resolved = forms.map { form -> Bool in
                let catalogue = HelpResources(root:URL(fileURLWithPath:form))
                return catalogue.localURL(URL(string:"app://statsdirect-help/contents.htm")!) != nil
                    && catalogue.localURL(URL(string:"app://statsdirect-help/Basics/R_Script_Window.htm")!) != nil
            }
            try check(resolved.allSatisfy { $0 },"the help catalogue finds topics from every form of a /private path, as App Translocation runs a downloaded app: \(zip(forms,resolved).map { "\($0.0)=\($0.1)" })")
        }
        try check((try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())")) as? String == selectionBefore,"selected worksheet cells and values survive docking and context help")
        worksheet.operationName=nil
        try await until(web,"document.querySelector('a[href*=\"ref-armitage-1994\"]')!==null")
        _ = try await js(web,"(()=>{document.querySelector('a[href*=\"ref-armitage-1994\"]').click();return true})()")
        try await until(web,"location.hash==='#ref-armitage-1994' && document.getElementById('ref-armitage-1994')!==null")
        try check(true,"reference link opens the correct offline anchor")
        try await checkTopics(h)
        try await checkTopicAliases(h)
        try await checkTopicCallers(v)

        let pdf=try await web.pdf(configuration:WKPDFConfiguration())
        try check(pdf.count>1000,"help can be printed to PDF")
        for document in v.documents { v.remove(document) }
        // Model clicking the search field: a first responder in an inactive
        // window alone must not make that pane the target of menu commands.
        v.window.makeKeyAndOrderFront(nil)
        v.window.makeFirstResponder(h.searchField)
        try check(h.isFocused && v.validateMenuItem(NSMenuItem(title:"Copy",action:#selector(Viewer.editCommand(_:)),keyEquivalent:"c")),"help editing commands remain available without workspace documents")
        try check(v.validateMenuItem(NSMenuItem(title:"Close",action:#selector(Viewer.closeTab),keyEquivalent:"w")),"Close remains available for help without workspace documents")
        v.closeTab()
        try check(!h.visible,"Close Document hides focused help without closing the application")
    }
    /// The callers of HelpPane.showTopic, given the fixture's help, which has none of their topics, in place of the bundled help.
    @MainActor static func checkTopicCallers(_ v: Viewer) async throws {
        let original=v.helpPane
        let (folder,pane,window)=try topicFixture()
        v.helpPane=pane
        defer { v.helpPane=original;pane.shutdown();window.orderOut(nil);try? FileManager.default.removeItem(at:folder);v.window.makeKeyAndOrderFront(nil) }
        let help=NSApp.mainMenu!.items.first { $0.submenu?.title == "Help" }!.submenu!
        let callers:[(String,() async throws -> Void)]=[
            ("Method Selection",{ help.performActionForItem(at:help.indexOfItem(withTitle:"Method Selection…")) }),
            ("The calculator's Help",{ v.calculatorPane.help() }),
            ("F1 in the calculator",{ v.calculatorPane.open();try await press(v.window,String(UnicodeScalar(0xF704)!),122) })
        ]
        for (name,request) in callers {
            pane.showTopic("5003")
            try await until(pane.web,"location.pathname==='/first.htm' && document.readyState==='complete'")
            try await request()
            try await until(pane.web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
            try await settle()
            try check(pane.notice.stringValue == topicUnavailable,"\(name), with a help ID the help does not map, shows the help contents and Windows's status line")
        }
        v.calculatorPane.hide()
    }
    #endif
}
