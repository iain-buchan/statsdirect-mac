import Cocoa
import PDFKit

@main struct BetaFeedbackTests {
 @MainActor static func main() {
  let app=NSApplication.shared; app.setActivationPolicy(.regular)
  let viewer=Viewer(); app.delegate=viewer
        let fixtureRoot=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        viewer.chatGPTTutor=ChatGPTTutor(executable:fixtureRoot.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:fixtureRoot.appendingPathComponent(".build/startup-chatgpt-mock"),resources:viewer.root.appendingPathComponent("Tutor"))
  UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
  DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { Task { @MainActor in
   do {
    if CommandLine.arguments.contains("--forms-only") {
     try await FormContractTests.run(viewer)
     try await FormControlTests.run(viewer)
    } else if CommandLine.arguments.contains("--excel-only") {
     try await ExcelImportTests.run(viewer)
    } else if CommandLine.arguments.contains("--groups-only") {
     try await GroupIdentifierTests.run(viewer)
    } else if CommandLine.arguments.contains("--privacy-only") {
     try await LearningWorkspaceTests.run(viewer)
    } else {
    try await ExcelImportTests.run(viewer)
    try await LearningWorkspaceTests.run(viewer)
    try await ProviderLearningTests.run(viewer)
    try await run(viewer)
    viewer.newReport()
    try await ReportExportTests.run(viewer)
    try await largeGrid(viewer)
    try await entryTables(viewer)
    try await FormContractTests.run(viewer)
    try await FormControlTests.run(viewer)
    try await GroupIdentifierTests.run(viewer)
    try await WriteBackTests.run(viewer)
    if CommandLine.arguments.contains("--live") { try await live(viewer) }
    }
    print("PASS: beta feedback native integration");fflush(stdout)
   } catch { print("FAIL:",error);fflush(stdout);exit(1) }
   if !CommandLine.arguments.contains("--stay-open") { viewer.closeApproved=true;app.terminate(nil) }
  }}
  app.run()
 }
 @MainActor static func asyncJavaScript(_ doc:Document,_ script:String,_ arguments:[String:Any]=[:]) async throws -> [String:Any] {
  try await withCheckedThrowingContinuation { continuation in
   doc.web.callAsyncJavaScript(script,arguments:arguments,in:nil,in:.page) { result in
    switch result {
    case .failure(let error): continuation.resume(throwing:error)
    case .success(let value):
     if let value=value as? [String:Any] { continuation.resume(returning:value) } else { continuation.resume(throwing:ChatGPTTutor.Failure(message:"Unexpected script result: \(String(describing:value))")) }
    }
   }
  }
 }
 @MainActor static func entryTables(_ v:Viewer) async throws {
  let form=v.newDocument(kind:"operation",title:"Entry table scale fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
  defer {v.remove(form)}
  try await ProviderLearningTests.wait {form.operationReady}
  _=try await v.learningJavaScript(form,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.entryState=s;update(s);};return {ok:true};})()")
  form.operationName="UnivariateSummary";v.startOperation(form)
  var pasted=false
  for _ in 0..<20 {
   try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:['input','complete','failed'].includes(window.entryState?.state)})"))?["ok"] as? Bool == true}
   let state=try await v.learningJavaScript(form,"({state:entryState.state,token:entryState.token??0,kind:entryState.prompt?.kind??'',error:entryState.prompt?.error??entryState.error??''})")
   if state["state"] as? String=="complete" {break}
   guard state["state"] as? String=="input",state["error"] as? String=="" else {throw ChatGPTTutor.Failure(message:"Entry table analysis failed: \(state)")}
   if state["kind"] as? String=="grid" {
    guard !pasted else {throw ChatGPTTutor.Failure(message:"Unexpected second data prompt")}
    _=try await v.learningJavaScript(form,"({ok:(Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Enter / paste data').click(),true)})")
    try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:!!document.querySelector('.grid-tools')})"))?["ok"] as? Bool == true}
    let timing=try await v.learningJavaScript(form,#"(()=>{const t=performance.now();statsDirectOperation.pasteText('1\n3\n'.repeat(524288));return {milliseconds:performance.now()-t};})()"#)
    try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:document.querySelector('.grid-tools').textContent.includes('1048576 rows')})"))?["ok"] as? Bool == true}
    print("Native embedded full-column paste ms:",timing["milliseconds"]!);fflush(stdout)
    pasted=true
   }
   let token=state["token"]!
   _=try await v.learningJavaScript(form,"({ok:(document.querySelector('form').requestSubmit(),true)})")
   try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:entryState.state!=='input'||entryState.token!==\(token)})"))?["ok"] as? Bool == true}
  }
  try await ProviderLearningTests.wait {form.completedJobID != nil}
  let summary=try await v.learningJavaScript(form,"(()=>{const d=document.createElement('div');d.innerHTML=entryState.html;return Object.fromEntries(Array.from(d.querySelectorAll('tr')).map(r=>[r.cells[0].textContent,r.cells[1].textContent]));})()")
  precondition(pasted && summary["Valid data"] as? String=="1048576" && summary["Mean"] as? String=="2" && summary["Sum"] as? String=="2097152")
  print("PASS: native embedded 1,048,576-row paste → original univariate summary engine; exact n, mean and sum")

  let grid=v.newDocument(kind:"grid",title:"Large selected table fixture",url:v.root.appendingPathComponent("Grid/index.html"))
  defer {v.remove(grid)}
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}
  _=try await asyncJavaScript(grid,"await statsDirectGrid.loadWorkbook({name:'Counts',sheets:[{name:'Counts',columns:2,rows:500001,headerRow:false,cells:[{col:0,row:0,text:'12',kind:'number'},{col:1,row:500000,text:'17',kind:'number'}]}]});return {ok:true};")
  _=try await v.learningJavaScript(grid,"({ok:statsDirectGrid.editCommand('selectAll','')})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!statsDirectGrid.analysisSource().screenDeferred})"))?["ok"] as? Bool == true}
  form.operationSourceID=grid.id
  v.refreshOperationSource(form)
  _=try await v.learningJavaScript(form,"({ok:(statsDirectOperation.update({state:'input',token:'fixture',prompt:{kind:'grid',screen:true,minColumns:2,maxColumns:2,rows:12,prompt:'Selected table'}}),true)})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(form,"({ok:document.querySelector('.grid-tools')?.textContent.includes('500001 rows × 2 columns')&&!document.querySelector('[aria-busy=true]')})"))?["ok"] as? Bool == true}
  let selected=try await v.learningJavaScript(form,"({first:document.querySelector('[aria-label=\"Selected data cell\"]').value,errors:Array.from(document.querySelectorAll('[role=alert]')).map(e=>e.textContent)})")
  precondition(selected["first"] as? String=="12" && (selected["errors"] as? [String])?.isEmpty==true)
  print("PASS: native highlighted 500,001 × 2 rectangle preloads through the worksheet column bridge")
 }
 @MainActor static func largeGrid(_ v:Viewer) async throws {
  let grid=v.newDocument(kind:"grid",title:"Large paste fixture",url:v.root.appendingPathComponent("Grid/index.html"))
  defer {v.remove(grid)}
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}
  let pasted=try await v.learningJavaScript(grid,#"""
  (()=>{const t=performance.now();window.largePaste=Array.from({length:10000},(_,r)=>Array.from({length:10},(_,c)=>String(r*10+c)).join('\t')).join('\n');statsDirectGrid.pasteText(window.largePaste);return {milliseconds:performance.now()-t};})()
  """#)
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().columns.length===10})"))?["ok"] as? Bool == true}
  let check="(()=>{const s=statsDirectGrid.analysisSource();const d=statsDirectGrid.columnValues({columns:[9],first:1,last:s.rows});return {rows:s.rows,columns:s.columns.length,count:s.columnEnds.reduce((n,e)=>n+e,0),last:d.columns[0].values[9999],exact:statsDirectGrid.csvData().trim().split('\\n').length===10000,cells:'cells' in s};})()"
  let full=try await v.learningJavaScript(grid,check)
  precondition(full["rows"] as? Int==10000 && full["columns"] as? Int==10 && full["count"] as? Int==100000 && full["last"] as? String=="99999" && full["exact"] as? Bool==true && full["cells"] as? Bool==false)
  let source=try await v.learningJavaScript(grid,"statsDirectGrid.analysisSource()")
  let frame:[String:Any]=["name":"Derived","columns":1,"rows":10001,"headerRow":true,"cells":[["col":0,"row":0,"text":"Derived","kind":"text"],["col":0,"row":1,"text":"2.5","kind":"number"]]]
  let plan=derivedWorksheet(source:source,range:["firstRow":1,"lastRow":10000],frame:frame)!
  precondition(plan.sourceColumns != nil && plan.sheet["columns"] as? Int==11 && (plan.sheet["cells"] as! [[String:Any]]).contains{$0["col"] as? Int==10 && $0["row"] as? Int==1 && $0["text"] as? String=="2.5"})
  // The source columns reach the derived worksheet through a typed snapshot served by the application, never JSON.
  let stored=try await asyncJavaScript(grid,"return window.statsDirectGrid.snapshotColumns(request)",["request":plan.sourceColumns!])
  let snapshotID=stored["id"] as! String
  precondition(((try? Data(contentsOf:SnapshotStore.shared.file(for:snapshotID)!))?.count ?? 0) > 100000)
  let derivedDoc=v.newDocument(kind:"grid",title:"Derived fixture",url:v.root.appendingPathComponent("Grid/index.html"))
  defer {v.remove(derivedDoc)}
  var merged=plan.sheet; merged["snapshot"]=SnapshotStore.shared.url(for:snapshotID); derivedDoc.snapshotIDs.append(snapshotID)
  derivedDoc.pendingWorkbook=["name":"Derived fixture","sheets":[merged],"formulaCount":0]
  try await ProviderLearningTests.wait {derivedDoc.pendingWorkbook==nil}
  let combined=try await v.learningJavaScript(derivedDoc,"(()=>{const d=statsDirectGrid.columnValues({columns:[0,9,10],first:1,last:10001});const s=statsDirectGrid.analysisSource();return {a:d.columns[0].values[1],j:d.columns[1].values[10000],derived:d.columns[2].values[1],title:d.columns[2].values[0],columns:s.columns.length,firstRow:s.firstRow,count:s.columnEnds.reduce((n,e)=>n+e,0)};})()")
  precondition(combined["a"] as? String=="0" && combined["j"] as? String=="99999" && combined["derived"] as? String=="2.5" && combined["title"] as? String=="Derived" && combined["columns"] as? Int==11 && combined["firstRow"] as? Int==2 && combined["count"] as? Int==100012)
  precondition(SnapshotStore.shared.file(for:snapshotID)==nil)
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.undo(),true)})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().width===0&&statsDirectGrid.analysisSource().columns.length===8})"))?["ok"] as? Bool == true}
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.redo(),true)})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,check))?["last"] as? String == "99999"}
  _=try await v.learningJavaScript(grid,"({ok:statsDirectGrid.editCommand('selectAll','')})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.copyText()===window.largePaste})"))?["ok"] as? Bool == true}
  // The typed store has no paste cap below Excel's dimensions: one more row is accepted, a 16,385-column row is refused and leaves the sheet unchanged.
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.pasteText(window.largePaste+'\\n1'),true)})")
  let grown=try await v.learningJavaScript(grid,check);precondition(grown["count"] as? Int==100001 && grown["last"] as? String=="99999")
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.pasteText(Array.from({length:16385},()=>'1').join('\\t')),true)})")
  let rejected=try await v.learningJavaScript(grid,check);precondition(rejected["count"] as? Int==100001 && rejected["last"] as? String=="99999" && rejected["columns"] as? Int==10)
  print("PASS: native 10,000 × 10 paste, auto-expansion, lazy column reads, derived worksheet through a typed snapshot, full CSV/copy, atomic undo/redo and rejection of a paste wider than Excel; paste ms=",pasted["milliseconds"]!)
 }
 @MainActor static func run(_ v:Viewer) async throws {
  let learn=v.documents.first{$0.kind=="learn"}!
  var state=learn.learningState!;state["view"]="study";state["lesson"]="paired";state["quiz"]=NSNull()
  let rich="**Paired differences**\n\nUse \\(t=\\frac{\\bar d}{s_d/\\sqrt n}\\).\n\n```r\nx <- c(2, 4, 6)\nmean(x)\n```\n\n<img src=x onerror=alert(1)>\n<script>window.UNSAFE=true</script>"
  state["conversation"]=[["id":"format-fixture","at":"2026-10-06T12:00:00Z","role":"assistant","text":rich,"source":"Native test","lessonId":"paired","lessonTitle":"Paired measurements"]]
  v.learningScript(learn,"restore",state)
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(learn,"({ok:!!document.querySelector('.katex')})"))?["ok"] as? Bool == true}
  let formatted=try await v.learningJavaScript(learn,"({math:document.querySelectorAll('math').length,strong:!!document.querySelector('.message-body strong'),code:!!document.querySelector('.hljs-number'),buttons:document.querySelectorAll('[data-code]').length,unsafe:!!window.UNSAFE,image:!!document.querySelector('.message-body img')})")
  precondition(formatted["math"] as? Int == 1 && formatted["strong"] as? Bool == true && formatted["code"] as? Bool == true && formatted["buttons"] as? Int == 2 && formatted["unsafe"] as? Bool == false && formatted["image"] as? Bool == false)
  v.window.setContentSize(NSSize(width:960,height:680))
  let before=try await v.learningJavaScript(learn,"({height:document.getElementById('messages').clientHeight})")
  _=try await v.learningJavaScript(learn,"({ok:document.getElementById('focusConversation').click()===undefined})")
  let after=try await v.learningJavaScript(learn,"({height:document.getElementById('messages').clientHeight,composer:document.querySelector('.composer').getBoundingClientRect().bottom,viewport:innerHeight})")
  precondition((after["height"] as! Int) > (before["height"] as! Int) && (after["composer"] as! Double) <= (after["viewport"] as! Double))
  _=try await v.learningJavaScript(learn,"({ok:document.querySelector('[data-code=r]').click()===undefined})")
  try await ProviderLearningTests.wait {v.active?.rPane?.editor.string == "x <- c(2, 4, 6)\nmean(x)"}
  precondition(v.active!.rPane?.isRunning == false)
  v.tabs.selectTabViewItem(learn.item)
  _=try await v.learningJavaScript(learn,"({ok:document.querySelector('[data-lesson=diagnostic]').click()===undefined})")
  let switched=try await v.learningJavaScript(learn,"({old:!!document.querySelector('.katex')})");precondition(switched["old"] as? Bool == false)
  _=try await v.learningJavaScript(learn,"({ok:document.querySelector('[data-lesson=paired]').click()===undefined})")
  print("PASS: native Markdown, rendered formula, highlighted R, safe raw HTML, laptop conversation expansion, R tab without autorun and per-lesson history")
  // The interface must remain usable while a reply is pending.
  _=try await v.learningJavaScript(learn,"({ok:(document.getElementById('question').value='CANCEL_TEST Wait while I inspect streaming',document.getElementById('send').click(),true)})")
  try await ProviderLearningTests.wait {learn.learningRequestID != nil}
  v.learningScript(learn,"partial",["id":learn.learningRequestID!,"text":"**A streamed reply** is visible before completion."])
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(learn,"({ok:!!document.querySelector('#streamedReply strong')})"))?["ok"] as? Bool == true}
  _=try await v.learningJavaScript(learn,"({ok:document.getElementById('stop').click()===undefined})")
  try await ProviderLearningTests.wait {learn.learningRequestID == nil}
  let stopped=try await v.learningJavaScript(learn,"({enabled:!document.getElementById('question').disabled})");precondition(stopped["enabled"] as? Bool == true)
  print("PASS: streamed text appears before completion; Stop remains responsive and restores the composer")
  // Use the actual renderer for an exported learning record, with structured attempts.
  let bundle=try String(contentsOfFile:".build/feedback-renderer.js",encoding:.utf8)
  try await learn.web.evaluateJavaScript(bundle)
  let json=String(decoding:try JSONSerialization.data(withJSONObject:learn.learningState!),as:UTF8.self)
  let html=try await learn.web.evaluateJavaScript("window.feedbackRecord(\(json))") as! String
  let output=URL(fileURLWithPath:CommandLine.arguments[1])
  try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  for format in ReportFormat.allCases {
   let data=try await v.learningRecordData(html,format:format);precondition(data.count>100)
   try data.write(to:output.appendingPathComponent("learning-record."+format.rawValue))
   if format == .pdf {precondition((PDFDocument(data:data)?.string ?? "").contains("Paired differences"))}
  }
  print("PASS: learning record HTML, paginated PDF and DOCX exports")
  let report=v.documents.first{$0.reportEntries?.isEmpty == false}!,id=report.reportEntries!.first!.id
  v.editReport(report,["action":"annotate","resultID":id,"text":"Interpret with the paired design in mind."])
  for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:50_000_000)}
  try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true); document.querySelector('.report-body svg').dispatchEvent(new MouseEvent('click',{bubbles:true})); document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',bubbles:true,cancelable:true}));")
  try await Task.sleep(nanoseconds:200_000_000)
  precondition(!(report.reportEntries!.first!.editedBody ?? report.reportEntries!.first!.body).contains("<svg"))
  v.editReport(report,["action":"undoText"])
  precondition(report.reportEntries!.first!.hiddenCharts.isEmpty && report.reportEntries!.first!.annotation.contains("paired design"))
  for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:50_000_000)}
  let exported=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
  precondition(exported.contains("Interpret with the paired design") && !exported.contains("Remove plot") && !exported.contains("contenteditable"))
  v.recordReportEdits(report,edits:[],removing:[id],typing:false);precondition(!report.reportEntries!.contains{$0.id==id})
  v.editReport(report,["action":"undoText"]);precondition(report.reportEntries!.contains{$0.id==id})
  for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:50_000_000)}
  try await report.web.evaluateJavaScript("StatsDirectReportEditor.setEditing(true); document.querySelector('.report-body svg').dispatchEvent(new MouseEvent('click',{bubbles:true})); document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',bubbles:true,cancelable:true}));")
  try await Task.sleep(nanoseconds:200_000_000)
  v.editReport(report,["action":"annotate","resultID":id,"text":"A newer annotation"])
  v.activeReportID=report.id
  v.appendReport(ReportEntry(id:"added-after-removal",title:"Later result",operation:"",body:"<p>Later result retained</p>",rPlan:nil))
  v.editReport(report,["action":"undoText"])
  precondition(report.reportEntries!.contains{$0.id=="added-after-removal"} && report.reportEntries!.first{$0.id==id}!.annotation=="A newer annotation")
  print("PASS: report notes exported, plots/results removed and restored; Undo preserves later results and annotations")
  let source:[String:Any]=["columns":["A","B"],"firstRow":1,"rows":3,"cells":[["col":0,"row":0,"text":"5","kind":"number"],["col":1,"row":2,"text":"9","kind":"number"]]]
  let frame:[String:Any]=["name":"Log","columns":1,"rows":3,"headerRow":true,"cells":[["col":0,"row":0,"text":"Log","kind":"text"],["col":0,"row":1,"text":"1.2","kind":"number"],["col":0,"row":2,"text":"1.4","kind":"number"]]]
  let derived=derivedWorksheet(source:source,range:["firstRow":2,"lastRow":3],frame:frame)!
  precondition(derived.sourceColumns==nil)
  let cells=derived.sheet["cells"] as! [[String:Any]]
  precondition(cells.contains{ $0["col"] as? Int == 2 && $0["row"] as? Int == 2 && $0["text"] as? String == "1.2" })
  precondition(cells.contains{ $0["col"] as? Int == 1 && $0["row"] as? Int == 3 && $0["text"] as? String == "9" })
  precondition(derivedWorksheet(source:source,range:["firstRow":1,"lastRow":3],frame:frame)==nil)
  print("PASS: derived worksheet preserves source columns and aligns selected rows; mismatched output is kept separate")
 }
 @MainActor static func live(_ v:Viewer) async throws {
  let base=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
  let storage=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("com.statsdirect.viewer.prototype/ChatGPT Tutor")
  let tutor=ChatGPTTutor(executable:base.appendingPathComponent(".build/codex-runtime/bin/codex-app-server"),storage:storage,resources:v.root.appendingPathComponent("Tutor"))
  defer {tutor.shutdown()}
  try await tutor.refreshAccount();precondition(tutor.account != nil)
  let grid=v.documents.first{$0.kind=="grid" && $0.workbookName=="test.xlsx"}!,learn=v.documents.first{$0.kind=="learn"}!
  learn.learningSourceID=grid.id;learn.learningRequestID="live-feedback"
  let workspace=LearningWorkspace(v,learn,"live-feedback")
  try await workspace.authorize()
  let overview=String(decoding:try JSONSerialization.data(withJSONObject:await workspace.overview()),as:UTF8.self)
  var calls:[String]=[],partials=0
  let reply=try await tutor.converse(context:"Fictional bundled teaching example, no patient identifiers. Current learner: advanced biostatistical skills, comfortable coding in R. Use appropriate equations and R code. Workspace: "+overview,messages:[["role":"user","text":"Read the two PEFR columns in test.xlsx, use the StatsDirect engine to run a paired t test with an agreement plot, and report the number of complete pairs and mean before-minus-after difference. Give the equivalent R paired t.test code using those actual values. Use the app tools and do not substitute illustrative data."]],tools:TutorTools.definitions,progress:{_ in partials += 1},toolHandler:{name,args in calls.append(name);return try await workspace.call(name,args)})
  precondition(calls.contains("statsdirect_read_data") && calls.contains("statsdirect_run_analysis") && partials>1)
  precondition(reply.text.contains("56.11") && reply.text.contains("t.test"))
  try Data(reply.text.utf8).write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("live-tutor-fictional-example.txt"))
  print("PASS: LIVE ChatGPT → native worksheet → nine PEFR pairs → real engine → SVG report; streamed advanced response includes correct difference and R code")
 }
}
