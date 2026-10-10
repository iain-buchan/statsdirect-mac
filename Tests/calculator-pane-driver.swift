import Cocoa
import WebKit

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
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--run-tests") else { print("Use Scripts/test-calculator-pane.sh"); exit(2) }
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        let v=Viewer(); app.delegate=v
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(v); print("PASS: native calculator checks"); fflush(stdout) }
                catch { print("FAIL: \(error.localizedDescription)"); fflush(stdout); exit(1) }
                if !CommandLine.arguments.contains("--stay-open") { v.closeApproved=true; app.terminate(nil) }
            }
        }
        app.run()
    }
    @MainActor static func run(_ v:Viewer) async throws {
        let c=v.calculatorPane, worksheet=v.active!, count=v.documents.count
        let deadline=Date().addingTimeInterval(20)
        while Date()<deadline, (try? await js(worksheet.web,"!!window.statsDirectGrid")) as? Bool != true { try await settle() }
        _ = try await js(worksheet.web,"statsDirectGrid.loadCSV('Before,After\\n1,2\\n3,4','Calculator selection.csv')")
        try await settle()
        _ = try await js(worksheet.web,"statsDirectGrid.editCommand('selectAll','')")
        try await settle()
        let before=try await js(worksheet.web,"JSON.stringify(statsDirectGrid.analysisSource())") as? String
        try check(!c.visible && v.documentSplit.subviews.count==1,"calculator starts hidden without a document tab")
        let menu=NSApp.mainMenu!.items.first { $0.submenu?.title=="Tools" }!.submenu!
        let command=menu.items.first { $0.title=="Calculator" }!
        try check(NSApp.sendAction(command.action!,to:command.target,from:command),"Tools → Calculator opens the pane")
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
        try check(NSPasteboard.general.string(forType:.string)=="2+\n3*4\t14","saved expressions and results copy to the clipboard")
        c.input.string="2+"; c.save(); try await until { !c.busy }
        try check(c.saved.count==1 && !c.result.string.isEmpty && c.result.textColor==NSColor.systemRed,"invalid expression is shown inline and is not saved")
        c.input.string="SQRT(81)"; c.calculate(); try await until { !c.busy }
        try check(c.result.string=="9","calculator recovers after an invalid expression")
        let long=Array(repeating:"1",count:180).joined(separator:"+")
        c.input.string=long; c.input.layoutManager?.ensureLayout(for:c.input.textContainer!)
        var lines=0
        c.input.layoutManager?.enumerateLineFragments(forGlyphRange:NSRange(location:0,length:c.input.layoutManager!.numberOfGlyphs)) { _,_,_,_,_ in lines += 1 }
        try check(lines>1 && c.input.string==long,"long expressions visually wrap without changing expression text")
        c.calculate(); try await until { !c.busy }
        try check(c.result.string=="180","wrapped expression evaluates correctly")
        c.input.string="ABC"; c.input.setSelectedRange(NSRange(location:1,length:1)); c.savedMenu.selectItem(withTag:0); c.useSaved()
        try check(c.input.string=="A2+\n3*4C","saved expression replaces selected input")
        c.input.undoManager?.undo()
        try check(c.input.string=="ABC","saved expression insertion supports Undo")
        c.input.string="2+3"; c.input.setSelectedRange(NSRange(location:1,length:1)); c.input.insertText("*",replacementRange:c.input.selectedRange())
        c.toggleMode(); try await settle()
        try check(c.view.window === c.floatingWindow && c.floatingWindow?.isVisible==true && v.documentSplit.subviews.count==1,"Pop out uses a companion window and restores document height")
        try check(c.input.string=="2*3" && c.saved.count==1 && c.result.string=="180","Pop out retains input, result and saved calculations")
        c.input.undoManager?.undo(); try check(c.input.string=="2+3","expression Undo survives reparenting")
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
        try check((try await js(v.helpPane.web,"document.body.innerText.includes('Calculator')")) as? Bool==true,"calculator opens its offline help topic")
        c.open(); v.currentMethodHelp()
        try check(v.helpPane.web.url?.path=="/basics/calculator.htm","context help targets the focused calculator")
        let originalFrame=v.window.frame
        v.window.setFrame(NSRect(origin:originalFrame.origin,size:v.window.minSize),display:true)
        v.workspaceSplit.setPosition(320,ofDividerAt:0); try await settle()
        let controls=[c.modeButton,c.calculateButton,c.saveButton,c.savedMenu,c.deleteButton,c.copyButton]
        try check(c.view.frame.width>=319 && c.inputScroll.frame.height>=45 && controls.allSatisfy { c.view.bounds.contains(c.view.convert($0.bounds,from:$0)) },"calculator controls fit the minimum window with Help docked")
        v.window.setFrame(originalFrame,display:true); try await settle()
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
