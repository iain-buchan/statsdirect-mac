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
        try await until(worksheet.web,"!!window.statsDirectGrid")
        _ = try await js(worksheet.web,"statsDirectGrid.loadCSV('Before,After\\n1,2\\n3,4','Help selection.csv')")
        try await settle()
        _ = try await js(worksheet.web,"statsDirectGrid.editCommand('selectAll','')")
        try await settle()
        let selectionBefore = try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())") as? String

        web.configuration.userContentController.addUserScript(WKUserScript(source:"window.helpErrors=[];window.cspBlocked=[];addEventListener('error',e=>helpErrors.push(e.message||e.target.src),true);addEventListener('securitypolicyviolation',e=>cspBlocked.push(e.blockedURI));",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        try check(h.url(for:"1239")?.path == "/parametric_methods/paired_t.htm","historical paired t context ID resolves")
        try check(h.url(for:"PTT") == h.url(for:"1239"),"named aliases can be resolved")
        try check(h.resources.localURL(URL(string:"app://statsdirect-help/../../Info.plist")!) == nil || !FileManager.default.fileExists(atPath:h.resources.localURL(URL(string:"app://statsdirect-help/../../Info.plist")!)!.path),"path traversal cannot read outside the help bundle")
        try check(h.resources.localURL(URL(string:"app://elsewhere/contents.htm")!) == nil,"foreign help origin rejected")
        try check(h.resources.localURL(URL(string:"app://statsdirect-help/resources/Scripts/jquery.min.js")!)?.path == h.resources.root.appendingPathComponent("resources/scripts/jquery.min.js").path,"mixed-case Windows links resolve to the bundle’s exact filename")
        v.openHelp(v.root.appendingPathComponent("Help/parametric_methods/paired_t.htm"),title:"Paired t")
        try await until(web,"document.querySelector('.MCDropDownHotSpot') !== null && typeof MadCap !== 'undefined'")
        try await settle()
        try check(h.visible && h.view.superview === v.workspaceSplit && v.workspaceSplit.subviews.count == 2,"help docks alongside the workspace")
        try check(v.active === worksheet && v.documents.count == startingDocuments,"opening help preserves the active worksheet and document tabs")
        try check((try await js(web,"document.querySelector('h1').textContent.includes('Paired')")) as? Bool == true,"paired t topic rendered offline")
        try check((try await js(web,"[...document.images].filter(i=>i.offsetWidth>0).every(i=>i.complete&&i.naturalWidth>0)")) as? Bool == true,"topic images and equations load")
        try check((try await js(web,"window.helpErrors")) as? [String] == [],"topic scripts have no runtime errors")
        _ = try await js(web,"(()=>{document.querySelector('.MCDropDownHotSpot').click();return true})()")
        try await until(web,"document.querySelector('.MCDropDownHotSpot').getAttribute('aria-expanded')==='true'")
        try check(true,"R example expands offline")
        _ = try await js(web,"(()=>{let elements=[document.scrollingElement,...document.querySelectorAll('*')];for(let e of elements){e.scrollTop=700;if(e.scrollTop>0){window.readingElement=e;return e.scrollTop}}return 0})()")
        let position=(try await js(web,"window.readingElement.scrollTop")) as? Double ?? 0
        try check(position>0,"reading position can be scrolled")
        h.toggleMode();try await settle()
        try check(h.web === web && h.view.window === h.floatingWindow && h.floatingWindow?.isVisible == true,"Pop out moves the same browser into a companion window")
        try check(v.workspaceSplit.subviews.count == 1 && v.active === worksheet,"Pop out restores workspace width and selection")
        try check((try await js(web,"document.querySelector('.MCDropDownHotSpot').getAttribute('aria-expanded')==='true'")) as? Bool == true,"expanded R example survives Pop out")
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
        try check((try await js(web,"document.querySelector('.MCDropDownHotSpot').getAttribute('aria-expanded')==='true'")) as? Bool == true,"Close/reopen retains the same page state")
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
        h.contents();try await until(web,"location.pathname.endsWith('/contents.htm') && document.readyState==='complete'")
        try await settle()
        h.back();try await until(web,"location.pathname.endsWith('/paired_t.htm') && document.readyState==='complete'")
        try check(web.canGoForward,"history survives presentation changes")
        h.forward();try await until(web,"location.pathname.endsWith('/contents.htm') && document.readyState==='complete'")
        h.searchField.stringValue="paired t test";h.search()
        try await until(web,"document.querySelectorAll('#resultList a').length > 0")
        try check((try await js(web,"document.querySelector('#search-results').textContent.toLowerCase().includes('paired')")) as? Bool == true,"full-text search returns offline results")
        print("SEARCH URL: \(web.url!.absoluteString)")
        h.toggleMode();try await settle();h.toggleMode();try await settle()
        try check((try await js(web,"document.querySelectorAll('#resultList a').length>0")) as? Bool == true,"search results survive Pop out and Dock")
        _ = try await js(web,"(()=>{document.querySelector('#resultList a').click();return true})()")
        try await until(web,"!location.pathname.endsWith('/search.htm') && document.querySelector('h1')!==null")
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
        try check((try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())")) as? String == selectionBefore,"selected worksheet cells and values survive docking and context help")
        worksheet.operationName=nil
        try await until(web,"document.querySelector('a[href*=\"ref-armitage-1994\"]')!==null")
        _ = try await js(web,"(()=>{document.querySelector('a[href*=\"ref-armitage-1994\"]').click();return true})()")
        try await until(web,"location.hash==='#ref-armitage-1994' && document.getElementById('ref-armitage-1994')!==null")
        try check(true,"reference link opens the correct offline anchor")

        let pdf=try await web.pdf(configuration:WKPDFConfiguration())
        try check(pdf.count>1000,"help can be printed to PDF")
        for document in v.documents { v.remove(document) }
        v.window.makeFirstResponder(h.searchField)
        try check(h.isFocused && v.validateMenuItem(NSMenuItem(title:"Copy",action:#selector(Viewer.editCommand(_:)),keyEquivalent:"c")),"help editing commands remain available without workspace documents")
        try check(v.validateMenuItem(NSMenuItem(title:"Close",action:#selector(Viewer.closeTab),keyEquivalent:"w")),"Close remains available for help without workspace documents")
        v.closeTab()
        try check(!h.visible,"Close Document hides focused help without closing the application")
    }
}
