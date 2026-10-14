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
        try check(ordered([ai.contextPanel,ai.input.enclosingScrollView!,ai.sendButton,ai.transcript.enclosingScrollView!]),"sharing, question, Send and conversation appear in that vertical order")
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
        v.window.contentView!.layoutSubtreeIfNeeded()
        try captureLayout("sharing-expanded")
        let expandedHistoryHeight=ai.transcript.enclosingScrollView!.frame.height
        ai.acknowledgement.performClick(nil)
        v.window.contentView!.layoutSubtreeIfNeeded()
        try check(ai.sendButton.isEnabled,"confirming the selected content enables Send")
        try check(ai.notice.stringValue.isEmpty,"confirming sharing clears the earlier reminder to confirm")
        try check(ai.contextPanel.isHidden && ai.contextButton.title.contains("script and R output + workbook"),"confirmation collapses the boxes into a compact sharing summary")
        try check(ai.transcript.enclosingScrollView!.frame.height > expandedHistoryHeight+60 && v.window.firstResponder === ai.input,"collapsed sharing gives the conversation more space and focuses the question")
        try check(ordered([ai.contextButton,ai.input.enclosingScrollView!,ai.sendButton,ai.transcript.enclosingScrollView!]),"the question stays below the compact sharing summary and above the conversation")
        try captureLayout("sharing-confirmed")
        ai.contextButton.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .on && ai.sendButton.isEnabled,"sharing can be reviewed without discarding confirmation")
        ai.shareWorkbook.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .off && !ai.sendButton.isEnabled,"changing the sharing scope keeps its controls open and requires confirmation")
        ai.shareWorkbook.performClick(nil);ai.acknowledgement.performClick(nil)
        ai.sendButton.performClick(nil)
        try await wait { !ai.isBusy && ai.transcript.string.contains("three approved worksheet rows") }
        try check(turns()==2 && ai.acknowledgement.state == .off && !ai.sendButton.isEnabled,"consent applies once and must be renewed for another question")
        try check(ai.contextPanel.isHidden && ai.contextButton.title.contains("Review sharing"),"reply leaves the controls collapsed with a clear route to review the next question")
        ai.contextButton.performClick(nil)
        try check(!ai.contextPanel.isHidden && ai.acknowledgement.state == .off,"compact review control reopens the next question’s confirmation")
        ai.contextButton.performClick(nil)
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
        ai.input.string="Keep this unsent question."
        let large=v.makeRScript(script:String(repeating:"x",count:20000),saved:true)
        let bounded=try await ScriptAIContext(viewer:v,script:large,workbook:nil,active:{true}).call("statsdirect_read_document",["documentId":large.id])
        try check((bounded["script"] as? String)?.count==12000 && bounded["truncated"] as? Bool==true,"large scripts return explicit bounded excerpts")
        try check(ai.scriptID==large.id && ai.conversations[large.id]?.messages.isEmpty==true && ai.shareScript.state == .off,"a different script has its own conversation and sharing choices")
        v.tabs.selectTabViewItem(first.item)
        try check(ai.scriptID==first.id && ai.transcript.string.contains("three approved worksheet rows"),"returning to a script restores its conversation")
        try check(ai.input.string=="Keep this unsent question.","switching scripts preserves the unsent question")
        v.helpPane.contents()
        try check(!ai.visible && v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"Help and AI share the right-hand dock without squeezing in a third pane")
        ai.open(first)
        try check(ai.visible && !v.helpPane.visible && v.workspaceSplit.arrangedSubviews.count==2,"AI reopens beside the script and preserves its conversation")
        try check(ai.input.string=="Keep this unsent question.","closing and reopening the dock preserves the unsent question")
        v.window.setContentSize(NSSize(width:980,height:620));v.window.contentView!.layoutSubtreeIfNeeded()
        ai.view.layoutSubtreeIfNeeded()
        try check(ai.view.bounds.width>=340 && ai.input.enclosingScrollView!.frame.height>=80 && ai.transcript.enclosingScrollView!.frame.height>=95,"composer, context and conversation fit the minimum docked window")
        let controls=ai.contextButton.superview!,controlsScroll=controls.enclosingScrollView!
        let composerBox=controls.convert(ai.input.enclosingScrollView!.bounds,from:ai.input.enclosingScrollView!)
        controls.scrollToVisible(composerBox)
        try check(controlsScroll.documentVisibleRect.contains(composerBox),"the full question box remains reachable in a short dock")
        controls.scrollToVisible(controls.convert(ai.contextPanel.bounds,from:ai.contextPanel))
        try captureLayout("short-dock")
        ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged()
        ai.transcript.setSelectedRange(NSRange(location:ai.transcript.string.utf16.count,length:0));ai.transcript.scrollToEndOfDocument(nil)
        ai.input.string="STREAM_TEST";ai.send()
        try await wait { ai.transcript.string.contains("STREAM_STEP_0") }
        let history=ai.transcript.enclosingScrollView!,clip=history.contentView
        func atBottom() -> Bool { clip.documentVisibleRect.maxY >= ai.transcript.bounds.maxY-3 }
        func advance(_ step:Int) async throws {
            try Data().write(to:storage.appendingPathComponent("stream-step-\(step)"))
            try await wait { ai.transcript.string.contains("STREAM_STEP_\(step+1)") }
        }
        if !atBottom() { print("Scroll bounds: visible=\(clip.documentVisibleRect), document=\(ai.transcript.bounds)");fflush(stdout) }
        try check(atBottom(),"a reader at the bottom follows a growing streamed reply")
        let streamingComposerFrame=frame(ai.input.enclosingScrollView!),streamingHistoryFrame=frame(history)
        ai.transcript.setSelectedRange(NSRange(location:0,length:0))
        clip.scroll(to:NSPoint(x:0,y:120));history.reflectScrolledClipView(clip)
        let readingOrigin=clip.bounds.origin
        try await advance(0)
        try check(abs(clip.bounds.origin.y-readingOrigin.y)<1,"streaming preserves an earlier reading position without a selection")
        let selected=(ai.transcript.string as NSString).range(of:"Paired measurements, 95% confidence intervals, and Unicode α 🧪.")
        ai.transcript.setSelectedRange(selected);v.window.makeFirstResponder(ai.transcript)
        let selectedOrigin=clip.bounds.origin
        try await advance(1)
        try check(ai.transcript.selectedRange()==selected && abs(clip.bounds.origin.y-selectedOrigin.y)<1,"streaming preserves selected Unicode text and its reading position")
        try check(frame(ai.input.enclosingScrollView!)==streamingComposerFrame && frame(history)==streamingHistoryFrame,"reply chunks do not move the question box or conversation pane")
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        ai.transcript.copy(nil)
        let copied=board.string(forType:.string)
        board.clearContents();board.writeObjects(saved.map { data in let item=NSPasteboardItem();for(type,value) in data {item.setData(value,forType:type)};return item })
        try check(copied==(ai.transcript.string as NSString).substring(with:selected),"selected conversation text still copies correctly during streaming")
        ai.transcript.scrollToEndOfDocument(nil)
        let selectedBottomOrigin=clip.bounds.origin
        try await advance(2)
        try check(ai.transcript.selectedRange()==selected && abs(clip.bounds.origin.y-selectedBottomOrigin.y)<1,"an active selection suppresses following even at the bottom")
        ai.transcript.setSelectedRange(NSRange(location:ai.transcript.string.utf16.count,length:0));ai.transcript.scrollToEndOfDocument(nil)
        try await advance(3)
        try check(atBottom(),"following resumes when the reader clears selection and returns to the bottom")
        ai.transcript.setSelectedRange(selected);clip.scroll(to:readingOrigin);history.reflectScrolledClipView(clip)
        try Data().write(to:storage.appendingPathComponent("stream-step-4"))
        try await wait { !ai.isBusy }
        let codeRange=(ai.transcript.string as NSString).range(of:"mean(c(1, 2, 3))")
        let codeFont=ai.transcript.textStorage?.attribute(.font,at:codeRange.location,effectiveRange:nil) as? NSFont
        try check(ai.transcript.selectedRange()==selected && abs(clip.bounds.origin.y-readingOrigin.y)<1 && codeFont?.isFixedPitch==true,"finishing the reply preserves reading, selection and code formatting")
        let turnsBeforeCancel=turns()
        ai.input.string="CANCEL_TEST";v.window.makeKeyAndOrderFront(nil);v.window.makeFirstResponder(ai.input)
        NSApp.activate(ignoringOtherApps:true)
        try await wait { ai.isFocused }
        let sendEvent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:v.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        NSApp.postEvent(sendEvent,atStart:false)
        try await wait { turns()==turnsBeforeCancel+1 }
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
        ai.newConversation()
        try check(!ai.contextPanel.isHidden,"a new conversation shows its fresh sharing choices")
        try check(ai.conversations[first.id]?.messages.isEmpty==true && ai.shareScript.state == .off && ai.shareWorkbook.state == .off,"New conversation removes prior context from subsequent prompts")
        v.window.makeFirstResponder(ai.input);v.closeTab()
        try check(!ai.visible && v.documents.contains(where:{$0===first}),"Command-W closes a focused AI dock without closing the script")
        ai.open(first);v.remove(first)
        try check(!ai.visible && ai.scriptID==nil && ai.conversations[first.id]==nil,"closing a script closes its AI dock and releases its conversation")
        let help=NSApp.mainMenu!.items.first{$0.submenu?.title=="Help"}!.submenu!
        let lastMenus=NSApp.mainMenu!.items.suffix(2).compactMap{$0.submenu?.title}
        let menuButtons=buttons(v.window.contentView!).filter{["Window","Help"].contains($0.identifier?.rawValue ?? "")}.sorted{$0.frame.minX < $1.frame.minX}
        try check(lastMenus==["Window","Help"] && menuButtons.map{$0.identifier?.rawValue}==["Window","Help"],"Window precedes Help in both the macOS menu bar and the in-window menu row")
        let example=help.items.first{$0.action==#selector(Viewer.openExampleWorkbook)}!
        let helpSections=help.items.suffix(7).map{$0.isSeparatorItem ? "|" : $0.title}
        try check(helpSections==["|","Example workbook","|","Check for Updates…","Automatically Check for Updates","|","About StatsDirect"] && help.items.last?.action==#selector(Viewer.showAbout),"Example workbook has its own section before updates, with About last in Help")
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
        ai.shareScript.state = .on;ai.sharingChanged();ai.acknowledgement.performClick(nil)
        ai.input.string="PEFR_CONTEXT";ai.sendButton.performClick(nil)
        try await wait { !ai.isBusy && ai.transcript.string.contains("wilcox.test") }
        let chat=ai.conversations[first.id]!,reply=chat.messages.last!,generation=chat.generation
        first.rPane!.editor.string="before <- 999\nafter <- 1"
        ai.openCodeButton.performClick(nil)
        let full=v.active!.rPane!.editor.string
        try check(full.contains("before <- c(312") && !full.contains("before <- 999") && full.contains("d <- before - after") && full.contains("wilcox.test"),"bottom Open R code uses approved source and all earlier R blocks, not later editor changes")
        try check(v.active!.rPane!.isRunning == false,"opening the complete AI suggestion does not run it")
        ai.open(first)
        let link="statsdirect-r://open/"+generation+"/"+reply["id"]!+"/1"
        _=ai.textView(ai.transcript,clickedOnLink:link,at:0)
        try check(v.active!.rPane!.editor.string==full && !v.active!.rPane!.isRunning,"per-block Open in R includes the earlier definition block and source")
        ai.open(first);ai.shareScript.state = .off;ai.shareWorkbook.state = .off;ai.sharingChanged()
        ai.input.string="PEFR_FOLLOWUP";ai.sendButton.performClick(nil)
        try await wait { !ai.isBusy && ai.transcript.string.contains("length(d)==9") }
        ai.openCodeButton.performClick(nil)
        try check(v.active!.rPane!.editor.string.contains("before <- c(312") && v.active!.rPane!.editor.string.contains("d <- before - after"),"question-only follow-up retains earlier approved R dependencies locally")
        ai.open(first)
        _=ai.textView(ai.transcript,clickedOnLink:link,at:0)
        try check(!v.active!.rPane!.editor.string.contains("length(d)==9"),"older reply excludes later follow-up code")
        ai.open(first);ai.newConversation()
        let count=v.documents.count
        _=ai.textView(ai.transcript,clickedOnLink:link,at:0)
        try check(v.documents.count==count && !ai.openCodeButton.isEnabled,"queued code click from an old conversation is rejected")
        let context=ScriptAIContext(viewer:v,script:nil,workbook:workbook,active:{true})
        let read=try await context.call("statsdirect_read_data",["documentId":workbook.id,"columns":[0,1],"firstRow":2,"lastRow":4])
        try check((read["rCode"] as? String)?.contains("column_1")==true && context.rData.contains("10, 20, 30"),"read_data supplies explicit R bindings from the exact bounded worksheet read")
    }

}
