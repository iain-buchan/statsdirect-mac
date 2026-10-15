import Cocoa
import WebKit
import Darwin

@main struct ReportAITests {
    @MainActor static func check(_ ok: Bool,_ message: String) throws {
        guard ok else { throw ChatGPTTutor.Failure(message:message) }
        print("PASS: " + message);fflush(stdout)
    }
    @MainActor static func wait(_ label: String,_ condition: () async throws -> Bool) async throws {
        for _ in 0..<300 { if try await condition() { return };try await Task.sleep(nanoseconds:100_000_000) }
        throw ChatGPTTutor.Failure(message:"Timed out: " + label)
    }
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks");UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        let viewer=Viewer();app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer);print("PASS: native report AI dock and sharing integration");fflush(stdout) }
                catch { print("FAIL:",error.localizedDescription,(error as NSError).userInfo,"AI notice:",viewer.scriptAI.notice.stringValue);fflush(stdout);exit(1) }
                viewer.closeApproved=true;app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+150) { print("FAIL: report AI timed out");fflush(stdout);exit(1) }
        app.run()
    }
    @MainActor static func ready(_ doc: Document) async throws {
        try await wait("report toolbar") {
            guard !doc.web.isLoading else { return false }
            return (try? await doc.web.evaluateJavaScript("!!document.querySelector('[data-command=ai]')")) as? Bool == true
        }
    }
    @MainActor static func text(_ ai: ScriptAIPane) async -> String {
        (try? await ai.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
    }
    @MainActor static func js(_ ai: ScriptAIPane,_ source: String) async throws -> Any {
        try await ai.transcript.web.evaluateJavaScript(source) ?? NSNull()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let work=root.appendingPathComponent(".build/report-ai-"+UUID().uuidString)
        let storage=work.appendingPathComponent("chatgpt-mock")
        v.learningStorageOverride=work.appendingPathComponent("Learning")
        v.chatGPTTutor.shutdown()
        v.chatGPTTutor=ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-report-ai-server.py"),storage:storage,resources:v.root.appendingPathComponent("Tutor"))
        v.chatGPTTutor.changed={ [weak v] in v?.scriptAI.updateConnection() }
        func requests() -> String { (try? String(contentsOf:storage.appendingPathComponent("requests.jsonl"),encoding:.utf8)) ?? "" }
        v.window.setContentSize(NSSize(width:1280,height:850))
        let unrelatedScript=v.makeRScript(script:"UNSHARED_SCRIPT <- 999",saved:true)
        let workbook=v.newDocument(kind:"grid",title:"UNSHARED_WORKBOOK",url:v.root.appendingPathComponent("Grid/index.html"))
        try await wait("worksheet") { (try? await workbook.web.evaluateJavaScript("!!window.statsDirectGrid")) as? Bool == true }
        _=try await workbook.web.callAsyncJavaScript("await statsDirectGrid.loadWorkbook({name:'UNSHARED_WORKBOOK',sheets:[{name:'Fictional',rows:10,columns:2,headerRow:true,cells:[{col:0,row:0,text:'Value',kind:'text'},{col:0,row:1,text:'12',kind:'number'}]}]});return true",arguments:[:],in:nil,contentWorld:.page)
        let before=[312,242,340,388,296,254,391,402,290],after=[300,201,232,312,220,256,328,330,231]
        let dataset:[String:Any]=["complete":true,"rowCount":9,"columns":[["title":"Before","values":before,"index":0],["title":"After","values":after,"index":1]]]
        let result=try await TutorTools.run(operation:"TPaired",dataset:dataset,agreement:true,studyType:"neither",preferences:[:]) { request in
            try await withCheckedThrowingContinuation { continuation in v.analysisRequest(request,entry:"statsdirect_operation"){continuation.resume(with:$0)} }
        }
        let report=v.appendReport(ReportEntry(id:"paired-fixture",title:"Paired t and agreement",operation:"TPaired",body:result["html"] as! String,record:"HIDDEN_RECORD_SECRET",helpPath:v.analysisCatalog["TPaired"]?["help"] as? String))
        report.title="PRIVATE_REPORT"
        try await ready(report)
        let ai=v.scriptAI,revision=report.reportRevision,original=report.reportEntries![0].body
        try check(try await report.web.evaluateJavaScript("document.querySelector('[data-command=ai]').getAttribute('aria-label')==='AI assistance'&&!document.querySelector('[data-command=ai]').disabled&&document.querySelector('[data-command=ai] svg')!==null") as? Bool == true,"report toolbar has an enabled accessible Windows-style AI icon")
        _=try await report.web.evaluateJavaScript("document.querySelector('[data-command=ai]').click();true")
        try await wait("report AI dock") { ai.visible && ai.scriptID==report.id }
        try await wait("introductory HTML") { (await text(ai)).contains("what your results mean") }
        try check((await text(ai)).contains("what your results mean") && v.workspaceSplit.arrangedSubviews.count==2 && ai.shareScript.title=="Share this report","AI opens beside the report with interpretation guidance and report sharing")
        try check(ai.shareScript.state == .off && ai.shareWorkbook.state == .off && !requests().contains("thread/start"),"opening the dock sends no report, worksheet or question and sharing starts off")
        // The workbook offered for sharing follows the result's record, as the Windows pane offers it (Iain's finding on the installed
        // build): opened on a result whose record names another open workbook than the session's data document, the pane selects that
        // workbook through the data-document path and the status line says so; a result without a usable record leaves the box as it was.
        let recordWorkbook=v.newDocument(kind:"grid",title:"RECORD_WORKBOOK",url:v.root.appendingPathComponent("Grid/index.html"));recordWorkbook.workbookName="RECORD_WORKBOOK.xlsx"
        try await wait("record worksheet") { (try? await recordWorkbook.web.evaluateJavaScript("!!window.statsDirectGrid")) as? Bool == true }
        v.selectAIDataDocument(workbook.id)
        let second=v.makeReport();try await ready(second)
        let recordJSON="{\"version\":1,\"operation\":\"TPaired\",\"title\":\"Recorded result\",\"run\":\"2026-10-14T06:00:00+01:00\",\"source\":{\"file\":\"RECORD_WORKBOOK.xlsx\",\"unsaved\":true},\"inputs\":[{\"name\":\"data\",\"prompt\":\"Select data\",\"kind\":\"frame\",\"file\":\"RECORD_WORKBOOK.xlsx\",\"path\":\"RECORD_WORKBOOK.xlsx\",\"sheet\":\"Sheet1\",\"columns\":[]}],\"parameters\":{},\"values\":{}}"
        let recorded=v.appendReport(ReportEntry(id:"record-fixture",title:"Recorded result",operation:"TPaired",body:"<p id='record-fixture-text'>From the record workbook</p>",record:recordJSON,recipe:true));try await ready(recorded)
        try check(recorded===second,"the recorded result lands in the second report")
        ai.open(recorded,reportResultID:"record-fixture")
        try check(ai.workbookPicker.selectedItem?.representedObject as? String==recordWorkbook.id && v.aiSharing.dataDocumentID==recordWorkbook.id && v.status.stringValue=="The workbook offered for sharing is the result's: RECORD_WORKBOOK","opening the AI pane on a result offers the workbook its record names, through the session's data-document path, and says so")
        v.selectAIDataDocument(workbook.id);v.appendReport(ReportEntry(id:"note-fixture",title:"Note",operation:"",body:"<p>A note</p>",record:nil));try await ready(recorded)
        ai.open(recorded,reportResultID:"note-fixture")
        try check(ai.workbookPicker.selectedItem?.representedObject as? String==workbook.id,"a result without a record leaves the offered workbook as it was")
        v.remove(recorded);v.remove(recordWorkbook);v.tabs.selectTabViewItem(report.item)
        ai.open(report,reportResultID:"paired-fixture")
        try await wait("report AI dock again") { ai.visible && ai.scriptID==report.id }
        _=try await v.chatGPTTutor.signIn();try await v.chatGPTTutor.refreshAccount()
        ai.input.string="NO_SHARING";ai.sendButton.performClick(nil)
        try await wait("question only") { (await text(ai)).contains("confidence interval describes") }
        try check(!requests().contains("PRIVATE_REPORT"),"a question without sharing excludes report title, results and other documents")
        // Enter sends the question and Shift+Enter adds a line, as the Windows pane has it (914d325b) and the calculator's input already
        // does: through the view's own key handling, so the window need not hold focus
        ai.input.string="LINE_ONE";ai.setSelectedEnd()
        ai.input.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.shift,timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
        try check(ai.input.string=="LINE_ONE\n","Shift+Enter adds a line to the question")
        ai.input.string="NO_SHARING";ai.setSelectedEnd()
        let turnsBeforeEnter=requests().components(separatedBy:"\"method\": \"turn/start\"").count
        ai.input.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
        try await wait("Enter sends the question") { requests().components(separatedBy:"\"method\": \"turn/start\"").count==turnsBeforeEnter+1 }
        try await wait("the reply to the question sent with Enter") { !ai.isBusy }
        try check(ai.input.string.isEmpty && v.scriptAI.view.labels().contains("Your question (Enter sends; Shift+Enter adds a line)"),"Enter sends the question and clears the box; the label says so")
        ai.shareScript.performClick(nil);ai.input.string="REPORT_TEST"
        try check(!ai.sendButton.isEnabled,"sharing a report requires the no-identifiers confirmation")
        ai.send();try check(!ai.isBusy,"native Send refuses unconfirmed report sharing")
        ai.acknowledgement.performClick(nil)
        try check(ai.contextPanel.isHidden && ai.contextButton.title.contains("report") && ai.sendButton.isEnabled,"confirmed report sharing collapses into the compact summary")
        ai.sendButton.performClick(nil)
        try await wait("report and method help reply") { (await text(ai)).contains("mean paired difference is about 56.1") }
        try check(requests().contains("statsdirect-report-assistant") && requests().contains("statsdirect_method_help"),"report-specific instructions, actual paired results and method-help tool work through the native provider bridge")
        try check(report.reportRevision==revision && report.reportEntries![0].body==original && !unrelatedScript.rPane!.isRunning,"AI interpretation does not edit reports or execute R")
        try check(try await js(ai,"!!document.querySelector('.message-body strong') && !!document.querySelector('.message-body table') && !!document.querySelector('.katex')") as? Bool == true,"AI replies display formatted headings, tables and equations in a WebView")
        try check(!ai.transcript.web.configuration.websiteDataStore.isPersistent && !ai.transcript.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically,"AI WebView uses isolated storage and disallows automatic popups")
        let image=try await ai.transcript.web.takeSnapshot(configuration:nil)
        try NSBitmapImageRep(data:image.tiffRepresentation!)?.representation(using:.png,properties:[:])?.write(to:root.appendingPathComponent(".build/ai-webview-conversation.png"))
        let board=NSPasteboard.general
        let savedBoard=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        do {
            defer { board.clearContents();board.writeObjects(savedBoard.map { data in let item=NSPasteboardItem();for(type,value) in data {item.setData(value,forType:type)};return item }) }
            _=try await js(ai,"document.querySelector('[data-code=copy]').click();true")
            try await wait("native code copy") { board.string(forType:.string)?.contains("x <- c(1, 2, 3)")==true }
            try check(board.string(forType:.string)?.contains("mean(x)")==true,"the WebView Copy button copies the actual R code through the native bridge")
        }
        let beforeRecovery=ai.transcript.web!
        let turnsBeforeRecovery=requests().components(separatedBy:"\"method\": \"turn/start\"").count
        let pid=(beforeRecovery.value(forKey:"_webProcessIdentifier") as? NSNumber)?.int32Value ?? 0
        try check(pid>1 && pid != getpid(),"isolated AI renderer identified for recovery test")
        _=kill(pid,SIGKILL)
        try await wait("AI renderer recovery") { guard ai.transcript.web !== beforeRecovery else { return false };return (await text(ai)).contains("mean paired difference") }
        try check(requests().components(separatedBy:"\"method\": \"turn/start\"").count==turnsBeforeRecovery && ai.conversations[report.id]?.messages.count==6,"renderer recovery restores conversation without resending")
        let restrictions=try await ai.transcript.web.callAsyncJavaScript("let blocked=false;try{await fetch('https://example.invalid/blocked')}catch{blocked=true}return blocked",arguments:[:],in:nil,contentWorld:.page)
        try check(restrictions as? Bool==true,"AI conversation cannot fetch external resources")
        try check(ai.acknowledgement.state == .on && ai.sendButton.isEnabled && ai.contextPanel.isHidden,"sharing acceptance persists across follow-up questions and stays compact")
        let context=ScriptAIContext(viewer:v,script:nil,workbook:nil,report:report,reportResultID:"paired-fixture",active:{true})
        let snapshot=try await context.call("statsdirect_read_document",["documentId":report.id])
        let snapshotText=String(decoding:try JSONSerialization.data(withJSONObject:snapshot),as:UTF8.self)
        try check(snapshotText.contains("56.111") && !snapshotText.contains("HIDDEN_RECORD_SECRET") && snapshot["chartImagesIncluded"] as? Bool==false,"report snapshot includes rendered results and declares chart limits without hidden run records")
        try check(!context.tools.contains{$0["name"] as? String=="statsdirect_read_data"} && !context.tools.contains{$0["name"] as? String=="statsdirect_run_analysis"},"report-only sharing exposes neither worksheet reads nor analysis execution")
        do { _=try await context.call("statsdirect_read_document",["documentId":unrelatedScript.id]);throw ChatGPTTutor.Failure(message:"Unshared script accepted") }
        catch { try check(error.localizedDescription.contains("not approved"),"unrelated scripts are inaccessible from the report conversation") }
        _=try await report.web.evaluateJavaScript("document.querySelector('.report-entry').insertAdjacentHTML('beforeend','<p>AFTER_SEND_ONLY</p>');true")
        report.reportRevision += 1
        let frozen=try await context.call("statsdirect_read_document",["documentId":report.id])
        try check(!(frozen["text"] as! String).contains("AFTER_SEND_ONLY"),"edits after the snapshot cannot expand an earlier question's shared report")
        let changed=ScriptAIContext(viewer:v,script:nil,workbook:nil,report:report,active:{true});report.reportRevision += 1
        do { _=try await changed.context();throw ChatGPTTutor.Failure(message:"Changed report accepted") }
        catch { try check(error.localizedDescription.contains("changed after confirmation"),"report changes before capture require fresh confirmation") }
        let both=ScriptAIContext(viewer:v,script:nil,workbook:workbook,report:report,active:{true})
        let data=try await both.call("statsdirect_read_data",["documentId":workbook.id,"columns":[0],"firstRow":2,"lastRow":2])
        try check((data["rCode"] as? String)?.contains("column_0") == true,"separately approved workbook data is available with exact R bindings")
        ai.input.string="Keep my report question"
        v.tabs.selectTabViewItem(unrelatedScript.item)
        try check(ai.scriptID==unrelatedScript.id && ai.shareScript.title.contains("script") && ai.conversations[unrelatedScript.id]?.messages.isEmpty==true,"script conversations stay separate from report conversations")
        try check(ai.shareScript.state == .on && ai.acknowledgement.state == .on && ai.contextPanel.isHidden && ai.sendButton.isEnabled,"Report acceptance carries into Script without another confirmation")
        v.tabs.selectTabViewItem(report.item)
        try await wait("restored report HTML") { (await text(ai)).contains("mean paired difference") }
        try check((await text(ai)).contains("mean paired difference") && ai.input.string=="Keep my report question","returning to the report restores its draft and conversation")
        let other=v.makeReport();other.title="UNRELATED_REPORT";try await ready(other)
        try check(ai.scriptID==other.id && ai.conversations[other.id]?.messages.isEmpty==true && ai.shareScript.state == .on && ai.acknowledgement.state == .on,"another report has a separate conversation and reuses session acceptance")
        v.tabs.selectTabViewItem(report.item)
        v.helpPane.contents();try check(!ai.visible && v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"report AI and Help use the same right dock")
        report.reportContext=["inReport":true,"resultId":"paired-fixture"]
        let menu=NSMenu();v.extendReportMenu(menu,for:report)
        let item=menu.items.first{$0.title=="AI Assistance…"}
        try check(item != nil,"report context menu offers AI assistance")
        _=NSApp.sendAction(item!.action!,to:item!.target,from:item)
        try check(ai.visible && !v.helpPane.visible && ai.scriptID==report.id && ai.input.string=="Keep my report question","context menu reopens the report conversation without losing the draft")
        v.openLearning();let learner=v.documents.first{$0.kind=="learn"}!
        try await wait("learning for session sharing") { learner.learningState != nil }
        learner.learningSourceID=report.id;learner.learningRequestID="shared-session"
        let learningScope=LearningWorkspace(v,learner,"shared-session")
        try await learningScope.authorize()
        try check(learningScope.allowed==Set([report.id]) && v.window.attachedSheet==nil,"Report acceptance also covers Learning without another dialog")
        try check((learner.learningState?["sharingConsents"] as? [[String:Any]])?.last?["reusedAcceptance"] as? Bool==true,"Learning records reuse of the session acceptance before reading documents")
        learner.learningRequestID=nil;v.tabs.selectTabViewItem(report.item)
        try await wait("R button after conversation switch") { (try? await js(ai,"!!document.querySelector('[data-code=r]:not(:disabled)')")) as? Bool == true }
        _=try await js(ai,"document.querySelector('[data-code=r]').click();true")
        try await wait("R script from HTML button") { v.active?.rPane?.editor.string.contains("x <- c(1, 2, 3)")==true }
        try check(v.active?.rPane?.editor.string.contains("x <- c(1, 2, 3)")==true && v.active?.rPane?.isRunning==false,"R suggestions from report AI open for review without running")
        v.tabs.selectTabViewItem(report.item)
        ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged();ai.input.string="CANCEL_TEST";ai.send()
        try await wait("pending report reply") { requests().contains("CANCEL_TEST") }
        ai.stopButton.performClick(nil);try check(!ai.isBusy,"Stop cancels a report AI reply")
        ai.newConversation();try check(ai.conversations[report.id]?.messages.isEmpty==true && v.aiSharing.accepted,"new report conversation clears history while retaining session acceptance")
        v.window.setContentSize(NSSize(width:980,height:620));v.window.contentView!.layoutSubtreeIfNeeded()
        try check(ai.view.bounds.width>=340 && ai.input.enclosingScrollView!.frame.height>=80 && ai.transcript.view.frame.height>=95,"report and conversation remain usable in the minimum docked window")
        let otherWorkbook=v.newDocument(kind:"grid",title:"Different data",url:v.root.appendingPathComponent("Grid/index.html"))
        try check(!v.aiSharing.accepted && ai.acknowledgement.state == .off,"selecting a new data document clears app-wide acceptance")
        v.tabs.selectTabViewItem(report.item);ai.shareScript.state = .on;ai.sharingChanged()
        try check(!ai.sendButton.isEnabled && !ai.contextPanel.isHidden,"returning to Report requires confirmation for the new data document")
        ai.acknowledgement.performClick(nil);v.tabs.selectTabViewItem(unrelatedScript.item)
        try check(ai.sendButton.isEnabled && ai.acknowledgement.state == .on,"renewed acceptance for new data carries across the app")
        v.tabs.selectTabViewItem(workbook.item)
        try check(!v.aiSharing.accepted,"selecting a different workbook again resets acceptance")
        v.tabs.selectTabViewItem(report.item);ai.acknowledgement.performClick(nil)
        try check(!AISharingConsent().accepted,"a fresh app session never restores acceptance")
        v.remove(otherWorkbook)
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor");ai.updateConnection()
        try check(!ai.sendButton.isEnabled && !ai.connection.isEnabled,"institutional AI policy applies to report assistance")
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        try check(ai.focusComposer() && v.window.firstResponder === ai.input,"the visible report composer accepts keyboard focus")
        // App activation is not guaranteed on an unattended runner. Explicitly
        // cover the same temporary loss of key status when returning from a
        // system dialog: window-targeted commands must still honor its responder.
        v.window.orderOut(nil)
        try await wait("window relinquishes key status") { NSApp.keyWindow !== v.window }
        try check(!v.window.isKeyWindow && NSApp.keyWindow !== v.window && ai.isFocused,"AI responder ownership survives loss of key-window status")
        try check(v.findableReport==nil,"report Replace commands do not target a report while composing in its AI dock")
        v.window.makeKeyAndOrderFront(nil)
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:250,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        v.window.beginSheet(sheet,completionHandler:{ _ in })
        try check(!ai.isFocused && !ai.focusComposer(),"a sheet keeps focus and commands out of the AI dock behind it")
        v.window.endSheet(sheet);sheet.orderOut(nil)
        try await wait("sheet dismissed") { v.window.attachedSheet == nil }
        try check(ai.focusComposer() && ai.isFocused,"the composer accepts focus again after the sheet closes")
        v.closeTab()
        try check(!ai.visible && v.documents.contains(where:{$0===report}),"Command-W in the report dock closes the dock, preserving the report")
        ai.open(report);v.remove(report)
        try check(!ai.visible && ai.conversations[report.id]==nil,"closing a report releases its AI conversation")
        let large=v.appendReport(ReportEntry(id:"large",title:"Long report",operation:"",body:"<p>"+String(repeating:"Large report text ",count:3000)+"</p>",record:nil));try await ready(large)
        let bounded=try await ScriptAIContext(viewer:v,script:nil,workbook:nil,report:large,active:{true}).call("statsdirect_read_document",["documentId":large.id])
        try check((bounded["text"] as? String)?.count==18000 && bounded["truncated"] as? Bool==true,"large reports return explicit bounded excerpts")
        let empty=v.makeReport();try await ready(empty);ai.open(empty)
        try check(ai.shareScript.title=="Share this report" && ai.conversations[empty.id]?.messages.isEmpty==true,"empty reports can open an independent methods conversation")
    }
}

extension ScriptAIPane { @MainActor func setSelectedEnd() { input.setSelectedRange(NSRange(location:(input.string as NSString).length,length:0)) } }
extension NSView { @MainActor func labels() -> [String] { subviews.flatMap { ($0 as? NSTextField).map { [$0.stringValue] } ?? [] } + subviews.flatMap { $0.labels() } } }
