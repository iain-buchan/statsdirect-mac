import Cocoa
import WebKit
import Darwin

@main struct LearningRecoveryTests {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let v = Viewer(); app.delegate = v
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let work = root.appendingPathComponent(".build/learning-recovery-" + UUID().uuidString)
        v.learningStorageOverride = work.appendingPathComponent("Learning")
        v.chatGPTTutor = ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:work.appendingPathComponent("chatgpt-mock"),resources:v.root.appendingPathComponent("Tutor"))
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(v); print("PASS: Learning streaming selection, isolated renderer recovery, restrictions and bridge lifecycle") }
                catch { print("FAIL:",error.localizedDescription,(error as NSError).userInfo); fflush(stdout); exit(1) }
                fflush(stdout); v.closeApproved = true; app.terminate(nil)
            }
        }
        app.run()
    }
    static func check(_ value: Bool, _ name: String) throws {
        if !value { throw ChatGPTTutor.Failure(message:name) }
    }
    @MainActor static func wait(_ name: String, _ predicate: () async throws -> Bool) async throws {
        for _ in 0..<200 {
            if try await predicate() { return }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw ChatGPTTutor.Failure(message:"Timed out: " + name)
    }
    @MainActor static func yes(_ v: Viewer,_ d: Document,_ expression: String) async -> Bool {
        (try? await v.learningJavaScript(d,"({ok:!!(\(expression))})"))?["ok"] as? Bool == true
    }
    @MainActor static func crash(_ v: Viewer,_ d: Document) async throws -> WKWebView {
        let old = d.web
        // Test-only WebKit SPI identifies this isolated renderer; never kill by name.
        try check(old.responds(to:NSSelectorFromString("_webProcessIdentifier")),"WebKit renderer PID test hook unavailable")
        let pid = (old.value(forKey:"_webProcessIdentifier") as? NSNumber)?.int32Value ?? 0
        try check(pid > 1 && pid != getpid(),"Invalid test renderer PID")
        try check(kill(pid,SIGKILL) == 0,"Cannot terminate isolated test renderer")
        try await wait("renderer termination callback") { d.learningNeedsRecovery && !d.learningRendererReady }
        return old
    }
    @MainActor static func reopen(_ v: Viewer,_ d: Document,_ old: WKWebView) async throws {
        v.openLearning()
        try await wait("fresh Learning page") { guard d.learningRendererReady && d.web !== old else { return false }; return await yes(v,d,"window.statsDirectLearn && document.getElementById('messages')") }
        try check(v.documents.filter{$0.kind == "learn"}.count == 1,"Recovery created duplicate documents")
        try check(!d.web.configuration.websiteDataStore.isPersistent,"Recovered page must use nonpersistent storage")
        try check(d.web.navigationDelegate === v && d.web.uiDelegate === v,"Recovered page lost delegates")
        try check(!d.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically,"Recovered page permits automatic popups")
        try check(old.navigationDelegate == nil && old.uiDelegate == nil && v.document(for:old) == nil,"Stale renderer remains attached")
    }
    @MainActor static func begin(_ v: Viewer,_ d: Document,_ id: String,_ text: String) {
        d.learningRequestID = id
        v.learningScript(d,"partial",["id":id,"text":text])
        v.learningScript(d,"resumeReply",d.learningReplyEvent!)
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.openLearning(); let d = v.documents.first{$0.kind == "learn"}!
        try await wait("initial Learning page") { guard d.learningState != nil else { return false }; return await yes(v,d,"document.getElementById('messages')") }
        let fixture = try String(contentsOfFile:"Tests/learning-selection.js",encoding:.utf8)
        // Installing the fixture returns a function unless explicitly discarded;
        // WebKit cannot bridge JavaScript functions back to Swift.
        _ = try await d.web.evaluateJavaScript(fixture + "\n;void 0;")
        let selection = try await d.web.callAsyncJavaScript("try { return await runLearningSelectionChecks() } catch (error) { return {error: String(error), stack: error.stack} }",arguments:[:],in:nil,contentWorld:.page) as! [String:Any]
        try check(selection["error"] == nil,"Selection fixture: \(selection)")
        try check((selection["checks"] as? [String])?.count == 10,"Selection checks did not complete")
        print("PASS:",(selection["checks"] as! [String]).joined(separator:"; ")); fflush(stdout)
        try await wait("saved selection fixture") { (d.learningState?["conversation"] as? [[String:Any]])?.contains{$0["id"] as? String == "stopped-fixture"} == true }
        // Preserve the most recent host-held draft and settings, not an older file.
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('question').value='Keep my draft',document.getElementById('question').dispatchEvent(new Event('input')),true)})")
        try await wait("saved draft") { d.learningState?["draft"] as? String == "Keep my draft" }
        begin(v,d,"crash-partial","Received before the crash.")
        try await wait("first partial") { await yes(v,d,"document.getElementById('streamedReply')?.textContent.includes('Received before')") }
        let old = try await crash(v,d)
        v.learningScript(d,"partial",["id":"crash-partial","text":"Received before the crash. More arrived while the renderer was stopped."])
        try await reopen(v,d,old)
        try await wait("latest partial and draft restored") { await yes(v,d,"document.getElementById('streamedReply')?.textContent.includes('More arrived') && document.getElementById('question').value==='Keep my draft'") }
        try check((d.learningState?["conversation"] as? [[String:Any]])?.contains{$0["id"] as? String == "selection-fixture"} == true,"Saved history lost")
        let complete = "**Recovered reply**\n\n```r\nx <- c(2, 4, 6)\nmean(x)\n```"
        v.learningScript(d,"reply",["id":"crash-partial","text":complete,"model":"fixture-model"]); d.learningRequestID = nil
        try await wait("completed reply acknowledged") { guard d.learningReplyEvent == nil else { return false }; return await yes(v,d,"document.querySelectorAll('[data-code=r]').length===1") }
        let count = v.documents.filter{$0.kind == "r"}.count
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-code=r]').click()===undefined})")
        try await wait("single working Open in R bridge") { v.documents.filter{$0.kind == "r"}.count == count+1 }
        try await Task.sleep(nanoseconds:200_000_000)
        try check(v.documents.filter{$0.kind == "r"}.count == count+1 && v.active?.rPane?.editor.string.contains("x <- c(2, 4, 6)\nmean(x)") == true,"Duplicate or incorrect Open in R handler")
        try check(v.active?.rPane?.isRunning == false,"Tutor code ran without Run")
        v.tabs.selectTabViewItem(d.item)
        let restrictions = try await d.web.callAsyncJavaScript("let blocked=false;try{await fetch('https://example.invalid/private-test')}catch{blocked=true}return {blocked,csp:document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content}",arguments:[:],in:nil,contentWorld:.page) as! [String:Any]
        try check(restrictions["blocked"] as? Bool == true && (restrictions["csp"] as? String)?.contains("frame-src 'none'") == true,"External resource restrictions lost")
        let url = d.web.url
        d.web.load(URLRequest(url:URL(string:"https://example.invalid/blocked-navigation")!))
        try await Task.sleep(nanoseconds:250_000_000)
        try check(d.web.url == url,"External navigation was allowed")
        print("PASS: actual isolated renderer crash preserves history, draft and latest partial; fresh security settings, CSP and one Open in R bridge")
        // A completed reply arriving after the renderer has died must also replay once.
        begin(v,d,"crash-completed","Waiting for completion.")
        let second = try await crash(v,d)
        v.learningScript(d,"reply",["id":"crash-completed","text":"Completed while the renderer was down.","model":"fixture-model"]); d.learningRequestID = nil
        try await reopen(v,d,second)
        try await wait("completion replayed once") { (d.learningState?["conversation"] as? [[String:Any]])?.filter{$0["id"] as? String == "crash-completed"}.count == 1 && d.learningReplyEvent == nil }
        // A subsequent real protocol request works after both recoveries.
        _ = try await v.chatGPTTutor.signIn()
        try await wait("fixture sign-in") { v.chatGPTTutor.account != nil }
        v.learningSettings(d)
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('question').value='PRIVATE_EVENT_TEST Explain pairing after recovery.',document.getElementById('send').click(),true)})")
        try await wait("new streamed reply after recovery") { (d.learningState?["conversation"] as? [[String:Any]])?.last?["text"] as? String == "Analyse within-person differences." && d.learningTask == nil }
        let saved = try String(contentsOf:v.learningFolder.appendingPathComponent("portfolio.json"),encoding:.utf8)
        try check(!saved.contains("PRIVATE_SENTINEL") && saved.contains("event: other notification"),"Private protocol text reached persistent portfolio diagnostics")
        print("PASS: completion during renderer failure replays once; later protocol streaming and safe persistent diagnostics work")
        begin(v,d,"close-after-crash","Retain this partial when the failed tab is closed.")
        _ = try await crash(v,d); v.remove(d); v.openLearning()
        let reopened = v.documents.first{$0.kind == "learn"}!
        try await wait("closed failed tab restored") { (reopened.learningState?["conversation"] as? [[String:Any]])?.contains{($0["text"] as? String)?.contains("Retain this partial") == true} == true }
        try check(reopened.learningSourceID == "__none__", "Reopening granted document sharing")
        print("PASS: closing and reopening a failed tab retains received text without restoring sharing consent")
    }
}
