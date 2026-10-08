import Cocoa
@main struct LearningWorkspaceTests {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let viewer=Viewer();app.delegate=viewer
        let fixtureRoot=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        viewer.chatGPTTutor=ChatGPTTutor(executable:fixtureRoot.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:fixtureRoot.appendingPathComponent(".build/startup-chatgpt-mock"),resources:viewer.root.appendingPathComponent("Tutor"))
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: native WKWebView context integration") }
                catch { print("FAIL:",error.localizedDescription); fflush(stdout); exit(1) }
                fflush(stdout)
                if !CommandLine.arguments.contains("--stay-open") { viewer.closeApproved=true;app.terminate(nil) }
            }
        }
        app.run()
    }
    @MainActor static func run(_ v:Viewer) async throws {
        v.openExampleWorkbook()
        var grid:Document?
        for _ in 0..<100 {
            if let doc=v.documents.last(where:{$0.kind=="grid" && $0.workbookName=="test.xlsx"}), doc.pendingWorkbook == nil,
               (try? await v.learningJavaScript(doc,"window.statsDirectGrid.tutorInfo()")) != nil {grid=doc;break}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard let grid else { throw ChatGPTTutor.Failure(message:"Example workbook failed to load") }
        let info=try await v.learningJavaScript(grid,"window.statsDirectGrid.tutorInfo()")
        let sheets=info["sheets"] as! [[String:Any]]
        var target:([String:Any],[Int])?
        for sheet in sheets {
            let cols=(sheet["columns"] as! [[String:Any]]).filter{String(describing:$0["title"] ?? "").lowercased().contains("pefr")}
            if cols.count==2 {target=(sheet,cols.map{$0["index"] as! Int});break}
        }
        guard let (sheet,columns)=target else {throw ChatGPTTutor.Failure(message:"PEFR columns were not found: \(info)")}
        v.openLearning()
        let learn=v.documents.first{$0.kind=="learn"}!
        for _ in 0..<100 {
            if (try? await v.learningJavaScript(learn,"({ready:!!document.getElementById('question')})"))?["ready"] as? Bool == true {break}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        precondition(learn.learningSourceID == "__none__")
        learn.learningRequestID="native-fixture"
        let defaultScope=LearningWorkspace(v,learn,"native-fixture")
        try await defaultScope.authorize { _ in fatalError("Default sharing asked for consent") }
        let defaultOverview=try await defaultScope.overview()
        precondition((defaultOverview["documents"] as! [Any]).isEmpty)
        learn.learningSourceID=grid.id;learn.learningRequestID="native-fixture"
        let workspace=LearningWorkspace(v,learn,"native-fixture")
        precondition(workspace.allowed.isEmpty)
        let before=try await workspace.overview()
        precondition((before["documents"] as! [Any]).isEmpty && before["focusedDocumentId"] as? String == "")
        do {_=try await workspace.call("statsdirect_read_data",["documentId":grid.id]);fatalError("Read before consent")}catch{precondition(error.localizedDescription.contains("no longer available"))}
        let cancelled=LearningWorkspace(v,learn,"native-fixture")
        do {try await cancelled.authorize {_ in .cancel};fatalError("Cancellation ignored")}catch{precondition(error.localizedDescription.contains("cancelled"))}
        precondition(cancelled.allowed.isEmpty)
        // Exercise the real native confirmation: Share is disabled until the checkbox is selected.
        let authorization=Task {try await workspace.authorize()}
        try await ProviderLearningTests.wait {v.window.attachedSheet != nil}
        func buttons(_ view:NSView)->[NSButton] { (view as? NSButton).map{[$0]} ?? view.subviews.flatMap(buttons) }
        let sheetWindow=v.window.attachedSheet!,controls=buttons(sheetWindow.contentView!)
        let share=controls.first{$0.title=="Share for This Question"}!,confirm=controls.first{$0.title.hasPrefix("I have checked")}!
        precondition(!share.isEnabled && confirm.state == .off)
        // Synthetic fixture only: no live AI connection is used by this test.
        confirm.performClick(nil);precondition(share.isEnabled);share.performClick(nil)
        try await authorization.value
        precondition(workspace.allowed == [grid.id])
        let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:v.learningFolder.appendingPathComponent("portfolio.json"))) as! [String:Any]
        let confirmations=saved["sharingConsents"] as! [[String:Any]]
        precondition(confirmations.count==1 && confirmations[0]["noPersonIdentifiers"] as? Bool==true)
        precondition((confirmations[0]["documents"] as! [[String:Any]]).map{$0["id"] as! String} == [grid.id])
        try await learn.web.evaluateJavaScript(String(contentsOfFile:".build/feedback-renderer.js",encoding:.utf8))
        let savedJSON=String(decoding:try JSONSerialization.data(withJSONObject:saved),as:UTF8.self)
        let recordHTML=try await learn.web.evaluateJavaScript("window.feedbackRecord(\(savedJSON))") as! String
        precondition(recordHTML.contains("Document sharing confirmations") && recordHTML.contains("document-sharing-v1") && recordHTML.contains("no person identifiers"))
        print("PASS: lessons-only default; no metadata or cells before native consent; unchecked confirmation blocks Share; consent persisted before access")
        let overview=try await workspace.call("statsdirect_workspace",[:]);precondition(!(overview["documents"] as! [Any]).isEmpty)
        let data=try await workspace.call("statsdirect_read_data",["documentId":grid.id,"sheetIndex":sheet["index"]!,"columns":columns])
        precondition(data["rowCount"] as? Int==9)
        let first=(data["columns"] as! [[String:Any]])[0]["values"] as! [String]
        precondition(first==[312,242,340,388,296,254,391,402,290].map(String.init))
        let result=try await workspace.call("statsdirect_run_analysis",["operation":"TPaired","datasetId":data["datasetId"]!,"agreement":true])
        precondition(result["state"] as? String=="complete" && result["hasSVG"] as? Bool==true)
        let again=try await workspace.call("statsdirect_run_analysis",["operation":"TPaired","datasetId":data["datasetId"]!,"agreement":true])
        precondition(again["resultId"] as? String==result["resultId"] as? String)
        let report=v.documents.first{$0.id==result["reportId"] as? String}!
        precondition(report.reportEntries?.count==1 && report.rScriptPlan?.hasRecipe==true && v.active===learn)
        print("PASS: real test.xlsx → exact nine PEFR pairs → engine → one active report with SVG and R link; repeated request reuses result")
        grid.gridVersion += 1
        do {_=try await workspace.call("statsdirect_run_analysis",["operation":"TPaired","datasetId":data["datasetId"]!]);throw ChatGPTTutor.Failure(message:"Stale worksheet accepted")} catch {precondition(error.localizedDescription.contains("changed"))}
        let r=v.newDocument(kind:"r",title:"R context fixture");let pane=RPane(script:"mean(c(1, 2, 3))");r.rPane=pane;r.item.view=pane.view;pane.console.string="[1] 2\n"
        // Documents opened after Send are excluded from that earlier question.
        do {_=try await workspace.call("statsdirect_read_document",["documentId":r.id]);throw ChatGPTTutor.Failure(message:"New document leaked into old scope")}catch{precondition(error.localizedDescription.contains("no longer available"))}
        learn.learningSourceID=""
        let current=LearningWorkspace(v,learn,"native-fixture")
        try await current.authorize {_ in .share}
        let rRead=try await current.call("statsdirect_read_document",["documentId":r.id]);precondition(rRead["output"] as? String=="[1] 2\n")
        for _ in 0..<40 where report.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        let reportRead=try await current.call("statsdirect_read_document",["documentId":report.id]);precondition((reportRead["text"] as? String ?? "").contains("56.111111"))
        let help=try await current.call("statsdirect_method_help",["operation":"TPaired"]);precondition((help["text"] as? String ?? "").lowercased().contains("paired"))
        let declined=LearningWorkspace(v,learn,"native-fixture")
        try await declined.authorize {_ in .lessonsOnly}
        precondition(declined.allowed.isEmpty && learn.learningSourceID == "__none__")
        let isolated=LearningWorkspace(v,learn,"native-fixture");precondition(isolated.allowed.isEmpty)
        do {_=try await isolated.call("statsdirect_read_data",["documentId":grid.id]);throw ChatGPTTutor.Failure(message:"Lessons-only allowed worksheet reading")}catch{precondition(error.localizedDescription.contains("no longer available"))}
        learn.learningRequestID=nil
        do {_=try await current.call("statsdirect_workspace",[:]);throw ChatGPTTutor.Failure(message:"Cancelled question retained access")}catch is CancellationError{}
        print("PASS: stale data, closed scope, lesson-only sharing and cancelled questions rejected; help/report/R context readable")
        // Permission is not carried to another question, and an unsaved consent never grants access.
        learn.learningSourceID=grid.id;learn.learningRequestID="save-failure"
        let unsaved=LearningWorkspace(v,learn,"save-failure")
        _=try await v.learningJavaScript(learn,"(()=>{window.savedConsent=statsDirectLearn.recordSharingConsent;statsDirectLearn.recordSharingConsent=()=>{throw Error('Synthetic save failure');};return {ok:true};})()")
        do {try await unsaved.authorize {_ in .share};fatalError("Failed consent record accepted")}catch{}
        precondition(unsaved.allowed.isEmpty)
        _=try await v.learningJavaScript(learn,"({ok:(statsDirectLearn.recordSharingConsent=window.savedConsent,true)})")
        let changed=LearningWorkspace(v,learn,"save-failure")
        do {try await changed.authorize {_ in grid.gridVersion += 1;return .share};fatalError("Changed data accepted")}catch{precondition(error.localizedDescription.contains("changed"))}
        learn.learningRequestID=nil
        let oldPolicy=UserDefaults.standard.object(forKey:"DisableOnlineTutor")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        v.learningSettings(learn)
        do {try await v.chatGPTTutor.refreshAccount();fatalError("Disabled tutor refreshed account")}catch{precondition(error.localizedDescription.contains("disabled"))}
        do {_=try await v.chatGPTTutor.signIn();fatalError("Disabled tutor started sign-in")}catch{precondition(error.localizedDescription.contains("disabled"))}
        do {_=try await v.chatGPTTutor.converse(context:"",messages:[["role":"user","text":"Synthetic policy test"]]);fatalError("Disabled tutor sent question")}catch{precondition(error.localizedDescription.contains("disabled"))}
        do {_=try await changed.overview();fatalError("Disabled policy exposed workspace")}catch{precondition(error.localizedDescription.contains("disabled"))}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(learn,"({ok:document.getElementById('send').disabled && document.getElementById('settings').disabled && document.getElementById('workspaceChoice').disabled})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(learn,"({ok:(document.getElementById('practiceNav').click(),true)})")
        let local=try await v.learningJavaScript(learn,"({practice:!document.getElementById('supported').disabled,lessons:!document.querySelector('[data-lesson]').disabled})")
        precondition(local["practice"] as? Bool==true && local["lessons"] as? Bool==true)
        _=try await v.learningJavaScript(learn,"({ok:(document.querySelector('[data-lesson]').click(),true)})")
        let offline=try await v.learningJavaScript(learn,"({example:!document.querySelector('[data-action=example]').disabled,r:!document.querySelector('[data-action=r]').disabled,help:!document.querySelector('[data-action=help]').disabled})")
        precondition(offline.values.allSatisfy{$0 as? Bool == true})
        UserDefaults.standard.set(oldPolicy,forKey:"DisableOnlineTutor")
        print("PASS: cancelled or unrecorded consent grants no access; edited data needs a new confirmation; institution policy blocks account, sign-in, questions and tools while offline learning remains usable")
        // Context/account updates must preserve a draft being typed.
        _=try await v.learningJavaScript(learn,"({value:(document.getElementById('question').value='Draft survives a context refresh')})")
        v.learningSettings(learn)
        v.remove(r);learn.learningSourceID=grid.id;v.learningLastDocumentID=grid.id;v.tabs.selectTabViewItem(learn.item);v.refreshLearningWorkspace(learn)
        try await Task.sleep(nanoseconds:200_000_000)
        let draft=try await v.learningJavaScript(learn,"({value:document.getElementById('question').value})")
        precondition(draft["value"] as? String == "Draft survives a context refresh")
        learn.learningSourceID="__none__";v.refreshLearningWorkspace(learn)
    }
}
