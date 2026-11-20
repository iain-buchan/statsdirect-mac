import Cocoa
import WebKit

@main struct ScriptAITests {
    @MainActor static func check(_ ok: Bool,_ message: String) throws {
        guard ok else { throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        print("PASS: "+message);fflush(stdout)
    }
    @MainActor static func wait(file: StaticString = #fileID, line: UInt = #line, _ condition: () async throws -> Bool) async throws {
        let end=Date().addingTimeInterval(30)
        while Date()<end { if try await condition() { return };try await Task.sleep(nanoseconds:50_000_000) }
        throw NSError(domain:"ScriptAI",code:2,userInfo:[NSLocalizedDescriptionKey:"Timed out waiting for script AI at \(file):\(line)"])
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
    @MainActor static func text(_ ai: ScriptAIPane) async -> String {
        (try? await ai.transcript.web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
    }
    @MainActor static func js(_ ai: ScriptAIPane,_ source: String) async throws -> Any {
        try await ai.transcript.web.evaluateJavaScript(source) ?? NSNull()
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
        let output=root.appendingPathComponent(".build/script-ai-layout-output",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func captureLayout(_ name:String) throws {
            v.window.contentView!.layoutSubtreeIfNeeded()
            if let bitmap=ai.view.bitmapImageRepForCachingDisplay(in:ai.view.bounds) {
                ai.view.cacheDisplay(in:ai.view.bounds,to:bitmap)
                let captured=NSImage(size:ai.view.bounds.size);captured.addRepresentation(bitmap)
                let image=NSImage(size:ai.view.bounds.size,flipped:false) { rect in
                    NSColor.windowBackgroundColor.setFill();rect.fill()
                    captured.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1);return true
                }
                try NSBitmapImageRep(data:image.tiffRepresentation!)?.representation(using:.png,properties:[:])?.write(to:output.appendingPathComponent(name+".png"))
            }
        }
        func frame(_ view:NSView) -> NSRect { ai.view.convert(view.bounds,from:view) }
        func ordered(_ views:[NSView]) -> Bool {
            let frames=views.map(frame)
            return zip(frames,frames.dropFirst()).allSatisfy{$0.minY >= $1.maxY-1}
        }
        let icon=buttons(first.rPane!.view).first{$0.accessibilityLabel()=="AI assistance"}
        try check(icon != nil,"R script toolbar has an accessible AI icon")
        icon!.performClick(nil)
        try await wait { ai.visible && ai.view.window != nil }
        v.window.contentView!.layoutSubtreeIfNeeded()
        try check(ordered([ai.contextPanel,ai.input.enclosingScrollView!,ai.sendButton,ai.transcript.view]),"sharing, question, Send and conversation appear in that vertical order")
        try check(ai.scriptID==first.id && v.workspaceSplit.arrangedSubviews.count==2,"AI icon opens conversation dock beside the current script")
        try check(ai.shareScript.state == .off && ai.shareWorkbook.state == .off && !ai.sendButton.isEnabled,"sharing starts off and unsigned Send is disabled")
        try await Task.sleep(nanoseconds:150_000_000)
        try check(turns()==0 && !requests().contains{$0["method"] as? String=="thread/start"},"opening the dock sends no question, document metadata or data")
        _=try await v.chatGPTTutor.signIn();try await v.chatGPTTutor.refreshAccount()
        ai.input.string="NO_SHARING";ai.sendButton.performClick(nil)
        try await wait { (await text(ai)).contains("General R guidance") }
        try check(turns()==1,"question-only round trip excludes script and workbook names/content")
        ai.shareScript.performClick(nil);ai.shareWorkbook.performClick(nil)
        try check(!ai.sendButton.isEnabled && !ai.acknowledgement.isHidden,"sharing requires a separate no-identifiers confirmation")
        ai.input.string="DATA_TEST";ai.send()
        try check(turns()==1 && !ai.isBusy,"native Send also refuses document sharing without confirmation")
        v.window.contentView!.layoutSubtreeIfNeeded()
        try captureLayout("sharing-expanded")
        let expandedHistoryHeight=ai.transcript.view.frame.height
        ai.acknowledgement.performClick(nil)
        v.window.contentView!.layoutSubtreeIfNeeded()
        try check(ai.sendButton.isEnabled,"confirming the selected content enables Send")
        try check(ai.notice.stringValue.isEmpty,"confirming sharing clears the earlier reminder to confirm")
        try check(ai.contextPanel.isHidden && ai.contextButton.title.contains("script and R output + workbook"),"confirmation collapses the boxes into a compact sharing summary")
        try check(ai.transcript.view.frame.height > expandedHistoryHeight+60 && v.window.firstResponder === ai.input,"collapsed sharing gives the conversation more space and focuses the question")
        try check(ordered([ai.contextButton,ai.input.enclosingScrollView!,ai.sendButton,ai.transcript.view]),"the question stays below the compact sharing summary and above the conversation")
        try captureLayout("sharing-confirmed")
        ai.contextButton.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .on && ai.sendButton.isEnabled,"sharing can be reviewed without discarding confirmation")
        ai.shareWorkbook.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .on && ai.sendButton.isEnabled,"changing selected context within the same data session reuses acceptance")
        ai.shareWorkbook.performClick(nil)
        ai.sendButton.performClick(nil)
        try await wait { (await text(ai)).contains("three approved worksheet rows") }
        try check(turns()==2 && ai.acknowledgement.state == .on && ai.sendButton.isEnabled,"session acceptance remains valid for follow-up questions")
        try check(ai.contextPanel.isHidden && ai.contextButton.title.contains("Sharing:"),"reply keeps the session sharing controls collapsed")
        ai.contextButton.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .on,"compact review preserves the session acceptance")
        ai.contextButton.performClick(nil)
        try check(first.rPane!.editor.string=="PRIVATE_SCRIPT <- c(1, 2, 3)","AI reply and suggested code do not alter or run the script")
        try check((await text(ai)).contains("Shared for this question:") && ai.conversations[first.id]!.messages.contains{$0["context"]?.contains("PRIVATE_WORKBOOK")==true},"conversation records the actual shared scope locally")
        var context=ScriptAIContext(viewer:v,script:first,workbook:workbook,active:{true})
        try check(!context.tools.contains{["statsdirect_run_analysis","statsdirect_open_analysis"].contains($0["name"] as? String ?? "")},"assistant exposes only read-only tools")
        do { _=try await context.call("statsdirect_run_analysis",[:]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"AI could run an analysis"]) }
        catch let error as NSError { try check(error.localizedDescription.contains("does not allow"),"unapproved write/execute tools are refused") }
        do { _=try await context.call("statsdirect_read_data",["documentId":workbook.id,"columns":[2],"firstRow":2,"lastRow":2]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Identifier read succeeded"]) }
        catch { let detail=(error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription;try check(detail.localizedCaseInsensitiveContains("identifier"),"identifier-heading protection remains active after consent") }
        let unrelated=v.newDocument(kind:"grid",title:"NOT_SHARED",url:v.root.appendingPathComponent("Grid/index.html"))
        try check(!v.aiSharing.accepted && !ai.sendButton.isEnabled,"selecting a different data document resets acceptance")
        do { _=try await context.context();throw ChatGPTTutor.Failure(message:"Old data consent survived") }
        catch { try check(error.localizedDescription.contains("selected data document changed"),"changing data invalidates an in-flight document scope") }
        context=ScriptAIContext(viewer:v,script:first,workbook:workbook,active:{true})
        do { _=try await context.call("statsdirect_read_data",["documentId":unrelated.id]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Unapproved document read succeeded"]) }
        catch { try check(error.localizedDescription.contains("not approved"),"new or unrelated documents do not enter the approved scope") }
        first.rPane!.editor.string="CHANGED_AFTER_CONSENT <- 99"
        let snapshot=try await context.call("statsdirect_read_document",["documentId":first.id])
        try check(snapshot["script"] as? String=="PRIVATE_SCRIPT <- c(1, 2, 3)","script edits during a reply do not expand the shared snapshot")
        workbook.gridVersion+=1
        do { _=try await context.call("statsdirect_workspace",[:]);throw NSError(domain:"ScriptAI",code:1,userInfo:[NSLocalizedDescriptionKey:"Stale workbook allowed"]) }
        catch { try check(error.localizedDescription.contains("changed after confirmation"),"changed workbooks require a new sharing decision") }
        ai.input.string="Keep this unsent question."
        let large=v.makeRScript(script:String(repeating:"x",count:20000),saved:true)
        let bounded=try await ScriptAIContext(viewer:v,script:large,workbook:nil,active:{true}).call("statsdirect_read_document",["documentId":large.id])
        try check((bounded["script"] as? String)?.count==12000 && bounded["truncated"] as? Bool==true,"large scripts return explicit bounded excerpts")
        try check(ai.scriptID==large.id && ai.conversations[large.id]?.messages.isEmpty==true && ai.shareScript.state == .on,"a different script has its own conversation and inherits the session context choice")
        v.tabs.selectTabViewItem(first.item)
        try check((await text(ai)).contains("three approved worksheet rows") && ai.scriptID==first.id,"returning to a script restores its conversation")
        try check(ai.input.string=="Keep this unsent question.","switching scripts preserves the unsent question")
        v.helpPane.contents()
        try check(!ai.visible && v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"Help and AI share the right-hand dock without squeezing in a third pane")
        ai.open(first)
        try check(ai.visible && !v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"AI reopens beside the script and preserves its conversation")
        try check(ai.input.string=="Keep this unsent question.","closing and reopening the dock preserves the unsent question")
        v.window.setContentSize(NSSize(width:980,height:620));v.window.contentView!.layoutSubtreeIfNeeded()
        ai.view.layoutSubtreeIfNeeded()
        try check(ai.view.bounds.width>=340 && ai.input.enclosingScrollView!.frame.height>=80 && ai.transcript.view.frame.height>=95,"composer, context and conversation fit the minimum docked window")
        let copyFrame=frame(ai.copyCodeButton),openFrame=frame(ai.openCodeButton),replyRow=frame(ai.copyCodeButton.superview!),conversationFrame=frame(ai.transcript.view)
        // The row spaces the buttons' alignment rectangles; their frames may overlap by the bezel's margin, which differs between macOS versions.
        func aligned(_ view:NSView) -> NSRect { ai.view.convert(view.alignmentRect(forFrame:view.frame),from:view.superview) }
        try check(ai.copyCodeButton.title=="Copy R code" && ai.openCodeButton.title=="Open R code" && copyFrame.minX>=0 && aligned(ai.copyCodeButton).maxX<=aligned(ai.openCodeButton).minX
                  && openFrame.maxX<=ai.view.bounds.width && abs(copyFrame.midY-openFrame.midY)<1 && replyRow.height<=max(copyFrame.height,openFrame.height)+1
                  && (ai.view.isFlipped ? replyRow.minY>=conversationFrame.maxY : replyRow.maxY<=conversationFrame.minY),
                  "Copy R code then Open R code share one row under the conversation in the minimum docked window, as on Windows")
        let controls=ai.contextButton.superview!,controlsScroll=controls.enclosingScrollView!
        let composerBox=controls.convert(ai.input.enclosingScrollView!.bounds,from:ai.input.enclosingScrollView!)
        controls.scrollToVisible(composerBox)
        try check(controlsScroll.documentVisibleRect.contains(composerBox),"the full question box remains reachable in a short dock")
        controls.scrollToVisible(controls.convert(ai.contextPanel.bounds,from:ai.contextPanel))
        try captureLayout("short-dock")
        ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged()
        _=try await js(ai,"window.getSelection().removeAllRanges();document.getElementById('messages').scrollTop=1e9;true")
        ai.input.string="STREAM_TEST";ai.send()
        try await wait { (await text(ai)).contains("STREAM_STEP_0") }
        let history=ai.transcript.view
        func atBottom() async throws -> Bool { try await js(ai,"(()=>{const e=document.getElementById('messages');return e.scrollHeight-e.clientHeight-e.scrollTop<3})()") as? Bool == true }
        func advance(_ step:Int) async throws {
            try Data().write(to:storage.appendingPathComponent("stream-step-\(step)"))
            try await wait { (await text(ai)).contains("STREAM_STEP_\(step+1)") }
        }
        try check(try await atBottom(),"a reader at the bottom follows a growing streamed reply")
        let streamingComposerFrame=frame(ai.input.enclosingScrollView!),streamingHistoryFrame=frame(history)
        _=try await js(ai,"window.getSelection().removeAllRanges();document.getElementById('messages').scrollTop=120;true")
        let readingOrigin=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try await advance(0)
        try check(abs((try await js(ai,"document.getElementById('messages').scrollTop") as! Double)-readingOrigin)<1,"streaming preserves an earlier reading position without a selection")
        let select="""
        (()=>{const walker=document.createTreeWalker(document.getElementById('messages'),NodeFilter.SHOW_TEXT);let n;const phrase='Paired measurements, 95% confidence intervals, and Unicode α 🧪.';while(n=walker.nextNode()){const i=n.textContent.indexOf(phrase);if(i>=0){window.getSelection().setBaseAndExtent(n,i+phrase.length,n,i);return phrase;}}throw Error('Selection fixture missing')})()
        """
        let selected=try await js(ai,select) as! String
        let selectedOrigin=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try await advance(1)
        let selection=try await js(ai,"window.getSelection().toString()") as! String
        let afterSelectionTop=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try check(selection==selected && abs(afterSelectionTop-selectedOrigin)<1,"streaming preserves selected Unicode text and its reading position")
        try check(frame(ai.input.enclosingScrollView!)==streamingComposerFrame && frame(history)==streamingHistoryFrame,"reply chunks do not move the question box or conversation pane")
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        v.window.makeFirstResponder(ai.transcript.web)
        NSApp.sendAction(NSSelectorFromString("copy:"),to:ai.transcript.web,from:nil)
        try await wait { board.string(forType:.string)==selected }
        let copied=board.string(forType:.string)
        board.clearContents();board.writeObjects(saved.map { data in let item=NSPasteboardItem();for(type,value) in data {item.setData(value,forType:type)};return item })
        try check(copied==selected,"selected conversation text copies from the WebView during streaming")
        _=try await js(ai,"document.getElementById('messages').scrollTop=1e9;true")
        let selectedBottomOrigin=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try await advance(2)
        let sameSelection=try await js(ai,"window.getSelection().toString()") as! String
        let afterBottomTop=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try check(sameSelection==selected && abs(afterBottomTop-selectedBottomOrigin)<1,"an active selection suppresses following even at the bottom")
        _=try await js(ai,"window.getSelection().removeAllRanges();document.getElementById('messages').scrollTop=1e9;true")
        try await advance(3)
        try check(try await atBottom(),"following resumes when the reader clears selection and returns to the bottom")
        _=try await js(ai,select)
        _=try await js(ai,"document.getElementById('messages').scrollTop=\(readingOrigin);true")
        try Data().write(to:storage.appendingPathComponent("stream-step-4"))
        try await wait { !ai.isBusy }
        try await wait { (try? await js(ai,"!!document.querySelector('[data-code=r]:not(:disabled)')")) as? Bool == true }
        let finalSelection=try await js(ai,"window.getSelection().toString()") as! String
        let afterFinishTop=try await js(ai,"document.getElementById('messages').scrollTop") as! Double
        try check(finalSelection==selected && abs(afterFinishTop-readingOrigin)<1,"finishing the HTML reply preserves reading and selection")
        try check(try await js(ai,"getComputedStyle(document.querySelector('pre code')).fontFamily.includes('monospace')") as? Bool == true,"R code is formatted in the WebView")
        let turnsBeforeCancel=turns()
        ai.input.string="CANCEL_TEST";v.window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        try await wait {
            v.window.makeFirstResponder(ai.input)
            return ai.isFocused
        }
        let sendEvent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        NSApp.postEvent(sendEvent,atStart:false)
        do { try await wait { turns()==turnsBeforeCancel+1 } }
        catch {
            // what stood in the way of the send: the pane's notice and state, for a timeout's diagnosis
            print("DIAGNOSTIC Command-Return: turns \(turns()) (before \(turnsBeforeCancel)), focused \(ai.isFocused), busy \(ai.isBusy), account \(v.chatGPTTutor.account != nil), keyWindow is viewer \(NSApp.keyWindow === v.window), notice: \(ai.notice.stringValue)");fflush(stdout)
            throw error
        }
        try check(!first.rPane!.isRunning && first.rPane!.editor.string=="CHANGED_AFTER_CONSENT <- 99","Command-Return in the AI composer sends the question without running R")
        ai.stopButton.performClick(nil)
        try check(!ai.isBusy,"Stop cancels the assistant without stopping R")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor");ai.updateConnection()
        try check(!ai.sendButton.isEnabled && !ai.connection.isEnabled,"institutional AI policy disables connection and Send")
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        // Enforcing the policy intentionally shuts down the provider and clears
        // its account. Reconnect the fixture before testing subsequent replies.
        _ = try await v.chatGPTTutor.signIn()
        try await v.chatGPTTutor.refreshAccount()
        ai.updateConnection()
        try await checkRReplay(v,first,workbook)
        try await checkFenceLanguageReplay(v,first)
        try await checkCodeBlockMatching(v,first)
        ai.newConversation()
        try check(ai.contextPanel.isHidden,"a new conversation reuses the accepted app session")
        try check(ai.conversations[first.id]?.messages.isEmpty==true && ai.shareScript.state == .off && ai.shareWorkbook.state == .off,"New conversation removes prior context from subsequent prompts")
        let nativeMenus=NSApp.mainMenu!.items.compactMap(\.submenu)
        let menuTitles=nativeMenus.map(\.title)
        try check(menuTitles==["StatsDirect","File","Edit","Format","Data","Analysis","Graphics","Window","Help"],
                  "the macOS menu bar retains every application menu, with Window before Help")
        let file=nativeMenus.first{$0.title=="File"}!
        let close=file.items.first{$0.action==#selector(Viewer.closeTab)}!
        try check(close.keyEquivalent=="w" && close.keyEquivalentModifierMask == .command,
                  "the native File menu retains Command-W")
        v.window.makeFirstResponder(ai.input)
        try check(NSApp.sendAction(close.action!,to:close.target,from:close),"the native File menu invokes Close Document")
        try check(!ai.visible && v.documents.contains(where:{$0===first}),"Command-W closes a focused AI dock without closing the script")
        ai.open(first);v.remove(first)
        try check(!ai.visible && ai.scriptID==nil && ai.conversations[first.id]==nil,"closing a script closes its AI dock and releases its conversation")
        let content=v.window.contentView!
        content.layoutSubtreeIfNeeded()
        let tabFrame=v.documentTabScroll.frame
        let tabTopGap=content.isFlipped ? tabFrame.minY-content.bounds.minY : content.bounds.maxY-tabFrame.maxY
        let duplicateMenus=buttons(content).filter{menuTitles.contains($0.identifier?.rawValue ?? "")}
        try check((0...8).contains(tabTopGap) && tabFrame.height>0 &&
                  v.documentTabScroll.documentView === v.documentTabs &&
                  v.documentTabs.arrangedSubviews.count==v.documents.count && duplicateMenus.isEmpty,
                  "the top row in the window contains document tabs and no duplicate application menus")
        let help=nativeMenus.first{$0.title=="Help"}!
        let example=help.items.first{$0.action==#selector(Viewer.openExampleWorkbook)}!
        let helpSections=help.items.suffix(6).map{$0.isSeparatorItem ? "|" : $0.title}
        try check(helpSections==["|","Example workbook","|","Check for Updates…","|","About StatsDirect…"] && help.items.last?.action==#selector(Viewer.showAbout),"Example workbook has its own section before updates, with About last in Help")
        try check(NSApp.sendAction(example.action!,to:example.target,from:example),"the Help menu invokes the example workbook command")
        try await wait {
            guard let doc=v.active,doc.workbookName=="test.xlsx",doc.workbookID != nil else { return false }
            return (try? await doc.web.evaluateJavaScript("!!window.statsDirectGrid && statsDirectGrid.csvData().includes('PEFR')")) as? Bool==true
        }
        try check(true,"Help opens the bundled example workbook with its PEFR data")
        if CommandLine.arguments.contains("--stay-open") { v.window.setContentSize(NSSize(width:1200,height:850));ai.open(large) }
    }
    @MainActor static func checkRReplay(_ v: Viewer,_ first: Document,_ workbook: Document) async throws {
        let ai=v.scriptAI
        ai.newConversation()
        first.rPane!.editor.string="before <- c(312,242,340,388,296,254,391,402,290)\nafter <- c(300,201,232,312,220,256,328,330,231)"
        ai.shareScript.state = .on;ai.sharingChanged();if !v.aiSharing.accepted { ai.acknowledgement.performClick(nil) }
        ai.input.string="PEFR_CONTEXT";ai.sendButton.performClick(nil)
        try await wait { (await text(ai)).contains("wilcox.test") }
        let chat=ai.conversations[first.id]!,reply=chat.messages.last!,generation=chat.generation
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        func restoreBoard() { board.clearContents();board.writeObjects(saved.map { data in let item=NSPasteboardItem();for(type,value) in data {item.setData(value,forType:type)};return item }) }
        board.clearContents();ai.copyCodeButton.performClick(nil)
        let copiedReply=board.string(forType:.string) ?? "",replyBlocks=ConversationRScript.blocks(reply["text"]!).map(\.code)
        restoreBoard()
        try check(ai.copyCodeButton.isEnabled && replyBlocks.count==2 && copiedReply==replyBlocks.joined(separator:"\n\n") && copiedReply.hasPrefix("d <- before - after\n\nt.test(")
                  && copiedReply.contains("wilcox.test") && !copiedReply.contains("Then analyse") && !copiedReply.contains("AI suggestion") && !copiedReply.contains("before <- c(312"),
                  "bottom Copy R code copies the last reply's R blocks alone, a blank line between them, as on Windows")
        first.rPane!.editor.string="before <- 999\nafter <- 1"
        ai.openCodeButton.performClick(nil)
        let full=v.active!.rPane!.editor.string
        try check(full.contains("before <- c(312") && !full.contains("before <- 999") && full.contains("d <- before - after") && full.contains("wilcox.test"),"bottom Open R code uses approved source and all earlier R blocks, not later editor changes")
        try check(v.active!.rPane!.isRunning == false,"opening the complete AI suggestion does not run it")
        ai.open(first)

        ai.openCode(generation:generation,messageID:reply["id"]!,blockIndex:1)
        try check(v.active!.rPane!.editor.string==full && !v.active!.rPane!.isRunning,"per-block Open in R includes the earlier definition block and source")
        ai.open(first);ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged()
        ai.input.string="PEFR_FOLLOWUP";ai.sendButton.performClick(nil)
        try await wait { (await text(ai)).contains("length(d)==9") }
        board.clearContents();ai.copyCodeButton.performClick(nil)
        let copiedFollowUp=board.string(forType:.string)
        restoreBoard()
        try check(copiedFollowUp=="stopifnot(length(d)==9)\nmean(d)","Copy R code takes the latest reply only, without earlier replies' code")
        ai.openCodeButton.performClick(nil)
        try check(v.active!.rPane!.editor.string.contains("before <- c(312") && v.active!.rPane!.editor.string.contains("d <- before - after"),"question-only follow-up retains earlier approved R dependencies locally")
        ai.open(first)
        ai.openCode(generation:generation,messageID:reply["id"]!,blockIndex:1)
        try check(!v.active!.rPane!.editor.string.contains("length(d)==9"),"older reply excludes later follow-up code")
        ai.open(first);ai.newConversation()
        let count=v.documents.count
        ai.openCode(generation:generation,messageID:reply["id"]!,blockIndex:1)
        try check(v.documents.count==count && !ai.openCodeButton.isEnabled,"queued code click from an old conversation is rejected")
        let noticeBefore=ai.notice.stringValue
        board.clearContents();board.setString("unchanged",forType:.string);ai.copyCodeButton.performClick(nil);ai.copyLastCode()
        let afterEmpty=board.string(forType:.string),emptyNotice=ai.notice.stringValue
        restoreBoard();ai.showNotice(noticeBefore)
        try check(!ai.copyCodeButton.isEnabled && afterEmpty=="unchanged" && emptyNotice=="The last reply contains no R code block.","with no R code in the last reply Copy R code is unavailable and leaves the clipboard alone")
        let context=ScriptAIContext(viewer:v,script:nil,workbook:workbook,active:{true})
        let read=try await context.call("statsdirect_read_data",["documentId":workbook.id,"columns":[0,1],"firstRow":2,"lastRow":4])
        try check((read["rCode"] as? String)?.contains("column_1")==true && context.rData.contains("10, 20, 30"),"read_data supplies explicit R bindings from the exact bounded worksheet read")
    }

    @MainActor static func checkFenceLanguageReplay(_ v:Viewer,_ first:Document) async throws {
        let ai=v.scriptAI
        let firstCode="fence_first_r <- c(17, 23, 41)"
        let pythonCode="PYTHON_FENCE_ONLY = [101, 103, 107]"
        let selectedCode="fence_selected_third <- sum(fence_first_r)"
        let reply="""
        ```r echo=FALSE
        \(firstCode)
        ```
        ```python
        \(pythonCode)
        ```
        ```r
        \(selectedCode)
        ```
        """
        let messageID="fence-language-"+UUID().uuidString
        // Load the completed fixture through retained native conversation state,
        // just as a restored reply is rendered; keep the real WebView bridge.
        ai.conversations[first.id]!.messages.append(["id":messageID,"role":"assistant","text":reply])
        ai.open(first)
        let row="document.querySelector('[data-message-id=\""+messageID+"\"]')"
        try await wait { (try? await js(ai,"(()=>{const row=\(row);return row?.querySelectorAll('.code-block').length===3&&row.querySelectorAll('[data-code=r]:not(:disabled)').length===2})()")) as? Bool == true }
        try check(try await js(ai,"(()=>{const cards=[...\(row).querySelectorAll('.code-block')];return !!cards[0].querySelector('[data-code=r]')&&!cards[1].querySelector('[data-code=r]')&&!!cards[2].querySelector('[data-code=r]')})()") as? Bool == true,"A native-loaded r echo=FALSE, Python and plain r reply has exactly two Open in R controls on its R blocks")
        let count=v.documents.count
        _=try await js(ai,"\(row).querySelectorAll('[data-code=r]')[1].click();true")
        try await wait { v.documents.count==count+1 && v.active?.rPane != nil && v.active !== first }
        let opened=v.active!,pane=opened.rPane!,source=pane.editor.string
        try check(source.contains(firstCode) && source.hasSuffix(selectedCode+"\n") && !source.contains(pythonCode) && !source.contains("PYTHON_FENCE_ONLY"),"The second DOM Open in R click reaches the native host and selects the third fenced block, retaining earlier R context and excluding Python")
        try check(pane.editor.isEditable && !pane.isRunning,"Opening the metadata-fenced R suggestion leaves an editable script and runs nothing")
        v.remove(opened);v.tabs.selectTabViewItem(first.item);ai.open(first)
    }

    /// A click on a block's own buttons uses only the block this pane reads in the saved reply (the shared rule,
    /// Learning/code-blocks.mjs): the page's text finds the block, the reply's own text is what is copied or opened.
    @MainActor static func checkCodeBlockMatching(_ v:Viewer,_ first:Document) async throws {
        let ai=v.scriptAI
        let stepped="stepped_value <- 4"
        let tabbed="tab_fn <- function(x) {\n\tx + 1\n}"
        let python="PY_BLOCK_ONLY = [2, 3, 5]"
        // A fence four spaces under a numbered step, a Tab-indented line, another language, and a block with no closing fence.
        let reply="Steps:\n\n1. Define it:\n    ```r\n    \(stepped)\n    ```\n\n```r\n\(tabbed)\n```\n\n```python\n\(python)\n```\n\n```r\nunfinished_block <- TRUE"
        let messageID="code-blocks-"+UUID().uuidString
        ai.conversations[first.id]!.messages.append(["id":messageID,"role":"assistant","text":reply])
        ai.open(first)
        let row="document.querySelector('[data-message-id=\""+messageID+"\"]')"
        func shownBlocks() async throws { try await wait { (try? await js(ai,"(()=>{const row=\(row);return row?.querySelectorAll('.code-block').length===4&&row.querySelectorAll('[data-code=r]:not(:disabled)').length===3})()")) as? Bool == true } }
        func copyButton(_ index: Int) -> String { "\(row).querySelectorAll('.code-block')[\(index)].querySelector('[data-code=copy]')" }
        try await shownBlocks()
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        func restoreBoard() { board.clearContents();board.writeObjects(saved.map { data in let item=NSPasteboardItem();for(type,value) in data {item.setData(value,forType:type)};return item }) }
        let noticeBefore=ai.notice.stringValue
        board.clearContents();board.setString("unchanged",forType:.string)
        _=try await js(ai,copyButton(1)+".click();true")
        try await wait { (try? await js(ai,copyButton(1)+".textContent==='Copied'")) as? Bool == true }
        let copiedTab=board.string(forType:.string)
        _=try await js(ai,copyButton(2)+".click();true")
        try await wait { (try? await js(ai,copyButton(2)+".textContent==='Copied'")) as? Bool == true }
        let copiedPython=board.string(forType:.string)
        try check(copiedTab==tabbed,"Copy on a block with a Tab-indented line copies the reply's own text, tab included, and the page then says Copied")
        try check(copiedPython==python,"Copy on a block in another language copies that block")
        let count=v.documents.count
        _=try await js(ai,"\(row).querySelectorAll('[data-code=r]')[0].click();true")
        try await wait { v.documents.count==count+1 && v.active?.rPane != nil && v.active !== first }
        let opened=v.active!,source=opened.rPane!.editor.string
        try check(source.hasSuffix(stepped+"\n") && !source.contains("tab_fn") && opened.rPane!.editor.isEditable && !opened.rPane!.isRunning,
                  "Open in R on a block fenced four spaces under a numbered step opens that block for review and runs nothing")
        v.remove(opened);v.tabs.selectTabViewItem(first.item);ai.open(first)
        try await shownBlocks()
        board.clearContents();board.setString("unchanged",forType:.string);ai.showNotice("")
        _=try await js(ai,copyButton(3)+".click();true")
        try await wait { ai.notice.stringValue==ConversationRScript.unmatchedNotice }
        try await Task.sleep(nanoseconds:300_000_000)
        let label=try await js(ai,copyButton(3)+".textContent") as? String
        let afterUnmatched=board.string(forType:.string)
        ai.showNotice("")
        let before=v.documents.count
        _=try await js(ai,"\(row).querySelectorAll('[data-code=r]')[2].click();true")
        try await wait { ai.notice.stringValue==ConversationRScript.unmatchedNotice }
        let openedNothing=v.documents.count==before
        restoreBoard();ai.showNotice(noticeBefore)
        try check(afterUnmatched=="unchanged" && label=="Copy","Copy on a block the pane cannot match (no closing fence) copies nothing, says so, and the page does not say Copied")
        try check(openedNothing,"Open in R on a block the pane cannot match opens nothing and says so")
    }

}
