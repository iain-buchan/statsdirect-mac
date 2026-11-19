import Cocoa
import WebKit

@main struct UnifiedToolbarChecks {
    @MainActor static func check(_ value: Bool, _ reason: String) throws {
        guard value else { throw NSError(domain:"ToolbarChecks",code:1,userInfo:[NSLocalizedDescriptionKey:reason]) }
        print("PASS: " + reason); fflush(stdout)
    }
    @MainActor static func wait(_ reason: String = "UI did not settle", _ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 { if try await condition() { return }; try await Task.sleep(nanoseconds:100_000_000) }
        throw NSError(domain:"ToolbarChecks",code:2,userInfo:[NSLocalizedDescriptionKey:reason])
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
        DispatchQueue.global().asyncAfter(deadline:.now()+120) { print("FAIL: toolbar checks timed out"); fflush(stdout); exit(1) }
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
        func scrollReport(_ doc:Document, toEnd:Bool) async throws {
            _=try await js(doc,toEnd ? "window.scrollTo(0,document.scrollingElement.scrollHeight)" : "window.scrollTo(0,900)")
            try await Task.sleep(nanoseconds:100_000_000)
            try check(try await js(doc,"(()=>{const bar=document.getElementById('report-toolbar'),r=bar.getBoundingClientRect(),save=bar.querySelector('[data-command=save]').getBoundingClientRect();return window.scrollY>500&&Math.abs(r.top)<1&&r.bottom<innerHeight&&bar.contains(document.elementFromPoint(save.left+save.width/2,save.top+save.height/2));})()") as? Bool == true,toEnd ? "report toolbar stays visible and usable at the end of a long report" : "report toolbar stays visible and usable in the middle of a long report")
        }
        let report=v.makeReport()
        report.reportEntries=[ReportEntry(id:"toolbar-test",title:"Paired comparison",operation:"",body:"<h2>Paired comparison</h2><p id='selection'>Preserve this selection for formatting.</p><table><tr><th>Mean difference</th><th>95% CI</th></tr><tr><td>12.50</td><td>8.10 to 16.90</td></tr></table><p style='margin-top:2400px'>End of the long report.</p>",record:nil)]
        v.renderReport(report)
        try await wait { (try? await js(report,"!!window.StatsDirectToolbar && !!document.querySelector('[data-command=save]')")) as? Bool == true }
        v.window.setContentSize(NSSize(width:1180,height:800));v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:200_000_000)
        let order=try await js(report,"[...document.querySelector('.sd-toolbar-row').children].filter(x=>x.dataset.command).map(x=>x.dataset.command).slice(0,7)") as? [String]
        try check(order==common,"report common command order")
        try await fit(report);try await snapshot(report.web,"report-wide")
        try await scrollReport(report,toEnd:false)
        try await scrollReport(report,toEnd:true)
        try await snapshot(report.web,"report-scrolled")
        _=try await js(report,"window.scrollTo(0,0)")
        _=try await js(report,"(()=>{const p=document.getElementById('selection');p.closest('.report-body').focus();const r=document.createRange();r.selectNodeContents(p);getSelection().removeAllRanges();getSelection().addRange(r);})()")
        // Docked panes can leave a document narrower than the main window minimum.
        v.helpLibrary();v.workspaceSplit.setPosition(380,ofDividerAt:0);v.window.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:250_000_000)
        try await fit(report)
        try await scrollReport(report,toEnd:true)
        _=try await js(report,"document.getElementById('report-more-toggle').click()")
        try check(try await js(report,"!document.getElementById('report-more-tools').hidden && !!document.querySelector('.sd-toolbar-overflow [data-command=bold]')") as? Bool == true,"report formatting moves to accessible More")
        try check(try await js(report,"(()=>{const menu=document.getElementById('report-more-tools'),r=menu.getBoundingClientRect(),bar=document.getElementById('report-toolbar').getBoundingClientRect();return r.top>=bar.bottom&&r.bottom<=innerHeight&&menu.contains(document.elementFromPoint(r.left+10,r.top+10));})()") as? Bool == true,"report More popup remains visible and usable while scrolled with a dock open")
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
        try check(try await js(grid,"""
            (()=>{const more=document.querySelector('[data-command=more]');more.click();
                const popup=document.getElementById('grid-more-tools');
                return !more.hidden&&getComputedStyle(more).display!=='none'&&!popup.hidden&&
                    ['addRows','addColumn'].every(id=>popup.querySelector(`[data-command=${id}]`))&&
                    !document.querySelector('.sd-toolbar-row [data-command=addRows],.sd-toolbar-row [data-command=addColumn]');})()
            """) as? Bool == true,"worksheet More always keeps Add 100 rows and Add column off the normal toolbar")
        try await click(grid,"addRows")
        try await wait { (try? await js(grid,"document.querySelector('footer').textContent.includes('200 rows')")) as? Bool == true }
        try await click(grid,"undo")
        try await wait { (try? await js(grid,"document.querySelector('footer').textContent.includes('100 rows')")) as? Bool == true }
        try check(true,"Add 100 rows remains available in More and uses worksheet undo")
        _=try await js(grid,"if(!document.getElementById('grid-more-tools').hidden)document.querySelector('[data-command=more]').click()")
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
        try check(try await js(grid,"getComputedStyle(document.querySelector('[data-command=more]')).display!=='none' && !document.getElementById('grid-more-tools').hidden && ['addRows','addColumn'].every(id=>document.querySelector('#grid-more-tools [data-command='+id+']')) && !document.querySelector('.sd-toolbar-row [data-command=addRows],.sd-toolbar-row [data-command=addColumn]')") as? Bool == true,"worksheet More retains Add 100 rows and Add column alongside overflow in a narrow view")
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
        try await worksheetTools(v, grid: grid, js: js, click: click, fit: fit, snapshot: snapshot)
    }

    @MainActor static func worksheetTools(_ v: Viewer, grid: Document,
        js: (Document, String) async throws -> Any?,
        click: (Document, String) async throws -> Void,
        fit: (Document) async throws -> Void,
        snapshot: (WKWebView, String) async throws -> Void) async throws {
        v.window.setContentSize(NSSize(width:1180,height:800))
        v.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        v.tabs.selectTabViewItem(grid.item)
        v.window.contentView!.layoutSubtreeIfNeeded()
        _=try await grid.web.callAsyncJavaScript("""
            await statsDirectGrid.loadWorkbook({name:'Toolbar selection',sheets:[{name:'Measurements',rows:100,columns:8,headerRow:true,cells:[
                {col:0,row:0,text:'Before',kind:'text'},{col:1,row:0,text:'After',kind:'text'},
                ...[1201,1202,1203,1204].map((n,i)=>({col:0,row:i+1,text:String(n),kind:'number'})),
                ...[8001,8002,8003,8004].map((n,i)=>({col:1,row:i+1,text:String(n),kind:'number'})),
                {col:5,row:99,text:'999999',kind:'number'}]}]});return true;
            """, arguments:[:],in:nil,contentWorld:.page)
        try await wait { (try? await js(grid,"statsDirectGrid.analysisSource().name==='Toolbar selection / Measurements'")) as? Bool == true }
        v.window.makeFirstResponder(grid.web)
        try await wait {
            guard v.window.isKeyWindow && NSApp.isActive else { return false }
            return (try? await js(grid,"document.hasFocus()")) as? Bool == true
        }
        // A rectangle gesture selects A/B, rows 2–4. Searching for a command
        // must preserve this source range instead of analysing entire columns.
        _=try await grid.web.callAsyncJavaScript("""
            await new Promise(resolve=>setTimeout(resolve,100));
            const b=document.querySelector('canvas').getBoundingClientRect(),x=c=>b.x+48+c*178+89,y=r=>b.y+36+r*29+14;
            const send=(type,c,r,buttons,shiftKey=false)=>{
                const target=document.elementFromPoint(x(c),y(r));if(!target)throw new Error('Worksheet selection has no hit target');
                target.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,clientX:x(c),clientY:y(r),button:0,buttons,shiftKey}));
            };
            send('mousemove',0,1,0);send('mousedown',0,1,1);await new Promise(resolve=>setTimeout(resolve,65));send('mouseup',0,1,0);
            send('mousedown',1,3,1,true);await new Promise(resolve=>setTimeout(resolve,65));send('mouseup',1,3,0,true);return true;
            """, arguments:[:],in:nil,contentWorld:.page)
        let selected="(()=>{const s=statsDirectGrid.analysisSource();return JSON.stringify(s.selection)==='[0,1]'&&s.range?.first===2&&s.range?.last===4})()"
        try await wait("Worksheet gesture did not select A/B, rows 2–4") { (try? await js(grid,selected)) as? Bool == true }
        try await fit(grid)
        try check(try await js(grid,"document.querySelector('[data-command=analyse]').textContent.trim()==='Analyse' && !!document.querySelector('[data-command=worksheetHelp]') && !!document.querySelector('[data-command=worksheetR]')") as? Bool == true,"worksheet exposes labelled Analyse, Help and R commands")

        let originalCount=v.documents.count
        try await click(grid,"analyse")
        try await wait("Analyse chooser did not populate or focus search") { (try? await js(grid,"document.activeElement.id==='worksheet-analysis-search'&&document.querySelectorAll('[data-worksheet-command]').length>0")) as? Bool == true }
        // Read the native hierarchy independently of the chooser's backing
        // records. Compare every branch and leaf, even those hidden by a
        // collapsed ancestor, with Analysis first and Data/Graphics following.
        var nativeRows=[[String:Any]]()
        func append(_ menu: NSMenu, _ path:[String]) {
            for item in menu.items {
                if let submenu=item.submenu {
                    nativeRows.append(["kind":"branch","id":"","label":item.title,"path":path.joined(separator:" › "),"disabled":false])
                    append(submenu,path+[item.title]); continue
                }
                let id=item.representedObject as? String ?? (item.action == #selector(Viewer.showCalculator) ? "calculator" : nil)
                guard let id else { continue }
                let disabled=id != "calculator" && (v.analysisCatalog[id] == nil || v.analysisCatalog[id]?["unavailable"] != nil)
                nativeRows.append(["kind":"leaf","id":id,"label":item.title,"path":path.joined(separator:" › "),"disabled":disabled])
            }
        }
        for title in ["Analysis","Data","Graphics"] {
            if let menu=NSApp.mainMenu!.items.first(where:{$0.submenu?.title == title})?.submenu {
                nativeRows.append(["kind":"branch","id":"","label":title,"path":"","disabled":false])
                append(menu,[title])
            }
        }
        let chooserRows=try await js(grid,"""
            (()=>{const tree=document.getElementById('worksheet-analysis-results');
                return [...tree.querySelectorAll('[role=treeitem]')].map(node=>{
                    const ancestors=[];let parent=node.parentElement.closest('[data-worksheet-branch]');
                    while(parent){ancestors.unshift(parent.querySelector(':scope > .worksheet-tree-row .worksheet-tree-label').textContent);parent=parent.parentElement.closest('[data-worksheet-branch]');}
                    return {kind:node.hasAttribute('data-worksheet-branch')?'branch':'leaf',id:node.dataset.worksheetCommand||'',
                        label:node.querySelector(':scope > .worksheet-tree-row .worksheet-tree-label').textContent,
                        path:ancestors.join(' › '),disabled:node.getAttribute('aria-disabled')==='true'};
                });})()
            """) as? [[String:Any]] ?? []
        try check(!nativeRows.isEmpty && NSArray(array:chooserRows).isEqual(to:nativeRows),"Analyse tree preserves the complete native hierarchy, labels, order and availability (\(chooserRows.count) tree nodes, \(nativeRows.count) native nodes)")
        try check(try await js(grid,"""
            (()=>{const tree=document.getElementById('worksheet-analysis-results'),nodes=[...tree.querySelectorAll('[role=treeitem]')],branches=[...tree.querySelectorAll('[data-worksheet-branch]')];
                return tree.getAttribute('role')==='tree'&&document.getElementById('worksheet-analysis-search').getAttribute('aria-haspopup')==='tree'&&
                    branches.length>3&&branches.every(node=>node.getAttribute('aria-expanded')==='false'&&node.querySelector(':scope > [role=group]').hidden)&&
                    nodes.filter(node=>node.getClientRects().length).map(node=>node.dataset.worksheetBranch).join('|')==='Analysis|Data|Graphics'&&
                    nodes.every(node=>node.id)&&new Set(nodes.map(node=>node.id)).size===nodes.length;
            })()
            """) as? Bool == true,"Analyse initially shows only three collapsed accessible menu roots with unique stable node IDs")
        func key(_ value:String) async throws {
            _=try await js(grid,"document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'"+value+"',bubbles:true,cancelable:true}))")
        }
        func query(_ value:String) async throws {
            let encoded=String(data:try JSONSerialization.data(withJSONObject:[value]),encoding:.utf8)!
            _=try await js(grid,"(()=>{const field=document.getElementById('worksheet-analysis-search');field.focus();Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(field,"+encoded+"[0]);field.dispatchEvent(new Event('input',{bubbles:true}));})()")
        }
        let activeBranch="document.activeElement.dataset.worksheetBranch"
        try await key("ArrowDown")
        try await wait("ArrowDown did not choose the first Analyse root") { try await js(grid,activeBranch) as? String == "Analysis" }
        try await key("ArrowRight")
        try await wait { (try? await js(grid,"document.querySelector('[data-worksheet-branch=Analysis]').getAttribute('aria-expanded')==='true' && !document.querySelector('[data-worksheet-branch=Analysis] > [role=group]').hidden")) as? Bool == true }
        try await key("ArrowRight")
        try await wait("Right on an expanded branch did not select its child") { try await js(grid,activeBranch) as? String == "Analysis › Exact Tests on Counts" }
        try await key("ArrowLeft")
        try await wait { try await js(grid,activeBranch) as? String == "Analysis" }
        try await key("ArrowLeft")
        try await wait { (try? await js(grid,"document.querySelector('[data-worksheet-branch=Analysis]').getAttribute('aria-expanded')==='false' && document.querySelector('[data-worksheet-branch=Analysis] > [role=group]').hidden")) as? Bool == true }
        try await key("Enter")
        try await wait { (try? await js(grid,"document.querySelector('[data-worksheet-branch=Analysis]').getAttribute('aria-expanded')==='true'")) as? Bool == true }
        try check(v.documents.count == originalCount,"Analyse browse keys expand, enter, return to and collapse menu branches without launching an analysis")
        _=try await js(grid,"document.querySelector('[data-worksheet-branch=\"Analysis › Parametric\"] > .worksheet-tree-row').click()")
        try await wait { (try? await js(grid,"document.querySelector('[data-worksheet-branch=\"Analysis › Parametric\"]').getAttribute('aria-expanded')==='true'")) as? Bool == true }
        _=try await js(grid,"document.querySelector('[data-worksheet-branch=\"Analysis › Parametric\"] > .worksheet-tree-row').click()")
        try await wait { (try? await js(grid,"document.querySelector('[data-worksheet-branch=\"Analysis › Parametric\"]').getAttribute('aria-expanded')==='false'")) as? Bool == true }
        _=try await js(grid,"window.__worksheetBrowseExpanded=[...document.querySelectorAll('[data-worksheet-branch][aria-expanded=true]')].map(node=>node.dataset.worksheetBranch)")
        try await query("paired t")
        try await wait("Search did not reveal paired t inside its menu branches") { (try? await js(grid,"""
            (()=>{const leaf=document.querySelector('[data-worksheet-command=TPaired]');
                if(!leaf?.getClientRects().length)return false;
                for(let parent=leaf.parentElement.closest('[data-worksheet-branch]');parent;parent=parent.parentElement.closest('[data-worksheet-branch]'))
                    if(parent.getAttribute('aria-expanded')!=='true'||parent.querySelector(':scope > [role=group]').hidden)return false;
                return !document.querySelector('[data-worksheet-branch="Analysis › Descriptive"]')?.getClientRects().length;
            })()
            """)) as? Bool == true }
        try check(true,"Search opens matching ancestor branches and hides unrelated menu groups")
        try await query("")
        try await wait("Clearing search did not restore prior browse expansion") { (try? await js(grid,"JSON.stringify([...document.querySelectorAll('[data-worksheet-branch][aria-expanded=true]')].map(node=>node.dataset.worksheetBranch))===JSON.stringify(window.__worksheetBrowseExpanded) && !document.querySelector('[data-worksheet-command=TPaired]').getClientRects().length")) as? Bool == true }
        try check(v.documents.count == originalCount,"Clearing search restores the learner's expanded Analysis and collapsed Parametric branches")
        try await snapshot(grid.web,"worksheet-analyse")
        _=try await js(grid,"document.getElementById('worksheet-analysis-search').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}))")
        try await wait { (try? await js(grid,"!document.getElementById('worksheet-analysis-chooser')&&document.activeElement.dataset.command==='analyse'")) as? Bool == true }
        let selectionAfterCancel=try await js(grid,selected) as? Bool == true
        try check(v.documents.count == originalCount && selectionAfterCancel,"Escape cancels Analyse, returns toolbar focus and preserves the selected worksheet range")
        try await click(grid,"analyse")
        try await wait { (try? await js(grid,"document.activeElement.id==='worksheet-analysis-search'")) as? Bool == true }
        try check(try await js(grid,"JSON.stringify([...document.querySelectorAll('[data-worksheet-branch][aria-expanded=true]')].map(node=>node.dataset.worksheetBranch))===JSON.stringify(window.__worksheetBrowseExpanded)") as? Bool == true,"Reopening Analyse retains the worksheet's manual branch expansion")
        try await query("paired t")
        try await wait { (try? await js(grid,"(()=>{const field=document.getElementById('worksheet-analysis-search'),leaf=document.getElementById(field.getAttribute('aria-activedescendant'));return leaf?.dataset.worksheetCommand==='TPaired'&&leaf.getClientRects().length>0})()")) as? Bool == true }
        _=try await js(grid,"window.__worksheetFirstMatch=document.getElementById('worksheet-analysis-search').getAttribute('aria-activedescendant')")
        try await key("ArrowDown")
        try await wait { (try? await js(grid,"(()=>{const field=document.getElementById('worksheet-analysis-search'),leaf=document.getElementById(field.getAttribute('aria-activedescendant'));return field.getAttribute('aria-activedescendant')!==window.__worksheetFirstMatch&&!!leaf?.dataset.worksheetCommand&&leaf.getClientRects().length>0})()")) as? Bool == true }
        try await key("ArrowUp")
        try await wait { (try? await js(grid,"(()=>{const search=document.getElementById('worksheet-analysis-search'),leaf=document.getElementById(search.getAttribute('aria-activedescendant'));return document.activeElement===search&&leaf?.dataset.worksheetCommand==='TPaired'&&leaf.getAttribute('aria-selected')==='true'&&leaf.id===window.__worksheetFirstMatch})()")) as? Bool == true }
        try check(v.documents.count == originalCount,"Analyse supports keyboard search and arrow selection without launching an analysis")
        _=try await js(grid,"document.getElementById('worksheet-analysis-search').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}))")
        try await wait("Enter did not open paired t with a source snapshot") { v.active?.operationName == "TPaired" && v.active?.operationSourceSnapshot != nil }
        let paired=v.active!
        try await wait { (try? await js(paired,"!!document.querySelector('.paired-inputs button[type=submit]')")) as? Bool == true }
        let source=paired.operationSourceSnapshot ?? [:]
        try check(v.documents.count == originalCount+1 && paired.operationSourceID == grid.id && source["selection"] as? [Int] == [0,1] && source["range"] as? [String:Int] == ["first":2,"last":4],"Enter starts the paired t form with the exact originating worksheet, columns and selected rows")
        try check(try await js(paired,"document.querySelector('.paired-inputs').textContent.includes('Before → After') && document.querySelector('.paired-inputs').textContent.includes('rows 2–4') && !document.querySelector('.column-chooser')") as? Bool == true,"paired t opens ready for Run without an extra column-selection step")
        v.remove(paired);v.tabs.selectTabViewItem(grid.item)
        try check(try await js(grid,selected) as? Bool == true,"Opening and closing the analysis form retains the worksheet highlight")

        try await click(grid,"worksheetHelp")
        try await wait("Worksheet Help did not open its topic in the existing dock") { v.helpPane.visible && v.helpPane.web.url?.path == "/basics/worksheet.htm" }
        let selectionAfterHelp=try await js(grid,selected) as? Bool == true
        try check(v.active === grid && v.documents.count == originalCount && selectionAfterHelp,"worksheet Help reuses the existing dock without creating a document or changing the selection")
        v.helpPane.hide();v.window.contentView!.layoutSubtreeIfNeeded()
        try await click(grid,"worksheetR")
        try await wait("Worksheet R did not open an interactive script document") { v.active?.kind == "r" && v.active?.rConsolePane != nil }
        let script=v.active!, console=script.rConsolePane!
        try await wait { (try? await js(script,"window.StatsDirectRConsole?.snapshot().mode==='script' && document.getElementById('script-source').value.length>0 && !document.getElementById('script-source').disabled && !document.getElementById('script-source').readOnly")) as? Bool == true }
        try await wait("The new R script did not reach an idle ready session") { console.session.state == "ready" }
        let text=console.sourceText
        try check(text.contains("data <-") && text.contains("Before") && text.contains("After") && ["1201","1202","1203","8001","8002","8003"].allSatisfy(text.contains) && !["1204","8004","999999"].contains(where:text.contains),"worksheet R opens an editable script containing only the selected columns and three selected data rows")
        try check(!console.isBusy && !console.hasWorkspace && console.session.commandId == nil && console.outputText.isEmpty,"worksheet R starts ready without executing the generated data script")
        try check(try await js(grid,selected) as? Bool == true,"Opening the R script preserves the original worksheet highlight")
        v.remove(script)
    }
}
