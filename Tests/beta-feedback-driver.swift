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
    try await LearningWorkspaceTests.run(viewer)
    try await ProviderLearningTests.run(viewer)
    try await run(viewer)
    viewer.newReport()
    try await ReportExportTests.run(viewer)
    try await largeGrid(viewer)
    if CommandLine.arguments.contains("--live") { try await live(viewer) }
    print("PASS: beta feedback native integration");fflush(stdout)
   } catch { print("FAIL:",error);fflush(stdout);exit(1) }
   if !CommandLine.arguments.contains("--stay-open") { viewer.closeApproved=true;app.terminate(nil) }
  }}
  app.run()
 }
 @MainActor static func largeGrid(_ v:Viewer) async throws {
  let grid=v.newDocument(kind:"grid",title:"Large paste fixture",url:v.root.appendingPathComponent("Grid/index.html"))
  defer {v.remove(grid)}
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}
  let pasted=try await v.learningJavaScript(grid,#"""
  (()=>{const t=performance.now();window.largePaste=Array.from({length:10000},(_,r)=>Array.from({length:10},(_,c)=>String(r*10+c)).join('\t')).join('\n');statsDirectGrid.pasteText(window.largePaste);return {milliseconds:performance.now()-t};})()
  """#)
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().columns.length===10})"))?["ok"] as? Bool == true}
  let check="(()=>{const s=statsDirectGrid.analysisSource();return {rows:s.rows,columns:s.columns.length,count:s.cells.filter(c=>c.text!=='').length,last:s.cells.find(c=>c.col===9&&c.row===9999)?.text,exact:statsDirectGrid.csvData().trim().split('\\n').length===10000};})()"
  let full=try await v.learningJavaScript(grid,check)
  precondition(full["rows"] as? Int==10000 && full["columns"] as? Int==10 && full["count"] as? Int==100000 && full["last"] as? String=="99999" && full["exact"] as? Bool==true)
  let source=try await v.learningJavaScript(grid,"statsDirectGrid.analysisSource()")
  let frame:[String:Any]=["name":"Derived","columns":1,"rows":10001,"headerRow":true,"cells":[["col":0,"row":0,"text":"Derived","kind":"text"],["col":0,"row":1,"text":"2.5","kind":"number"]]]
  let derived=derivedWorksheet(source:source,range:["firstRow":1,"lastRow":10000],frame:frame)!
  let sourceCells=derived["cells"] as! [[String:Any]]
  precondition(sourceCells.contains{$0["col"] as? Int==0 && $0["row"] as? Int==1 && $0["text"] as? String=="0" && $0["kind"] as? String=="number"})
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.undo(),true)})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().cells.length===0&&statsDirectGrid.analysisSource().columns.length===8})"))?["ok"] as? Bool == true}
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.redo(),true)})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,check))?["last"] as? String == "99999"}
  _=try await v.learningJavaScript(grid,"({ok:statsDirectGrid.editCommand('selectAll','')})")
  try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.copyText()===window.largePaste})"))?["ok"] as? Bool == true}
  _=try await v.learningJavaScript(grid,"({ok:(statsDirectGrid.pasteText(window.largePaste+'\\n1'),true)})")
  let rejected=try await v.learningJavaScript(grid,check);precondition(rejected["count"] as? Int==100000 && rejected["last"] as? String=="99999")
  print("PASS: native 10,000 × 10 paste, auto-expansion, numeric source-and-derived columns, full CSV/copy, atomic undo/redo and oversized-paste rejection; paste ms=",pasted["milliseconds"]!)
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
  v.editReport(report,["action":"hideChart","resultID":id,"index":0])
  precondition(report.reportEntries!.first!.hiddenCharts.contains(0))
  v.editReport(report,["action":"undoReport"])
  precondition(report.reportEntries!.first!.hiddenCharts.isEmpty && report.reportEntries!.first!.annotation.contains("paired design"))
  for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:50_000_000)}
  let exported=String(decoding:try await v.reportExportData(report,format:.html),as:UTF8.self)
  precondition(exported.contains("Interpret with the paired design") && !exported.contains("Remove plot") && !exported.contains("contenteditable"))
  v.editReport(report,["action":"removeResult","resultID":id]);precondition(!report.reportEntries!.contains{$0.id==id})
  v.editReport(report,["action":"undoReport"]);precondition(report.reportEntries!.contains{$0.id==id})
  v.editReport(report,["action":"hideChart","resultID":id,"index":0])
  v.editReport(report,["action":"annotate","resultID":id,"text":"A newer annotation"])
  v.activeReportID=report.id
  v.appendReport(ReportEntry(id:"added-after-removal",title:"Later result",operation:"",body:"<p>Later result retained</p>",rPlan:nil))
  v.editReport(report,["action":"undoReport"])
  precondition(report.reportEntries!.contains{$0.id=="added-after-removal"} && report.reportEntries!.first{$0.id==id}!.annotation=="A newer annotation")
  print("PASS: report notes exported, plots/results removed and restored; Undo preserves later results and annotations")
  let source:[String:Any]=["columns":["A","B"],"firstRow":1,"rows":3,"cells":[["col":0,"row":0,"text":"5","kind":"number"],["col":1,"row":2,"text":"9","kind":"number"]]]
  let frame:[String:Any]=["name":"Log","columns":1,"rows":3,"headerRow":true,"cells":[["col":0,"row":0,"text":"Log","kind":"text"],["col":0,"row":1,"text":"1.2","kind":"number"],["col":0,"row":2,"text":"1.4","kind":"number"]]]
  let derived=derivedWorksheet(source:source,range:["firstRow":2,"lastRow":3],frame:frame)!
  let cells=derived["cells"] as! [[String:Any]]
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
  let overview=String(decoding:try JSONSerialization.data(withJSONObject:await workspace.overview()),as:UTF8.self)
  var calls:[String]=[],partials=0
  let reply=try await tutor.converse(context:"Fictional bundled teaching example, no patient identifiers. Current learner: advanced biostatistical skills, comfortable coding in R. Use appropriate equations and R code. Workspace: "+overview,messages:[["role":"user","text":"Read the two PEFR columns in test.xlsx, use the StatsDirect engine to run a paired t test with an agreement plot, and report the number of complete pairs and mean before-minus-after difference. Give the equivalent R paired t.test code using those actual values. Use the app tools and do not substitute illustrative data."]],tools:TutorTools.definitions,progress:{_ in partials += 1},toolHandler:{name,args in calls.append(name);return try await workspace.call(name,args)})
  precondition(calls.contains("statsdirect_read_data") && calls.contains("statsdirect_run_analysis") && partials>1)
  precondition(reply.text.contains("56.11") && reply.text.contains("t.test"))
  try Data(reply.text.utf8).write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("live-tutor-fictional-example.txt"))
  print("PASS: LIVE ChatGPT → native worksheet → nine PEFR pairs → real engine → SVG report; streamed advanced response includes correct difference and R code")
 }
}
