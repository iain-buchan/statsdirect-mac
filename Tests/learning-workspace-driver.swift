import Cocoa
@main struct LearningWorkspaceTests {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let viewer=Viewer();app.delegate=viewer
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
        learn.learningSourceID=grid.id;learn.learningRequestID="native-fixture"
        let workspace=LearningWorkspace(v,learn,"native-fixture")
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
        let current=LearningWorkspace(v,learn,"native-fixture")
        let rRead=try await current.call("statsdirect_read_document",["documentId":r.id]);precondition(rRead["output"] as? String=="[1] 2\n")
        for _ in 0..<40 where report.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        let reportRead=try await current.call("statsdirect_read_document",["documentId":report.id]);precondition((reportRead["text"] as? String ?? "").contains("56.111111"))
        let help=try await current.call("statsdirect_method_help",["operation":"TPaired"]);precondition((help["text"] as? String ?? "").lowercased().contains("paired"))
        learn.learningSourceID="__none__"
        let isolated=LearningWorkspace(v,learn,"native-fixture");precondition(isolated.allowed.isEmpty)
        do {_=try await isolated.call("statsdirect_read_data",["documentId":grid.id]);throw ChatGPTTutor.Failure(message:"Lessons-only allowed worksheet reading")}catch{precondition(error.localizedDescription.contains("no longer available"))}
        learn.learningRequestID=nil
        do {_=try await current.call("statsdirect_workspace",[:]);throw ChatGPTTutor.Failure(message:"Cancelled question retained access")}catch is CancellationError{}
        print("PASS: stale data, closed scope, lesson-only sharing and cancelled questions rejected; help/report/R context readable")
        // Context/account updates must preserve a draft being typed.
        _=try await v.learningJavaScript(learn,"({value:(document.getElementById('question').value='Draft survives a context refresh')})")
        v.learningSettings(learn)
        v.remove(r);learn.learningSourceID=grid.id;v.learningLastDocumentID=grid.id;v.tabs.selectTabViewItem(learn.item);v.refreshLearningWorkspace(learn)
        try await Task.sleep(nanoseconds:200_000_000)
        let draft=try await v.learningJavaScript(learn,"({value:document.getElementById('question').value})")
        precondition(draft["value"] as? String == "Draft survives a context refresh")
    }
}
