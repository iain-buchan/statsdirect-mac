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
        // Rule 2.6 of the worksheet R rules: Edit > Select All offers Entire worksheet as its Selected cells, which the
        // grid's own tests cannot reach because the marker lives in the React selection.
        try check(try await js(grid,"(()=>{const p=window.statsDirectGrid.worksheetRImport();return p.selected!==null&&JSON.stringify(p.selected)===JSON.stringify(p.entire);})()") as? Bool == true,
                  "Select All offers the entire worksheet as the R import's selected cells")
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
        try check(try await js(grid,"""
            (()=>{const row=document.querySelector('.sd-toolbar-row'), get=id=>row.querySelector('[data-command='+id+']');
                const analyse=get('analyse'), r=get('worksheetR'), external=get('worksheetRPlus'), help=get('worksheetHelp');
                return analyse?.textContent.trim()==='Analyse'&&r?.previousElementSibling===analyse&&external?.previousElementSibling===r&&
                    help?.previousElementSibling===external&&help.hasAttribute('data-group-start')&&
                    [r,external,help].every(b=>b.title===b.getAttribute('aria-label')&&b.title.length>0);})()
            """) as? Bool == true,"worksheet groups the labelled Analyse, R and R+ commands before the Help divider")

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
                const search=document.getElementById('worksheet-analysis-search');
                return tree.getAttribute('role')==='tree'&&search.getAttribute('aria-haspopup')==='tree'&&
                    search.placeholder==='Search methods'&&search.getAttribute('aria-label')==='Search methods'&&
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
        try await query("Z Score")
        try await wait("The Data Z Score exact command was not ranked ahead of partial Analysis matches") { (try? await js(grid,"""
            (()=>{const tree=document.getElementById('worksheet-analysis-results'),exact=tree.querySelector(':scope > [data-worksheet-branch="Exact matches"]'),leaves=[...tree.querySelectorAll('[data-worksheet-command]')].filter(node=>node.getClientRects().length),field=document.getElementById('worksheet-analysis-search');
                return exact===tree.firstElementChild&&leaves[0]?.dataset.worksheetCommand==='TransformZSD'&&
                    document.getElementById(field.getAttribute('aria-activedescendant'))===leaves[0]&&
                    exact.querySelector(':scope > [role=group]').contains(leaves[0]);
            })()
            """)) as? Bool == true }
        try check(try await js(grid,"""
            (()=>{const tree=document.getElementById('worksheet-analysis-results'),exact=tree.querySelector(':scope > [data-worksheet-branch="Exact matches"]'),z=[...tree.querySelectorAll('[data-worksheet-command=TransformZSD]')],partial=[...tree.querySelectorAll('[data-worksheet-command=ChildGrowth]')].filter(node=>node.getClientRects().length),path=z[0]?.querySelector(':scope > .worksheet-tree-row .worksheet-tree-path');
                return z.length===1&&path?.textContent==='Data › Transforming and Deriving › Common Transforms'&&path.getClientRects().length>0&&
                    partial.length>0&&partial.every(node=>!exact.contains(node));
            })()
            """) as? Bool == true,"Search puts the exact Data Z Score first with a visible menu path, keeps Growth Charts partial matches below, and shows the exact command once")
        try await snapshot(grid.web,"worksheet-analyse-exact-search")
        try await query("Normal")
        let expectedNormal=nativeRows.filter { $0["kind"] as? String == "leaf" && $0["label"] as? String == "Normal" }.map { ["id":$0["id"] as! String,"path":$0["path"] as! String] }
        try await wait("Normal search did not display every exact duplicate with its path") { (try? await js(grid,"document.querySelector('[data-worksheet-branch=\"Exact matches\"] > [role=group]')?.querySelectorAll('[data-worksheet-command]').length===3")) as? Bool == true }
        let normalRows=try await js(grid,"""
            (()=>{const exact=document.querySelector('[data-worksheet-branch="Exact matches"] > [role=group]');
                return [...exact.querySelectorAll(':scope > [data-worksheet-command]')].map(node=>{
                    const path=node.querySelector(':scope > .worksheet-tree-row .worksheet-tree-path');
                    return {id:node.dataset.worksheetCommand,path:path?.getClientRects().length?path.textContent:''};
                });})()
            """) as? [[String:String]] ?? []
        func ordered(_ rows:[[String:String]]) -> [[String:String]] { rows.sorted { ($0["path"] ?? "") < ($1["path"] ?? "") } }
        try check(expectedNormal.count==3 && normalRows.count==3 && ordered(normalRows)==ordered(expectedNormal),"Duplicate Normal exact commands retain their distinct Analysis, Data and Graphics menu paths")
        try check(try await js(grid,"['DistributionNormal','RndNormal','NormalPlot'].every(id=>document.querySelectorAll('[data-worksheet-command='+id+']').length===1)") as? Bool == true,"Exact Normal commands are removed from the remaining partial-match outline")
        try await snapshot(grid.web,"worksheet-analyse-matches")
        try check(v.documents.count==originalCount,"Comparing exact and duplicate search matches leaves the worksheet and open documents unchanged")
        try await query("Bland Altman plot")
        try await wait("The authored Help keyword did not find Paired t") { (try? await js(grid,"document.querySelector('[data-worksheet-command=TPaired]')?.getClientRects().length>0")) as? Bool == true }
        try check(true,"Analyse uses authored Help keyword aliases to find methods with different menu names")
        try await query("paired")
        try await wait("Paired search did not show Graphics Ladder Plot before reviewed related methods") { (try? await js(grid,"""
            (()=>{const tree=document.getElementById('worksheet-analysis-results'),graphics=tree.querySelector(':scope > [data-worksheet-branch=Graphics]'),related=tree.querySelector(':scope > [data-worksheet-branch="Related methods"]');
                return graphics?.querySelector('[data-worksheet-command=LadderPlot]')?.getClientRects().length>0&&
                    related?.querySelector('[data-worksheet-command=Wilcoxon]')?.getClientRects().length>0&&
                    related?.querySelector('[data-worksheet-command=ExactMcNamarChi]')?.getClientRects().length>0&&
                    !!(graphics.compareDocumentPosition(related)&Node.DOCUMENT_POSITION_FOLLOWING);
            })()
            """)) as? Bool == true }
        try check(true,"Paired search shows the Graphics Ladder Plot before Related methods while retaining the reviewed paired tests")
        try await query("paired tests")
        try await wait("Broad paired tests search did not reveal its reviewed related methods") { (try? await js(grid,"""
            (()=>{const related=document.querySelector('[data-worksheet-branch="Related methods"]');
                return related?.getClientRects().length>0&&related.querySelector('[data-worksheet-command=Wilcoxon]')?.getClientRects().length>0&&
                    related.querySelector('[data-worksheet-command=ExactMcNamarChi]')?.getClientRects().length>0;
            })()
            """)) as? Bool == true }
        try check(try await js(grid,"!document.querySelector('#worksheet-analysis-results [data-worksheet-command=LadderPlot]')") as? Bool == true,"Paired tests search excludes Ladder Plot while retaining the reviewed statistical tests")
        try check(try await js(grid,"""
            (()=>{const related=document.querySelector('[data-worksheet-branch="Related methods"]'),leaves=[...document.querySelectorAll('#worksheet-analysis-results [data-worksheet-command]')].filter(node=>node.getClientRects().length),reviewed=[...related.querySelectorAll('[data-worksheet-command]')];
                return reviewed.length>=2&&reviewed.every(node=>{
                    const purpose=node.querySelector(':scope > .worksheet-tree-row .worksheet-tree-purpose');
                    return purpose?.getClientRects().length>0&&purpose.textContent.trim().length>15;
                })&&leaves.every(node=>!['TUnpaired','TUnpairedSummary','ZUnpaired','MannWhitney','Chi2by2'].includes(node.dataset.worksheetCommand));
            })()
            """) as? Bool == true,"Broad paired tests includes Wilcoxon and McNemar with visible outcome/purpose guidance, excluding independent-sample and ordinary 2-by-2 tests")
        try await key("Enter")
        try await Task.sleep(nanoseconds:150_000_000)
        let broadSelectionUnchanged=try await js(grid,selected) as? Bool == true
        let broadChooserOpen=try await js(grid,"!!document.getElementById('worksheet-analysis-chooser')") as? Bool == true
        try check(v.active === grid && v.documents.count==originalCount && broadSelectionUnchanged && broadChooserOpen,"Enter on a broad method query leaves the chooser open until the learner explicitly chooses a method")
        try await key("ArrowDown")
        try await wait("A deliberate arrow choice did not select a reviewed method") { (try? await js(grid,"(()=>{const field=document.getElementById('worksheet-analysis-search'),leaf=document.getElementById(field.getAttribute('aria-activedescendant'));return !!leaf?.dataset.worksheetCommand&&leaf.getAttribute('aria-selected')==='true'&&leaf.getClientRects().length>0})()")) as? Bool == true }
        try check(v.documents.count==originalCount,"Arrow selection makes a broad method choice explicit without running an analysis")
        try await snapshot(grid.web,"worksheet-analyse-related-methods")
        _=try await js(grid,"document.getElementById('worksheet-analysis-search-help').click()")
        func helpQuery(_ url:URL?) -> String? {
            guard let url,let fragment=URLComponents(url:url,resolvingAgainstBaseURL:false)?.percentEncodedFragment else { return nil }
            return URLComponents(string:"?"+fragment)?.queryItems?.first(where:{$0.name=="searchQuery"})?.value
        }
        try await wait("Search Help did not pass the unchanged broad query to the existing dock") { v.helpPane.visible && helpQuery(v.helpPane.web.url)=="paired tests" }
        try await wait("The Help dock did not render the full paired-tests results") {
            (try? await v.helpPane.web.evaluateJavaScript("!document.getElementById('results')?.hidden && !!document.querySelector('#results a[data-link=\"nonparametric_methods/wilcoxon_signed_ranks.htm\"]') && !!document.querySelector('#results a[data-link=\"methods/methods_paired_dichotomous.htm\"]')")) as? Bool == true
        }
        let selectionAfterSearchHelp=try await js(grid,selected) as? Bool == true
        try check(v.helpPane.searchField.stringValue=="paired tests" && v.active === grid && v.documents.count==originalCount && selectionAfterSearchHelp,"Search Help uses the same paired tests query in the existing dock, retaining the worksheet, highlighted range and document count")
        v.helpPane.hide();v.window.contentView!.layoutSubtreeIfNeeded()
        if (try await js(grid,"!!document.getElementById('worksheet-analysis-chooser')")) as? Bool != true { try await click(grid,"analyse") }
        try await wait { (try? await js(grid,"!!document.getElementById('worksheet-analysis-search')")) as? Bool == true }
        try await query("paired t")
        try await wait("Search did not reveal paired t inside its menu branches") { (try? await js(grid,"""
            (()=>{const leaf=document.querySelector('[data-worksheet-command=TPaired]');
                if(!leaf?.getClientRects().length)return false;
                for(let parent=leaf.parentElement.closest('[data-worksheet-branch]');parent;parent=parent.parentElement.closest('[data-worksheet-branch]'))
                    if(parent.getAttribute('aria-expanded')!=='true'||parent.querySelector(':scope > [role=group]').hidden)return false;
                return leaf.parentElement.closest('[data-worksheet-branch]')?.dataset.worksheetBranch==='Exact matches'&&
                    leaf.querySelector(':scope > .worksheet-tree-row .worksheet-tree-path')?.textContent==='Analysis › Parametric'&&
                    !document.querySelector('[data-worksheet-branch="Analysis › Descriptive"]')?.getClientRects().length;
            })()
            """)) as? Bool == true }
        try check(true,"Search opens matching ancestor branches and hides unrelated menu groups")
        try await query("")
        try await wait("Clearing search did not restore prior browse expansion") { (try? await js(grid,"JSON.stringify([...document.querySelectorAll('[data-worksheet-branch][aria-expanded=true]')].map(node=>node.dataset.worksheetBranch))===JSON.stringify(window.__worksheetBrowseExpanded) && !document.querySelector('[data-worksheet-command=TPaired]').getClientRects().length")) as? Bool == true }
        try check(v.documents.count == originalCount,"Clearing search restores the learner's expanded Analysis and collapsed Parametric branches")
        try await snapshot(grid.web,"worksheet-analyse")
        _=try await js(grid,"document.getElementById('worksheet-analysis-search').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}))")
        try await Task.sleep(nanoseconds:150_000_000)
        try await wait("Escape did not dismiss Analyse and keep focus on its toolbar button after layout") { (try? await js(grid,"!document.getElementById('worksheet-analysis-chooser')&&document.activeElement.dataset.command==='analyse'")) as? Bool == true }
        let selectionAfterCancel=try await js(grid,selected) as? Bool == true
        try check(v.documents.count == originalCount && selectionAfterCancel,"Escape cancels Analyse, returns toolbar focus and preserves the selected worksheet range")
        let analysisMenu=NSApp.mainMenu!.items.first(where:{$0.submenu?.title=="Analysis"})!.submenu!
        let shortcut=analysisMenu.items.first(where:{$0.action == #selector(Viewer.searchWorksheetCommands)})
        try check(shortcut?.keyEquivalent=="A" && shortcut?.keyEquivalentModifierMask == [.command,.shift],"Analysis exposes the native Command-Shift-A worksheet search shortcut")
        func openWithShortcut() throws {
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.shift],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:v.window.windowNumber,context:nil,characters:"A",charactersIgnoringModifiers:"A",isARepeat:false,keyCode:0)!
            try check(NSApp.mainMenu!.performKeyEquivalent(with:event),"The native menu dispatches Command-Shift-A from the worksheet WebView")
        }
        v.window.makeFirstResponder(grid.web)
        let responder=v.window.firstResponder as? NSView
        try check(responder === grid.web || responder?.isDescendant(of:grid.web)==true,"Worksheet content is the native first responder before its search shortcut")
        try openWithShortcut()
        try await wait("Command-Shift-A did not open and focus worksheet command search") { (try? await js(grid,"document.activeElement.id==='worksheet-analysis-search'")) as? Bool == true }
        try check(try await js(grid,"JSON.stringify([...document.querySelectorAll('[data-worksheet-branch][aria-expanded=true]')].map(node=>node.dataset.worksheetBranch))===JSON.stringify(window.__worksheetBrowseExpanded)") as? Bool == true,"Reopening Analyse with its native shortcut retains the worksheet's manual branch expansion")
        try await query("paired t")
        try await wait { (try? await js(grid,"(()=>{const field=document.getElementById('worksheet-analysis-search'),leaf=document.getElementById(field.getAttribute('aria-activedescendant'));return leaf?.dataset.worksheetCommand==='TPaired'&&leaf.getClientRects().length>0})()")) as? Bool == true }
        try openWithShortcut()
        try await wait { (try? await js(grid,"document.activeElement.id==='worksheet-analysis-search'&&document.activeElement.value==='paired t'")) as? Bool == true }
        try check(try await js(grid,selected) as? Bool == true,"The native shortcut refocuses an open search without resetting its query or worksheet selection")
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

        let sharedHelpSVG=try await js(grid,"document.querySelector('[data-command=worksheetHelp] svg')?.innerHTML") as? String ?? ""
        try check(!sharedHelpSVG.isEmpty,"The worksheet supplies the shared question-mark SVG for method-help controls")
        for (operation,topic,name) in [("ExactSign","/exact_tests_on_counts/sign.htm","Sign Test"),("ExactChiRbyCScreen","/chi_square_tests/rc.htm","screen R × C")] {
            v.openWorksheetCommand(operation,source:grid)
            let form=v.active!
            try check(form !== grid,"\(name) opens its actual analysis form")
            try await wait("\(name) did not show its header help icon") { (try? await js(form,"!!document.querySelector('header button[data-command=methodHelp] svg')")) as? Bool == true }
            try check(try await js(form,"(()=>{const button=document.querySelector('header button[data-command=methodHelp]'),svg=button.querySelector('svg');return button.title==='Method help'&&button.getAttribute('aria-label')==='Method help'&&button.textContent.trim()===''&&svg.innerHTML===\(v.jsString(sharedHelpSVG));})()") as? Bool == true,"\(name) uses the shared icon-only question mark with the exact Method help tooltip and accessible label")
            try await click(form,"methodHelp")
            try await wait("\(name) header help did not reach its existing native help route") { v.helpPane.visible && v.helpPane.web.url?.path == topic }
            try check(v.active === form && v.documents.count==originalCount+1,"\(name) Method help opens the correct topic in the existing dock")
            v.helpPane.hide()
            if form.kind=="operation", form.analysisJobID != nil {
                try await wait { form.operationReady && !form.operationStarting }
                _=try await js(form,"document.querySelector('.cancel button')?.click()")
                try await wait { form.analysisJobID == nil }
            }
            v.remove(form);v.tabs.selectTabViewItem(grid.item);v.window.contentView!.layoutSubtreeIfNeeded()
        }
        try await click(grid,"worksheetHelp")
        try await wait("Worksheet Help did not open its topic in the existing dock") { v.helpPane.visible && v.helpPane.web.url?.path == "/basics/worksheet.htm" }
        let selectionAfterHelp=try await js(grid,selected) as? Bool == true
        try check(v.active === grid && v.documents.count == originalCount && selectionAfterHelp,"worksheet Help reuses the existing dock without creating a document or changing the selection")
        v.helpPane.hide();v.window.contentView!.layoutSubtreeIfNeeded()
        try await worksheetRTools(v, grid: grid, js: js, click: click, selected: selected)
    }

    @MainActor static func worksheetRTools(_ v: Viewer, grid: Document,
        js: (Document, String) async throws -> Any?, click: (Document, String) async throws -> Void,
        selected: String) async throws {
        func view<T: NSView>(_ id: String, in root: NSView?) -> T? {
            guard let root else { return nil }
            if root.identifier?.rawValue == "worksheet-r-" + id { return root as? T }
            return root.subviews.lazy.compactMap { view(id, in: $0) }.first
        }
        func button(_ id: String, in sheet: NSWindow) throws -> NSButton {
            guard let control: NSButton = view(id, in: sheet.contentView) else {
                throw NSError(domain:"ToolbarChecks",code:3,userInfo:[NSLocalizedDescriptionKey:"Missing R import control " + id])
            }
            return control
        }
        func prompt() async throws -> NSWindow {
            try await wait("Worksheet R import sheet did not open") { v.window.attachedSheet?.identifier?.rawValue == "worksheet-r-import" }
            return v.window.attachedSheet!
        }
        func formatControls(in sheet: NSWindow) throws -> (NSPopUpButton, NSTextField) {
            guard let format: NSPopUpButton = view("format", in: sheet.contentView),
                  let hint: NSTextField = view("format-hint", in: sheet.contentView) else {
                throw NSError(domain:"ToolbarChecks",code:3,userInfo:[NSLocalizedDescriptionKey:"Missing R import format or its hint"])
            }
            return (format, hint)
        }
        func choose(_ format: NSPopUpButton, _ index: Int) { format.selectItem(at: index); format.sendAction(format.action, to: format.target) }
        /// Every text the sheet shows, the alert's title and message among them.
        func texts(in sheet: NSWindow) -> [String] {
            func collect(_ view: NSView) -> [String] { ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(collect) }
            return sheet.contentView.map(collect) ?? []
        }
        let originalCount = v.documents.count
        try await click(grid,"worksheetR")
        let integrated = try await prompt()
        let none = try button("none", in: integrated)
        let entireCells = try button("entire", in: integrated)
        let selectedCells = try button("selected", in: integrated)
        let headings = try button("headings", in: integrated)
        let friendly = try button("friendly-names", in: integrated)
        let (format, hint) = try formatControls(in: integrated)
        try check(texts(in: integrated).contains("Open in StatsDirect R")
                  && texts(in: integrated).contains("Choose the data from “Measurements” to copy into the new R session as worksheet_data."),
                  "the R sheet is titled Open in StatsDirect R and names the sheet and worksheet_data")
        try check(none.state == .on && integrated.initialFirstResponder === none
                  && !headings.isEnabled && !friendly.isEnabled && !format.isEnabled && hint.isHidden
                  && friendly.state == .off && format.titleOfSelectedItem == "Data frame (keep rows aligned)",
                  "the native import sheet focuses No data and disables the data options by default")
        try check(entireCells.title == "Entire worksheet — A1:F100 (100 rows × 6 columns)"
                  && selectedCells.title == "Selected cells — A2:B4 (3 rows × 2 columns)"
                  && selectedCells.accessibilityIdentifier() == "worksheet-r-selected",
                  "the data choices give the exact ranges and counts, and keep stable accessibility identifiers")
        selectedCells.performClick(nil)
        try check(headings.isEnabled && headings.state == .off && !friendly.isEnabled && format.isEnabled,
                  "a numeric first row stays in the imported data by default")
        choose(format, 1)
        try check(!hint.isHidden && hint.stringValue == "Missing values are removed separately from each vector.",
                  "List of vectors shows its hint")
        choose(format, 0)
        try check(hint.isHidden, "Data frame hides the list hint")
        try button("open", in: integrated).performClick(nil)
        try await wait("Worksheet R did not open an integrated R session") { v.active?.kind == "r" && v.active?.rConsolePane != nil }
        let script=v.active!, console=script.rConsolePane!
        try await wait("Worksheet R did not import the data into its live console") {
            guard console.session.state == "ready", console.hasWorkspace else { return false }
            return (try? await js(script,"window.StatsDirectRConsole?.snapshot().mode==='console'")) as? Bool == true
        }
        let text=console.sourceText
        try check(text.contains("worksheet_data <- structure(list(") && text.contains("utils::str(worksheet_data)")
                  && ["1201","1202","1203","8001","8002","8003"].allSatisfy(text.contains)
                  && !["1204","8004","999999"].contains(where:text.contains),
                  "worksheet R retains an editable script with only the selected cells")
        try check(console.session.submit(source: "if (is.data.frame(worksheet_data) && identical(names(worksheet_data), c('A', 'B')) && identical(worksheet_data$A, c(1201, 1202, 1203)) && identical(worksheet_data$B, c(8001, 8002, 8003))) cat(paste0('WORKSHEET_', 'FRAME_OK'))"),
                  "the integrated session accepts a command against the imported frame")
        try await wait("The integrated data frame did not match the chosen cells and column letters") { console.outputText.contains("WORKSHEET_FRAME_OK") }
        try check(console.outputText.contains("3 obs. of") && console.outputText.contains("2 variables"),
                  "the integrated session shows utils::str(worksheet_data) after the import")
        v.remove(script); v.tabs.selectTabViewItem(grid.item)
        try check(try await js(grid,selected) as? Bool == true,"Opening the R session preserves the original worksheet highlight")

        try await click(grid,"worksheetR")
        let empty = try await prompt()
        try button("open", in: empty).performClick(nil)
        try await wait { v.active?.rConsolePane != nil && v.documents.count == originalCount + 1 }
        let emptyScript = v.active!
        try check(emptyScript.rConsolePane?.sourceText.isEmpty == true && emptyScript.rConsolePane?.hasWorkspace == false,
                  "the default No data choice opens an empty integrated session")
        v.remove(emptyScript); v.tabs.selectTabViewItem(grid.item)

        let sheetName = "Worksheet R toolbar test " + UUID().uuidString
        _=try await grid.web.callAsyncJavaScript("""
            await statsDirectGrid.loadWorkbook({name:'Worksheet R test',sheets:[{name, headerRow:false, rows:100, columns:8, cells:[
                {col:1,row:3,text:'PEFR Before',kind:'text'}, {col:2,row:3,text:'PEFR_Before',kind:'text'},
                {col:3,row:3,text:'PEFR_Before_1',kind:'text'},
                {col:1,row:4,text:'11',kind:'number'}, {col:2,row:5,text:'22',kind:'number'},
                {col:1,row:6,text:'33',kind:'number'}, {col:3,row:6,text:'44',kind:'number'}]}]});
            return true;
            """, arguments:["name":sheetName], in:nil, contentWorld:.page)
        try await wait { (try? await js(grid,"statsDirectGrid.analysisSource().name.endsWith(" + v.jsString(sheetName) + ")")) as? Bool == true }
        // The script R+ saves in R Scripts is named after the sheet; a unique suffix may follow.
        func savedScripts() -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: RExternalScript.scriptsFolder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(sheetName + " Worksheet") && $0.pathExtension == "R" }
        }
        let launchExternal = RExternalScript.opensExternally
        RExternalScript.opensExternally = false
        defer { RExternalScript.opensExternally = launchExternal; for url in savedScripts() { try? FileManager.default.removeItem(at: url) } }
        try await click(grid,"worksheetRPlus")
        let cancelled = try await prompt()
        try check(try button("none", in: cancelled).state == .on && texts(in: cancelled).contains("Open in R or RStudio")
                  && texts(in: cancelled).contains("Choose the data from “\(sheetName)” to copy into R as worksheet_data."),
                  "the external R+ command opens the same No data default sheet, titled Open in R or RStudio")
        try button("cancel", in: cancelled).performClick(nil)
        try await wait { v.window.attachedSheet == nil }
        try check(v.documents.count == originalCount && savedScripts().isEmpty,
                  "Cancel prevents both a data copy and an external handoff")

        try await click(grid,"worksheetRPlus")
        let external = try await prompt()
        let entire = try button("entire", in: external)
        try check(entire.title == "Entire worksheet — B4:D7 (4 rows × 3 columns)",
                  "Entire worksheet reports populated bounds and dimensions")
        entire.performClick(nil)
        let infer = try button("headings", in: external)
        let convert = try button("friendly-names", in: external)
        try check(infer.state == .on && convert.isEnabled && convert.state == .off,
                  "a clear first row suggests headings, and R-friendly names are opt-in")
        convert.performClick(nil)
        infer.performClick(nil)
        try check(infer.state == .off && !convert.isEnabled && convert.state == .on,
                  "unticking the first box dims R-friendly names but keeps their tick")
        entire.performClick(nil)
        try check(infer.state == .off, "choosing the same data again keeps the user's first-box choice")
        infer.performClick(nil)
        try check(convert.isEnabled && convert.state == .on, "ticking the first box again brings back the R-friendly tick")
        let (externalFormat, externalHint) = try formatControls(in: external)
        choose(externalFormat, 1)
        try check(!externalHint.isHidden, "List of vectors shows its hint for R+ too")
        try button("open", in: external).performClick(nil)
        try await wait("R+ did not save the external script") { savedScripts().count == 1 }
        try check(v.active === grid && v.documents.count == originalCount,
                  "worksheet R+ hands off the script without opening an internal R tab")
        guard let rscript = RRuntime.executable() else {
            throw NSError(domain:"ToolbarChecks",code:4,userInfo:[NSLocalizedDescriptionKey:"Rscript is required for standalone worksheet replay"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath:rscript)
        process.arguments = ["--vanilla", "-e", """
            source(commandArgs(TRUE)[1L], encoding = 'UTF-8')
            stopifnot(is.list(worksheet_data), !is.data.frame(worksheet_data),
              identical(names(worksheet_data), c('PEFR_Before', 'PEFR_Before_2', 'PEFR_Before_1')),
              identical(worksheet_data[[1L]], c(11, 33)), identical(worksheet_data[[2L]], 22), identical(worksheet_data[[3L]], 44))
            """, savedScripts()[0].path]
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0,"the R+ script replays independently in R with unique headings and unequal vectors")
    }
}
