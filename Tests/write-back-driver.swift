import Cocoa

// A failed check ends the driver through its normal failure path (a printed FAIL and exit code 1)
// rather than trapping, which would show the macOS "quit unexpectedly" dialog.
struct DriverCheckFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: Bool, _ message: @autoclosure () -> String) throws { if !condition { throw DriverCheckFailure(description: message()) } }

struct WriteBackTests {
    @MainActor static func run(_ v: Viewer) async throws {
        let grid=v.newDocument(kind:"grid",title:"Write-back fixture",url:v.root.appendingPathComponent("Grid/index.html"))
        defer {v.remove(grid)}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}
        _=try await BetaFeedbackTests.asyncJavaScript(grid,"await statsDirectGrid.loadWorkbook({name:'Write back',sheets:[{name:'Doses',columns:2,rows:5,headerRow:true,cells:[['dose','1','2','4','8'],['note','a','b','c','d']].flatMap((values,col)=>values.map((text,row)=>({col,row,text,kind:row&&!col?'number':'text'})))}]});return {ok:true};")
        _=try await v.learningJavaScript(grid,"(()=>{statsDirectGrid.editCommand('selectAll','');return {ok:true};})()")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().range?.last===5})"))?["ok"] as? Bool == true}
        let form=v.newDocument(kind:"operation",title:"Log transform fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
        defer {v.remove(form)}
        form.operationSourceID=grid.id
        try await ProviderLearningTests.wait {form.operationReady && form.operationSourceSnapshot != nil}
        _=try await v.learningJavaScript(form,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.wbState=s;update(s);};return {ok:true};})()")
        form.operationName="TransformLog";v.startOperation(form)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:window.wbState?.prompt?.kind==='grid'&&!!document.querySelector('select[name=output-placement]')})"))?["ok"] as? Bool == true}
        // The definition's default (after the selected columns) is offered; the dose column alone is transformed, inserted after it.
        _=try await v.learningJavaScript(form,"(()=>{const s=document.querySelector('select[name=output-placement]');if(s.value!=='AfterSelection')throw new Error('default placement '+s.value);const boxes=document.querySelectorAll('.column-chooser input');if(boxes[1].checked)boxes[1].click();return {ok:true};})()")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:document.querySelectorAll('.column-chooser input:checked').length===1})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(form,"({ok:(document.querySelector('form').requestSubmit(),true)})")
        try await ProviderLearningTests.wait {form.completedJobID != nil}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.csvData().split(/\\r?\\n/)[0].split(',').length===3})"))?["ok"] as? Bool == true}
        let csv=(try await v.learningJavaScript(grid,"({csv:statsDirectGrid.csvData()})"))["csv"] as! String
        let lines=csv.components(separatedBy:.newlines).filter{!$0.isEmpty}.map{$0.split(separator:",",omittingEmptySubsequences:false).map(String.init)}
        try check(lines[0][0]=="dose" && lines[0][2]=="note" && lines[0][1].lowercased().contains("dose"), "titles \(lines[0])")
        try check(lines[1][1]=="0" && lines[4][1].hasPrefix("2.0794") && lines[1][2]=="a", "values \(lines[1]) \(lines[4])")
        let selected=try await v.learningJavaScript(grid,"({range:statsDirectGrid.analysisSource().range})")
        try check((selected["range"] as? [String:Any])?["last"] as? Int==5, "selection \(selected)")
        _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.undo(),true)})")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.csvData().split(/\\r?\\n/)[0]==='dose,note'})"))?["ok"] as? Bool == true}
        print("PASS: native transform output written into the source worksheet after the selected column, moving the note column along, selected, and undone in one step")
    }
}
