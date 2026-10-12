import Cocoa
import WebKit

@main struct UnifiedToolbarChecks {
    @MainActor static func check(_ value: Bool, _ reason: String) throws {
        guard value else { throw NSError(domain:"ToolbarChecks",code:1,userInfo:[NSLocalizedDescriptionKey:reason]) }
        print("PASS: " + reason); fflush(stdout)
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 { if try await condition() { return }; try await Task.sleep(nanoseconds:100_000_000) }
        throw NSError(domain:"ToolbarChecks",code:2,userInfo:[NSLocalizedDescriptionKey:"UI did not settle"])
    }
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        let viewer=Viewer(); app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: unified toolbar checks completed"); fflush(stdout) }
                catch { print("FAIL: \(error.localizedDescription)"); fflush(stdout); exit(1) }
                viewer.closeApproved=true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+90) { print("FAIL: toolbar checks timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let common=["save","undo","redo","cut","copy","paste","find"]
        let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func snapshot(_ web: WKWebView,_ name: String) async throws {
            let image=try await web.takeSnapshot(configuration:nil)
            let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        func js(_ doc: Document,_ script: String) async throws -> Any? { try await doc.web.evaluateJavaScript(script) }
        func click(_ doc: Document,_ command: String) async throws {
            _=try await js(doc,"(()=>{const b=document.querySelector('[data-command=\(command)]');b.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));b.click();})()")
        }
        func fit(_ doc:Document) async throws {
            try check(try await js(doc,"(()=>{const row=document.querySelector('.sd-toolbar-row'),box=row.getBoundingClientRect();return [...row.children].filter(x=>!x.hidden&&getComputedStyle(x).display!=='none').every(x=>{const r=x.getBoundingClientRect();return r.left>=box.left-1&&r.right<=box.right+1&&r.top>=box.top-1&&r.bottom<=box.bottom+1;});})()") as? Bool == true,"\(doc.kind) toolbar fits one row")
        }
        let report=v.makeReport()
        report.reportEntries=[ReportEntry(id:"toolbar-test",title:"Paired comparison",operation:"",body:"<h2>Paired comparison</h2><p id='selection'>Preserve this selection for formatting.</p><table><tr><th>Mean difference</th><th>95% CI</th></tr><tr><td>12.50</td><td>8.10 to 16.90</td></tr></table>",record:nil)]
        v.renderReport(report)
        try await wait { (try? await js(report,"!!window.StatsDirectToolbar && !!document.querySelector('[data-command=save]')")) as? Bool == true }
        v.window.setContentSize(NSSize(width:1180,height:800));v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:200_000_000)
        let order=try await js(report,"[...document.querySelector('.sd-toolbar-row').children].filter(x=>x.dataset.command).map(x=>x.dataset.command).slice(0,7)") as? [String]
        try check(order==common,"report common command order")
        try await fit(report);try await snapshot(report.web,"report-wide")
        _=try await js(report,"(()=>{const p=document.getElementById('selection');p.closest('.report-body').focus();const r=document.createRange();r.selectNodeContents(p);getSelection().removeAllRanges();getSelection().addRange(r);})()")
        // Docked panes can leave a document narrower than the main window minimum.
        v.helpLibrary();v.workspaceSplit.setPosition(380,ofDividerAt:0);v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:250_000_000)
        try await fit(report)
        _=try await js(report,"document.getElementById('report-more-toggle').click()")
        try check(try await js(report,"!document.getElementById('report-more-tools').hidden && !!document.querySelector('.sd-toolbar-overflow [data-command=bold]')") as? Bool == true,"report formatting moves to accessible More")
        try await click(report,"bold")
        try await wait { report.reportUndo.count==1 }
        try check(try await js(report,"(()=>{const p=document.getElementById('selection');return p.textContent==='Preserve this selection for formatting.'&&!!p.querySelector('b,strong,span[style]');})()") as? Bool == true,"formatting in More retains the selected report text")
        try await snapshot(report.web,"report-narrow-more")
        _=try await js(report,"document.getElementById('report-more-toggle').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")
        try check(try await js(report,"document.getElementById('report-more-tools').hidden && document.activeElement.id==='report-more-toggle'") as? Bool == true,"Escape closes More and returns keyboard focus")
        try await click(report,"undo");try await wait { report.reportUndo.isEmpty }
        v.helpPane.hide();v.window.contentView!.layoutSubtreeIfNeeded()
        try await click(report,"find")
        try check(report.findBar?.isHidden==false,"report Find uses the native find bar")
        v.hideFindBar(report)
        try await click(report,"save")
        try await wait { v.window.attachedSheet is NSSavePanel }
        (v.window.attachedSheet as? NSSavePanel)?.cancel(nil)
        try await wait { v.window.attachedSheet == nil }
        try check(true,"report toolbar opens the existing save/export panel")

        v.newWorksheet();let grid=v.active!
        try await wait { (try? await js(grid,"!!window.statsDirectGrid && !!document.querySelector('.sd-toolbar')")) as? Bool == true }
        _=try await js(grid,"window.statsDirectGrid.applyWorkbook({name:'Toolbar.xlsx',sheets:[{name:'Sheet1',rows:100,columns:8,cells:[{col:0,row:0,text:'Alpha',kind:'text'},{col:1,row:0,text:'12.50',kind:'number'},{col:0,row:1,text:'Beta',kind:'text'}]}]})")
        try await Task.sleep(nanoseconds:100_000_000)
        let gridOrder=try await js(grid,"[...document.querySelector('.sd-toolbar-row').children].map(x=>x.dataset.command).slice(0,7)") as? [String]
        try check(gridOrder==common,"worksheet common command order")
        try await fit(grid)
        _=try await js(grid,"window.statsDirectGrid.editCommand('cut','')")
        try await Task.sleep(nanoseconds:150_000_000)
        try check(try await js(grid,"window.statsDirectGrid.csvData().includes('Alpha')") as? Bool == true,"Cut without a worksheet selection leaves cells unchanged")
        try await click(grid,"find")
        try await wait { (try? await js(grid,"document.activeElement.id==='grid-find-text'")) as? Bool == true }
        _=try await js(grid,"(()=>{const input=document.getElementById('grid-find-text');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(input,'beta');input.dispatchEvent(new Event('input',{bubbles:true}));})()")
        try await Task.sleep(nanoseconds:100_000_000)
        _=try await js(grid,"[...document.querySelectorAll('.grid-find button')].find(b=>b.textContent==='Next').click()")
        try await wait { (try? await js(grid,"document.querySelector('.formula label').textContent==='A2'")) as? Bool == true }
        try check(true,"worksheet Find selects the matching cell")
        _=try await js(grid,"document.querySelector('[aria-label=\"Close Find\"]').click();window.statsDirectGrid.editCommand('selectAll','')")
        try await Task.sleep(nanoseconds:100_000_000)
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.reduce(into:[NSPasteboard.PasteboardType:Data]()){$0[$1]=item.data(forType:$1)} } ?? []
        defer {board.clearContents();board.writeObjects(saved.map { data in let i=NSPasteboardItem();for(t,d) in data {i.setData(d,forType:t)};return i})}
        try await click(grid,"cut")
        try await wait { (try? await js(grid,"window.statsDirectGrid.csvData().includes('Alpha')")) as? Bool == false }
        try check(board.string(forType:.string)?.contains("12.50")==true,"worksheet Cut preserves numeric text on the native clipboard")
        try await click(grid,"undo")
        try await wait { (try? await js(grid,"window.statsDirectGrid.csvData().includes('Alpha')")) as? Bool == true }
        try check(true,"worksheet Cut uses the existing undo history")
        // A native clipboard reply can arrive after another edit. Keep the
        // original cells when the captured worksheet revision is no longer current.
        _=try await js(grid,"document.querySelector('[data-command=cut]').click();window.statsDirectGrid.setCellText({col:2,row:3,text:'intervening edit'})")
        try await wait { (try? await js(grid,"document.querySelector('footer').textContent.includes('no cells were cleared')")) as? Bool == true }
        try check(try await js(grid,"window.statsDirectGrid.csvData().includes('Alpha') && window.statsDirectGrid.csvData().includes('intervening edit')") as? Bool == true,"delayed Cut acknowledgement preserves intervening worksheet edits")
        try await snapshot(grid.web,"worksheet-wide")
        v.helpLibrary();v.workspaceSplit.setPosition(330,ofDividerAt:0);v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:200_000_000);try await fit(grid)
        try await click(grid,"more")
        try check(try await js(grid,"!document.getElementById('grid-more-tools').hidden && !!document.querySelector('.sd-toolbar-overflow [data-command=addColumn]')") as? Bool == true,"worksheet secondary commands move into More")
        try await click(grid,"addColumn")
        try await wait { (try? await js(grid,"document.querySelector('footer').textContent.includes('9 columns')")) as? Bool == true }
        try check(true,"worksheet More invokes the live command")
        v.helpPane.hide();v.window.contentView!.layoutSubtreeIfNeeded()
        grid.csvSaveName="Toolbar.csv"
        try await click(grid,"save")
        try await wait { v.window.attachedSheet is NSSavePanel }
        try check((v.window.attachedSheet as? NSSavePanel)?.nameFieldStringValue.hasSuffix(".csv")==true,"worksheet Save preserves the document's CSV format")
        (v.window.attachedSheet as? NSSavePanel)?.cancel(nil)
        try await wait { v.window.attachedSheet == nil }
    }
}
