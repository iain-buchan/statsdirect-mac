import Cocoa
import WebKit

@main struct ScriptAITests {
    @MainActor static func check(_ ok: Bool,_ message: String) throws {
        guard ok else { throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        print("PASS: "+message);fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end=Date().addingTimeInterval(30)
        while Date()<end { if try await condition() { return };try await Task.sleep(nanoseconds:50_000_000) }
        throw NSError(domain:"ScriptAI",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out waiting for script AI"])
    }
    @MainActor static func buttons(_ view:NSView) -> [NSButton] { (view as? NSButton).map{[$0]} ?? view.subviews.flatMap(buttons) }
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks");UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        let v=Viewer();app.delegate=v
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(v);print("PASS: script AI native and consent checks completed");fflush(stdout) }
                catch { print("FAIL:",error.localizedDescription);fflush(stdout);exit(1) }
                if !CommandLine.arguments.contains("--stay-open") { v.closeApproved=true;app.terminate(nil) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+160) { if !CommandLine.arguments.contains("--stay-open") { print("FAIL: script AI timed out");fflush(stdout);exit(1) } }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let storage=root.appendingPathComponent(".build/script-ai-mock-"+UUID().uuidString+"/chatgpt-mock")
        v.chatGPTTutor.shutdown()
        v.chatGPTTutor=ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-script-ai-server.py"),storage:storage,resources:v.root.appendingPathComponent("Tutor"))
        v.chatGPTTutor.changed={ [weak v] in v?.scriptAI.updateConnection() }
        func requests() -> [[String:Any]] {
            let text=(try? String(contentsOf:storage.appendingPathComponent("requests.jsonl"),encoding:.utf8)) ?? ""
            return text.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}
        }
        func turns() -> Int { requests().filter{$0["method"] as? String=="turn/start"}.count }
        v.window.setContentSize(NSSize(width:1200,height:850))
        let workbook=v.newDocument(kind:"grid",title:"PRIVATE_WORKBOOK",url:v.root.appendingPathComponent("Grid/index.html"))
        try await wait { (try? await workbook.web.evaluateJavaScript("!!window.statsDirectGrid")) as? Bool==true }
        _=try await workbook.web.callAsyncJavaScript("""
        await statsDirectGrid.loadWorkbook({name:'PRIVATE_WORKBOOK',sheets:[{name:'Fictional',rows:10,columns:3,headerRow:true,cells:[
          {col:0,row:0,text:'Before',kind:'text'},{col:1,row:0,text:'After',kind:'text'},{col:2,row:0,text:'NHS number',kind:'text'},
          ...[10,20,30].map((n,i)=>({col:0,row:i+1,text:String(n),kind:'number'})),
          ...[8,17,25].map((n,i)=>({col:1,row:i+1,text:String(n),kind:'number'})),
          {col:2,row:1,text:'FAKE-IDENTIFIER',kind:'text'}]}]});return true;
        """,arguments:[:],in:nil,contentWorld:.page)
        v.analysisSourceID=workbook.id
        let first=v.makeRScript(script:"PRIVATE_SCRIPT <- c(1, 2, 3)",saved:true)
        let ai=v.scriptAI
        let icon=buttons(first.rPane!.view).first{$0.accessibilityLabel()=="AI assistance"}
        try check(icon != nil,"R script toolbar has an accessible AI icon")
        icon!.performClick(nil)
        try await wait { ai.visible && ai.view.window != nil }
        try check(ai.scriptID==first.id && v.workspaceSplit.arrangedSubviews.count==2,"AI icon opens conversation dock beside the current script")
        try check(ai.shareScript.state == .off && ai.shareWorkbook.state == .off && !ai.sendButton.isEnabled,"sharing starts off and unsigned Send is disabled")
        try await Task.sleep(nanoseconds:150_000_000)
        try check(turns()==0 && !requests().contains{$0["method"] as? String=="thread/start"},"opening the dock sends no question, document metadata or data")
        _=try await v.chatGPTTutor.signIn();try await v.chatGPTTutor.refreshAccount()
        ai.input.string="NO_SHARING";ai.sendButton.performClick(nil)
        try await wait { !ai.isBusy && ai.transcript.string.contains("General R guidance") }
        try check(turns()==1,"question-only round trip excludes script and workbook names/content")
        ai.shareScript.performClick(nil);ai.shareWorkbook.performClick(nil)
        try check(!ai.sendButton.isEnabled && !ai.acknowledgement.isHidden,"sharing requires a separate no-identifiers confirmation")
        ai.input.string="DATA_TEST";ai.send()
        try check(turns()==1 && !ai.isBusy,"native Send also refuses document sharing without confirmation")
        ai.acknowledgement.performClick(nil)
        try check(ai.sendButton.isEnabled,"confirming the selected content enables Send")
        ai.sendButton.performClick(nil)
        try await wait { !ai.isBusy && ai.transcript.string.contains("three approved worksheet rows") }
        try check(turns()==2 && ai.acknowledgement.state == .off && !ai.sendButton.isEnabled,"consent applies once and must be renewed for another question")
        try check(first.rPane!.editor.string=="PRIVATE_SCRIPT <- c(1, 2, 3)","AI reply and suggested code do not alter or run the script")
        try check(ai.transcript.string.contains("Shared for this question:") && ai.transcript.string.contains("PRIVATE_WORKBOOK"),"conversation records the actual shared scope locally")
        let context=ScriptAIContext(viewer:v,script:first,workbook:workbook,active:{true})
        try check(!context.tools.contains{["statsdirect_run_analysis","statsdirect_open_analysis"].contains($0["name"] as? String ?? "")},"assistant exposes only read-only tools")
        do { _=try await context.call("statsdirect_run_analysis",[:]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"AI could run an analysis"]) }
        catch let error as NSError { try check(error.localizedDescription.contains("does not allow"),"unapproved write/execute tools are refused") }
        do { _=try await context.call("statsdirect_read_data",["documentId":workbook.id,"columns":[2],"firstRow":2,"lastRow":2]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Identifier read succeeded"]) }
        catch { let detail=(error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription;try check(detail.localizedCaseInsensitiveContains("identifier"),"identifier-heading protection remains active after consent") }
        let unrelated=v.newDocument(kind:"grid",title:"NOT_SHARED",url:v.root.appendingPathComponent("Grid/index.html"))
        do { _=try await context.call("statsdirect_read_data",["documentId":unrelated.id]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Unapproved document read succeeded"]) }
        catch { try check(error.localizedDescription.contains("not approved"),"new or unrelated documents do not enter the approved scope") }
        first.rPane!.editor.string="CHANGED_AFTER_CONSENT <- 99"
        let snapshot=try await context.call("statsdirect_read_document",["documentId":first.id])
        try check(snapshot["script"] as? String=="PRIVATE_SCRIPT <- c(1, 2, 3)","script edits during a reply do not expand the shared snapshot")
        workbook.gridVersion+=1
        do { _=try await context.call("statsdirect_workspace",[:]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Stale workbook allowed"]) }
        catch { try check(error.localizedDescription.contains("changed after confirmation"),"changed workbooks require a new sharing decision") }
        let large=v.makeRScript(script:String(repeating:"x",count:20000),saved:true)
        let bounded=try await ScriptAIContext(viewer:v,script:large,workbook:nil,active:{true}).call("statsdirect_read_document",["documentId":large.id])
        try check((bounded["script"] as? String)?.count==12000 && bounded["truncated"] as? Bool==true,"large scripts return explicit bounded excerpts")
        try check(ai.scriptID==large.id && ai.conversations[large.id]?.messages.isEmpty==true && ai.shareScript.state == .off,"a different script has its own conversation and sharing choices")
        v.tabs.selectTabViewItem(first.item)
        try check(ai.scriptID==first.id && ai.transcript.string.contains("three approved worksheet rows"),"returning to a script restores its conversation")
        v.helpPane.contents()
        try check(!ai.visible && v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"Help and AI share the right-hand dock without squeezing in a third pane")
        ai.open(first)
        try check(ai.visible && !v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"AI reopens beside the script and preserves its conversation")
        v.window.setContentSize(NSSize(width:980,height:620));v.window.contentView!.layoutSubtreeIfNeeded()
        ai.view.layoutSubtreeIfNeeded()
        try check(ai.view.bounds.width>=340 && ai.input.enclosingScrollView!.frame.height>=80 && ai.transcript.enclosingScrollView!.frame.height>=95,"composer, context and conversation fit the minimum docked window")
        ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged()
        ai.input.string="CANCEL_TEST";v.window.makeKeyAndOrderFront(nil);v.window.makeFirstResponder(ai.input)
        let sendEvent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        NSApp.sendEvent(sendEvent)
        try await wait { turns()==3 }
        try check(!first.rPane!.isRunning && first.rPane!.editor.string=="CHANGED_AFTER_CONSENT <- 99","Command-Return in the AI composer sends the question without running R")
        ai.stopButton.performClick(nil)
        try check(!ai.isBusy,"Stop cancels the assistant without stopping R")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor");ai.updateConnection()
        try check(!ai.sendButton.isEnabled && !ai.connection.isEnabled,"institutional AI policy disables connection and Send")
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        ai.newConversation()
        try check(ai.conversations[first.id]?.messages.isEmpty==true && ai.shareScript.state == .off && ai.shareWorkbook.state == .off,"New conversation removes prior context from subsequent prompts")
        v.window.makeFirstResponder(ai.input);v.closeTab()
        try check(!ai.visible && v.documents.contains(where:{$0===first}),"Command-W closes a focused AI dock without closing the script")
        ai.open(first);v.remove(first)
        try check(!ai.visible && ai.scriptID==nil && ai.conversations[first.id]==nil,"closing a script closes its AI dock and releases its conversation")
        if CommandLine.arguments.contains("--stay-open") { v.window.setContentSize(NSSize(width:1200,height:850));ai.open(large) }
    }
}
