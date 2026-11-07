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
        let focused = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!focused && h.notice.stringValue.hasPrefix("Could not open the help topics"),"A failed Contents focus confirmation reports a visible failure")
        try await checkPageUnchanged(web,"Failed Contents focus does not replace the page or add history")
        _ = try await js(web,"(()=>{delete window.__contentsTarget.focus;return true})()")
        try await contents(h,paired)
        try check(h.notice.stringValue.isEmpty,"Successful Contents clears the earlier failure status")
        try await rememberPage(web)
        _ = try await js(web,"(()=>{window.__originalGetElementById=document.getElementById;document.getElementById=function(id){if(id==='contents')throw new Error('deliberate Contents failure');return window.__originalGetElementById.call(this,id)};return true})()")
        let failed = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!failed && h.notice.stringValue.hasPrefix("Could not open the help topics"),"A Contents script error reports status")
        try await checkPageUnchanged(web,"A Contents script error preserves the live page and history")
        _ = try await js(web,"(()=>{document.getElementById=window.__originalGetElementById;return true})()")
        try await contents(h,paired)
        try await rememberPage(web)
        _ = try await js(web,"(()=>{document.querySelectorAll('#contents a').forEach(a=>a.remove());return true})()")
        let empty = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!empty && h.notice.stringValue.hasPrefix("Could not open the help topics"),"An existing Contents tree with no links reports failure")
        try await checkPageUnchanged(web,"An empty Contents tree does not trigger a reader fallback")

        _ = try await js(web,"(()=>{document.getElementById('contents').remove();history.replaceState(null,'','/index.html');return true})()")
        try await nativeUntil { web.url?.path=="/index.html" }
        try await rememberPage(web)
        let missingAtHome = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try check(!missingAtHome && h.notice.stringValue.hasPrefix("Could not open the help topics"),"Missing Contents on index.html reports failure instead of entering a reload loop")
        try await checkPageUnchanged(web,"A missing tree on the reader preserves its URL and history")

        h.contents()
        try await until(web,"location.pathname==='/contents.htm' && document.readyState==='complete'")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        _ = try await js(web,"(()=>{document.getElementById('contents').remove();window.__missingContentsToken='removed';return true})()")
        _ = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete' && window.__missingContentsToken===undefined")
        try check(true,"Only a missing Contents tree opens the reader at the current topic")
        h.searchField.stringValue="paired t";h.search()
        try await until(web,"document.querySelector('#results')?.hidden===false && document.querySelectorAll('a.result').length>0")
        _ = try await js(web,"(()=>{document.getElementById('contents').hidden=false;return true})()")
        _ = await withCheckedContinuation { (done: CheckedContinuation<Bool,Never>) in h.showContents { done.resume(returning:$0) } }
        try await until(web,"document.getElementById('results').hidden && !document.getElementById('topic').hidden && !!document.activeElement.closest('#contents')")
        try check(true,"Contents restores the reader mode after search even when contents.hidden is false")
        h.open(h.url(for:"1239")!)
        try await until(web,"location.pathname==='/"+paired+"' && document.readyState==='complete'")
        try check(h.contentsButton.keyEquivalent.isEmpty && h.indexButton.keyEquivalent.isEmpty,"Contents and Index introduce no permanent shortcut")
        try await checkToolbarTraversal(h)
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
        try check(h.indexPicker.table.numberOfRows==726,"Index lists all 726 authored term-target records")
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

        try check(try await index(h),"Index reopens after cancellation")
        filter(h,"Cohen's kappa")
        try check(h.indexPicker.table.numberOfRows>0 && (0..<h.indexPicker.table.numberOfRows).allSatisfy { rowText(h,$0).localizedCaseInsensitiveContains("Cohen") },"Typing filters authored keywords and target titles")
        try await rememberPage(web)
        _ = h.indexPicker.handleKey(key(h,"\u{f701}",125))
        try await nativeUntil { pickerFocused(h,false) }
        try await checkPageUnchanged(web,"Moving through Index rows does not navigate")
        _ = h.indexPicker.handleKey(key(h,"\t",48))
        try await nativeUntil { pickerFocused(h,true) }
        _ = h.indexPicker.handleKey(key(h,"\t",48,.shift))
        try await nativeUntil { pickerFocused(h,false) }
        try check(true,"Tab and Shift+Tab reach both the Index filter and results")
        _ = h.indexPicker.handleKey(key(h,"\r",36))
        try await until(web,"location.pathname==='/agreement/kappa.htm' && document.readyState==='complete'")
        try check(!h.indexPicker.isVisible,"Enter opens the chosen Index topic in the same Help browser")
        try check(try await index(h),"Index reopens for another query")
        try check(h.indexPicker.filter.stringValue=="Cohen's kappa","Reopening Index retains the filter")
        try await rememberPage(web)
        clickRow(h,0,true)
        try await settle()
        try await checkPageUnchanged(web,"Right-clicking an Index row does not navigate")
        clickRow(h,-1)
        try await settle()
        try await checkPageUnchanged(web,"Clicking blank Index list space does not open its prior selection")
        filter(h,"Gaussian distribution")
        try check(h.indexPicker.table.numberOfRows==1,"Gaussian distribution has one authored Index target")
        clickRow(h,0)
        try await until(web,"location.pathname==='/distributions/normal.htm' && document.readyState==='complete'")
        try check(!h.indexPicker.isVisible,"A valid left-click opens the selected Index topic")
        try check(try await index(h),"Index reopens for no-match correction")
        filter(h,"__no_such_keyword__")
        try check(h.indexPicker.table.numberOfRows==0,"A no-match filter leaves no selectable target")
        try await rememberPage(web)
        _ = h.indexPicker.handleKey(key(h,"\r",36))
        try check(h.indexPicker.isVisible,"Enter with no Index match leaves the picker open")
        try await checkPageUnchanged(web,"Enter with no Index match preserves the page and history")
        _ = h.indexPicker.handleKey(key(h,"\u{1b}",53))
        try await nativeUntil { !h.indexPicker.isVisible }
        try check(h.view.window?.firstResponder === h.indexButton,"Escape closes Index and restores its toolbar focus")
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
        try check(h.indexPicker.table.numberOfRows>1,"Index retains authored ANOVA subentries")
        h.indexPicker.close()
        try check(try await index(h),"The same Index picker can be opened repeatedly")
        try check(h.indexPicker.filter.stringValue=="ANOVA","Repeated Index use keeps its last query")
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
        try check(window.makeFirstResponder(h.contentsButton),"Contents accepts keyboard focus after Index has closed")
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        h.contentsButton.keyDown(with:enter)
        try await until(web,visibleFocus("parametric_methods/paired_t.htm"))
        try check(!h.indexPicker.isVisible,"A previously used hidden Index does not intercept native Enter on Contents")
        try await checkPageUnchanged(web,"Native Contents Enter after Index use preserves the same topic, URL and history")
    }
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
        try check(try await index(h),"Index opens beside the wide reader")
        try check((try await js(h.web,"!document.body.classList.contains('navigation-open') && document.getElementById('help-navigation').getClientRects().length>0")) as? Bool == true,"Index preserves the wide reader's permanent sidebar")
        try await contents(h,"references/support.htm")
        try check(!h.indexPicker.isVisible,"Wide Contents closes Index")
        try await checkPageUnchanged(h.web,"Wide Contents and Index switching retains the topic and history")
        _ = try await js(h.web,"(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()")
        try await until(h.web,"document.activeElement===document.getElementById('topic') && !document.body.classList.contains('navigation-open')")
        try check(true,"Escape from the wide Contents tree returns focus to the topic")
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
            try await rememberPage(pane.web)
            pane.indexButton.performClick(nil)
            try await nativeUntil { pane.notice.stringValue.hasPrefix("Could not open the help index") }
            try check(!pane.indexPicker.isVisible && pane.notice.window?.isVisible == true,"Index toolbar reports \(name) visibly without opening a picker")
            try await checkPageUnchanged(pane.web,"Index toolbar rejects \(name) without replacing the page or history")
            pane.hide()
        }
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
                    if CommandLine.arguments.contains("--check-reader-escape") { try await checkWideContents(pane) }
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
        try await checkInvalidIndex(h)
        if CommandLine.arguments.contains("--check-reader-escape") { try await checkWideContents(h) }
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
    #endif
}
