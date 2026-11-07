import Cocoa
import WebKit

// A non-editing calculator control whose focus does not depend on the system's Keyboard navigation preference.
private final class CalculatorRoutingControl: NSControl {
    override var acceptsFirstResponder: Bool { true }
}

@main struct CalculatorPaneTests {
    @MainActor static func check(_ ok:Bool,_ message:String) throws {
        guard ok else { throw NSError(domain:"CalculatorTests",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        print("PASS: " + message); fflush(stdout)
    }
    @MainActor static func settle() async throws { try await Task.sleep(nanoseconds:350_000_000) }
    @MainActor static func until(_ condition:() -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline { try await settle() }
        try check(condition(),"asynchronous calculator operation completed")
    }
    @MainActor static func js(_ web:WKWebView,_ expression:String) async throws -> Any? {
        try await web.callAsyncJavaScript("return (" + expression + ");",arguments:[:],in:nil,contentWorld:.page)
    }
    @MainActor static func key(_ pane:CalculatorPane, shift:Bool = false) {
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:shift ? [.shift] : [],timestamp:0,windowNumber:pane.view.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        pane.input.keyDown(with:event)
    }
    @MainActor static func historyCommand(_ viewer:Viewer,_ name:String = "undo") async throws {
        // Undo is a separate user event. Go through NSTextView's responder-chain
        // action so AppKit can finish text coalescing before its undo manager runs.
        try await settle()
        let command=NSMenuItem(title:name,action:#selector(Viewer.editCommand(_:)),keyEquivalent:"z")
        command.representedObject=name
        viewer.editCommand(command)
        try await settle()
    }
    @MainActor static func press(_ window:NSWindow,_ text:String,_ code:UInt16) async throws {
        for type in [NSEvent.EventType.keyDown,.keyUp] {
            let event=NSEvent.keyEvent(with:type,location:.zero,modifierFlags:.command,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
            NSApp.postEvent(event,atStart:false)
        }
        try await settle()
    }
    @MainActor static func floatingCommandRouting(_ v:Viewer,_ worksheet:Document) async throws {
        let c=v.calculatorPane, originallyFloating=c.prefersFloating
        let policy=UserDefaults.standard.object(forKey:"DisableOnlineTutor")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        let script=v.makeRScript(script:"1 + 1",title:"Calculator routing fixture",saved:true,language:"CSharp")
        let nonEditing=CalculatorRoutingControl(frame:NSRect(x:0,y:0,width:1,height:1))
        defer {
            nonEditing.removeFromSuperview()
            c.hide()
            if c.prefersFloating != originallyFloating { c.open(); c.toggleMode(); c.hide() }
            v.scriptAI.hide(); v.remove(script); v.tabs.selectTabViewItem(worksheet.item)
            if let policy { UserDefaults.standard.set(policy,forKey:"DisableOnlineTutor") }
            else { UserDefaults.standard.removeObject(forKey:"DisableOnlineTutor") }
        }
        c.open(); if !c.prefersFloating { c.toggleMode() }
        guard let floating=c.floatingWindow else { throw NSError(domain:"CalculatorTests",code:2,userInfo:[NSLocalizedDescriptionKey:"Calculator did not float for command routing"])}
        v.scriptAI.open(script)
        v.scriptAI.input.string="Background AI draft"
        v.scriptAI.input.undoManager?.removeAllActions()
        v.scriptAI.input.insertText(" continued",replacementRange:NSRange(location:19,length:0))
        v.scriptAI.input.breakUndoCoalescing()
        v.scriptAI.input.setSelectedRange(NSRange(location:0,length:10))
        let draft=v.scriptAI.input.string, selection=v.scriptAI.input.selectedRange(), documents=v.documents.count
        floating.makeKeyAndOrderFront(nil); floating.makeFirstResponder(c.input)
        try await settle()
        try check(c.isFocused && v.scriptAI.isFocused && NSApp.keyWindow === floating,"The floating calculator is key while the AI composer retains the main window's focus")
        try await press(floating,"w",13)
        try check(!c.visible && v.scriptAI.visible && v.documents.count==documents,"Close typed in the floating calculator hides only the calculator, leaving AI and documents open")
        c.open()
        c.input.breakUndoCoalescing(); c.input.string="2+"; c.input.undoManager?.removeAllActions()
        c.input.setSelectedRange(NSRange(location:2,length:0))
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("3",forType:.string)
        try await press(floating,"v",9)
        try check(c.input.string=="2+3","Paste typed in the floating calculator edits its expression")
        try await press(floating,"z",6)
        try check(c.input.string=="2+" && v.scriptAI.input.string==draft,"Undo typed in the floating calculator undoes its paste without editing the background AI draft")
        c.view.addSubview(nonEditing)
        try check(floating.makeFirstResponder(nonEditing),"A non-editing calculator control can own the floating window's focus")
        try check((NSApp.target(forAction:NSSelectorFromString("paste:"),to:nil,from:v) as AnyObject?) === v.scriptAI.input,"AppKit's unrestricted Paste search would reach the background AI composer")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("keep the background unchanged",forType:.string)
        for (text,code) in [("v",UInt16(9)),("x",7),("c",8),("a",0),("z",6)] { try await press(floating,text,code) }
        try check(v.scriptAI.input.string==draft && v.scriptAI.input.selectedRange()==selection,"Unsupported Edit shortcuts in a floating calculator control preserve the background AI text and selection")
        try check(NSPasteboard.general.string(forType:.string)=="keep the background unchanged","Unsupported Copy and Cut in the calculator leave the clipboard unchanged")
        try check(c.visible && v.scriptAI.visible && v.documents.count==documents,"Unsupported calculator Edit shortcuts leave both tools and documents open")
    }
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--run-tests") else { print("Use Scripts/test-calculator-pane.sh"); exit(2) }
        print("INFO: starting native calculator checks"); fflush(stdout)
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        let v=Viewer(); app.delegate=v
        let watchdog=DispatchWorkItem {
            let sample=Process(), trace=FileManager.default.temporaryDirectory.appendingPathComponent("calculator-timeout.txt")
            sample.executableURL=URL(fileURLWithPath:"/usr/bin/sample")
            sample.arguments=[String(ProcessInfo.processInfo.processIdentifier),"1","-file",trace.path]
            if (try? sample.run()) != nil { sample.waitUntilExit() }
            if let output=try? String(contentsOf:trace,encoding:.utf8) { print(output) }
            print("FAIL: native calculator checks exceeded 120 seconds"); fflush(stdout); exit(1)
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+120,execute:watchdog)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(v); print("PASS: native calculator checks"); fflush(stdout) }
                catch { print("FAIL: \(error.localizedDescription)"); fflush(stdout); exit(1) }
                watchdog.cancel()
                if !CommandLine.arguments.contains("--stay-open") { v.closeApproved=true; app.terminate(nil) }
            }
        }
        app.run()
    }
    @MainActor static func run(_ v:Viewer) async throws {
        print("INFO: native calculator assertions started"); fflush(stdout)
        let general=NSPasteboard.general
        let clipboard=(general.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy=NSPasteboardItem()
            for type in item.types { if let data=item.data(forType:type) { copy.setData(data,forType:type) } }
            return copy
        }
        defer { general.clearContents(); if !clipboard.isEmpty { general.writeObjects(clipboard) } }
        let c=v.calculatorPane, worksheet=v.active!, count=v.documents.count
        let deadline=Date().addingTimeInterval(20)
        while Date()<deadline, (try? await js(worksheet.web,"!!window.statsDirectGrid")) as? Bool != true { try await settle() }
        _ = try await js(worksheet.web,"statsDirectGrid.loadCSV('Before,After\\n1,2\\n3,4','Calculator selection.csv')")
        try await settle()
        _ = try await js(worksheet.web,"statsDirectGrid.editCommand('selectAll','')")
        try await settle()
        let before=try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())") as? String
        try check(!c.visible && v.documentSplit.subviews.count==1,"calculator starts hidden without a document tab")
        let menu=NSApp.mainMenu!.items.first { $0.submenu?.title=="Analysis" }!.submenu!
        try check(menu.items.suffix(4).map { $0.isSeparatorItem ? "separator" : $0.title } == ["separator","Calculator","separator","Options"],"Analysis ends with separated Calculator and Options commands")
        let options=menu.items.filter { $0.representedObject as? String=="AnalysisOptions" }
        try check(options.count==1 && options[0].action == #selector(Viewer.openAnalysisOperation(_:)) && options[0].target === v,"Analysis Options keeps its operation identity and action")
        let command=menu.items.first { $0.title=="Calculator" }!
        try check(NSApp.sendAction(command.action!,to:command.target,from:command),"Analysis → Calculator opens the pane")
        try await settle()
        try check(c.visible && c.view.superview === v.documentSplit && v.documentSplit.subviews.count==2,"calculator docks beneath the document")
        try check(v.active === worksheet && v.documents.count==count,"calculator leaves active document and tabs unchanged")
        try check(v.window.firstResponder === c.input,"explicit opening focuses expression input")
        c.input.string="2+3*4"; key(c); try await until { !c.busy }
        try check(c.result.string=="14" && c.input.string=="2+3*4","Enter uses the original engine without inserting a newline")
        c.input.setSelectedRange(NSRange(location:(c.input.string as NSString).length,length:0)); key(c,shift:true)
        try check(c.input.string=="2+3*4\n" && !c.busy,"Shift+Enter inserts a real newline without calculating")
        c.input.string="2+\n3*4"; c.save(); try await until { !c.busy }
        try check(c.saved.count==1 && c.saved[0].expression=="2+\n3*4" && c.saved[0].result=="14","Save calculates and preserves the exact multiline expression")
        c.copySaved()
        try check(NSPasteboard.general.string(forType:.string)=="2+ 3*4 = 14","Copy saved matches Windows, with one expression/result per line")
        c.copyResult(); try check(NSPasteboard.general.string(forType:.string)=="14","Copy result copies only the evaluated answer")
        c.input.string="2+"; c.save(); try await until { !c.busy }
        try check(c.saved.count==1 && !c.result.string.isEmpty && c.result.textColor==NSColor.systemRed,"invalid expression is shown inline and is not saved")
        try check(!c.copyResultButton.isEnabled,"a failed evaluation cannot copy a stale answer")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("unchanged",forType:.string); c.copyResult()
        try check(NSPasteboard.general.string(forType:.string)=="unchanged","Copy result ignores an invalid calculation")
        c.input.string="SQRT(81)"; c.calculate(); try await until { !c.busy }
        try check(c.result.string=="9","calculator recovers after an invalid expression")
        let long=Array(repeating:"1",count:180).joined(separator:"+")
        c.input.string=long; c.input.layoutManager?.ensureLayout(for:c.input.textContainer!)
        var lines=0
        c.input.layoutManager?.enumerateLineFragments(forGlyphRange:NSRange(location:0,length:c.input.layoutManager!.numberOfGlyphs)) { _,_,_,_,_ in lines += 1 }
        try check(lines>1 && c.input.string==long,"long expressions visually wrap without changing expression text")
        c.calculate(); try await until { !c.busy }
        try check(c.result.string=="180","wrapped expression evaluates correctly")
        // Earlier arithmetic cases assign text directly, bypassing NSTextView's
        // undo registration. Start a fresh baseline before testing real edits.
        c.input.breakUndoCoalescing(); c.input.string="ABC"; c.input.undoManager?.removeAllActions()
        c.input.setSelectedRange(NSRange(location:1,length:1)); c.savedMenu.selectItem(withTag:0); c.selectionChanged()
        try check(c.input.string=="ABC" && c.recallButton.isEnabled && c.insertButton.isEnabled,"choosing a saved calculation does not modify the expression")
        c.useSaved()
        try check(c.input.string=="A2+\n3*4C","saved expression replaces selected input")
        try check(c.result.string.isEmpty && !c.copyResultButton.isEnabled,"editing an expression clears its old result")
        try await historyCommand(v)
        try check(c.input.string=="ABC","saved expression insertion supports Undo")
        try await historyCommand(v,"redo")
        try check(c.input.string=="A2+\n3*4C" && c.result.string.isEmpty,"Edit menu Redo restores insertion without a stale result")
        try await historyCommand(v)
        try check(c.input.string=="ABC","Edit menu Undo works again after Redo")
        c.recallSaved()
        try check(c.input.string=="2+\n3*4" && c.result.string=="14" && c.copyResultButton.isEnabled,"Recall restores the entire saved expression and result")
        try await historyCommand(v); try check(c.input.string=="ABC" && c.result.string.isEmpty,"Recall is undoable without leaving a stale answer")
        c.input.breakUndoCoalescing(); c.input.string="2+3"; c.input.undoManager?.removeAllActions()
        c.input.setSelectedRange(NSRange(location:1,length:1)); c.input.insertText("*",replacementRange:c.input.selectedRange())
        c.calculate(); try await until { !c.busy }
        let caret=c.input.selectedRange()
        c.toggleMode(); try await settle()
        try check(c.view.window === c.floatingWindow && c.floatingWindow?.isVisible==true && v.documentSplit.subviews.count==1,"Pop out uses a companion window and restores document height")
        try check(c.input.string=="2*3" && c.saved.count==1 && c.result.string=="6" && c.input.selectedRange()==caret,"Pop out retains input, result, caret and saved calculations")
        try await historyCommand(v); try check(c.input.string=="2+3","expression Undo survives reparenting")
        c.toggleMode(); try await settle()
        try check(c.view.superview === v.documentSplit && c.floatingWindow?.isVisible==false,"Dock returns calculator beneath the document")
        v.documentSplit.setPosition(v.documentSplit.bounds.height-280,ofDividerAt:0); try await settle()
        let height=c.view.frame.height
        c.hide(); c.open(); try await settle()
        try check(abs(c.view.frame.height-height)<3,"docked height survives Close/reopen")
        c.toggleMode(); c.hide(); c.open(); try await settle()
        try check(c.prefersFloating && c.view.window === c.floatingWindow,"chosen floating mode survives Close/reopen")
        c.toggleMode(); v.calculatorHelp(); try await settle()
        try check(v.helpPane.visible && v.workspaceSplit.subviews.count==2 && c.view.superview === v.documentSplit,"Calculator and right-hand Help can both be docked")
        try await until { v.helpPane.web.url?.path=="/basics/calculator.htm" && !v.helpPane.web.isLoading }
        try check((try await js(v.helpPane.web,"['Analysis > Calculator','selected from the Analysis menu','Shift+Enter','Recall','Copy saved'].every(s=>document.body.innerText.includes(s)) && !document.body.innerText.includes('Tools > Calculator')")) as? Bool==true,"calculator opens the updated offline help topic with the Mac menu location")
        c.open(); v.currentMethodHelp()
        try check(v.helpPane.web.url?.path=="/basics/calculator.htm","context help targets the focused calculator")
        let originalFrame=v.window.frame
        c.input.string=long
        v.window.setFrame(NSRect(origin:originalFrame.origin,size:v.window.minSize),display:true)
        v.workspaceSplit.setPosition(320,ofDividerAt:0); try await settle()
        let controls=[c.modeButton,c.calculateButton,c.saveButton,c.copyResultButton,c.savedMenu,c.recallButton,c.insertButton,c.deleteButton,c.copyButton]
        try check(c.view.frame.width>=319 && c.inputScroll.frame.height>=45 && controls.allSatisfy { c.view.bounds.contains(c.view.convert($0.bounds,from:$0)) },"calculator controls fit the minimum window with Help docked")
        c.input.layoutManager!.ensureLayout(for:c.input.textContainer!)
        let narrowHeight=c.input.layoutManager!.usedRect(for:c.input.textContainer!).height
        v.window.setFrame(originalFrame,display:true); try await settle()
        c.input.layoutManager!.ensureLayout(for:c.input.textContainer!)
        try check(c.input.layoutManager!.usedRect(for:c.input.textContainer!).height<narrowHeight && c.input.string==long,"wrapping layout shrinks after changing from narrow to wide")
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:150),styleMask:[.titled],backing:.buffered,defer:false)
        let field=NSTextField(frame:NSRect(x:20,y:60,width:240,height:25)); sheet.contentView!.addSubview(field)
        v.window.beginSheet(sheet,completionHandler:nil); sheet.makeFirstResponder(field)
        let responder=sheet.firstResponder, originalKey=NSApp.keyWindow
        c.refreshModalPresentation(); v.helpPane.refreshModalPresentation(); try await settle()
        try check(c.temporarilyFloating && c.view.window === c.floatingWindow && v.helpPane.temporarilyFloating,"both tools float temporarily during parameter dialogs")
        try check(sheet.firstResponder === responder && NSApp.keyWindow === originalKey,"automatic floating does not steal parameter input focus")
        try check(!c.modeButton.isEnabled && c.floatingWindow?.worksWhenModal==true,"floating calculator works during modal dialogs with Dock disabled")
        v.window.endSheet(sheet); sheet.orderOut(nil); c.refreshModalPresentation(); v.helpPane.refreshModalPresentation(); try await settle()
        try check(c.view.superview === v.documentSplit && !c.temporarilyFloating,"calculator returns to its chosen mode after the dialog")
        try await floatingCommandRouting(v,worksheet)
        let after=try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())") as? String
        try check(before==after && v.active === worksheet,"calculation, docking and Help preserve worksheet data and selection")
        c.open(); c.deleteSaved(); try check(c.saved.isEmpty,"saved entry can be deleted")
        v.closeTab(); try check(!c.visible && v.documents.count==count,"Close while calculator is focused hides it without closing the worksheet")
        for doc in v.documents { v.remove(doc) }
        c.open()
        let close=NSMenuItem(title:"Close",action:#selector(Viewer.closeTab),keyEquivalent:"")
        let edit=NSMenuItem(title:"Select All",action:#selector(Viewer.editCommand(_:)),keyEquivalent:""); edit.representedObject="selectAll"
        try check(v.validateMenuItem(close) && v.validateMenuItem(edit),"calculator editing and Close work with no document open")
        c.input.string="2+3"; v.editCommand(edit)
        try check(c.input.selectedRange().length==3,"Edit menu targets calculator input")
        v.closeTab(); try check(!c.visible,"Close hides calculator when it is the only open content")
        if CommandLine.arguments.contains("--stay-open") { v.newWorksheet(); c.open() }
    }
}
