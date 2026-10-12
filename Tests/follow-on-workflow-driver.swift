import Cocoa
import WebKit

// Parents use the recorded input fixtures. Every follow-on is launched by its real
// WebKit button and completed through the rendered controls and native host.
@main struct FollowOnWorkflowTests {
    @MainActor static func check(_ ok: Bool, _ message: String) throws {
        if !ok { throw NSError(domain: "FollowOnWorkflow", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "FollowOnWorkflow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for follow-on form"])
    }
    @MainActor static func request(_ v: Viewer, _ body: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            v.analysisRequest(body, entry: "statsdirect_operation") { continuation.resume(with: $0) }
        }
    }
    @MainActor static func settled(_ v: Viewer, _ id: String) async throws -> [String: Any] {
        var result: [String: Any] = [:]
        try await wait {
            result = try await request(v, ["action": "poll", "id": id])
            return result["state"] as? String != "running"
        }
        return result
    }
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "automaticUpdateChecks")
        UserDefaults.standard.set(["use-default-ci": true, "default-ci": "95", "selectGroupsByIdentifier": false], forKey: "analysisDefaults")
        let v = Viewer(); app.delegate = v
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                do { try await run(v); print("PASS: native follow-on workflow suite"); fflush(stdout) }
                catch { print("FAIL: \(error)"); fflush(stdout); exit(1) }
                v.closeApproved = true; app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 600) { print("FAIL: follow-on suite timed out"); fflush(stdout); exit(1) }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.window.setContentSize(NSSize(width: 1180, height: 850))
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/form-follow-on-fixtures.json")
        let fixtures = (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any])["fixtures"] as! [[String: Any]]
        let byName = Dictionary(uniqueKeysWithValues: fixtures.map { ($0["operation"] as! String, $0) })
        let report = v.makeReport()
        var parents: [String: Document] = [:], outputs: [String: [String: Any]] = [:]
        var tested = Set<String>(), paths = 0
        // Seed the full parent context through the real engine, without substituting
        // hand-made results. Its form remains open just as after a normal calculation.
        for fixture in fixtures where fixture["parent"] == nil {
            let operation = fixture["operation"] as! String, id = UUID().uuidString
            _ = try await request(v, ["action": "start", "id": id, "operation": operation])
            var state = try await settled(v, id)
            for step in fixture["steps"] as! [[String: Any]] {
                let prompt = state["prompt"] as? [String: Any] ?? [:]
                try check(state["state"] as? String == "input" && prompt["kind"] as? String == step["kind"] as? String && prompt["name"] as? String == step["name"] as? String, "Parent fixture changed: \(operation): \(state)")
                _ = try await request(v, ["action": "answer", "id": id, "token": state["token"]!, "value": step["value"]!])
                state = try await settled(v, id)
            }
            try check(state["state"] as? String == "complete", "Parent failed: \(operation): \(state)")
            let parent = v.newDocument(kind: "operation", title: operation, url: v.root.appendingPathComponent("Grid/operation.html"))
            try await wait { parent.operationReady }
            parent.operationName = operation; parent.completedJobID = id
            parent.operationInputEntered = true
            v.operationScript(parent, "configure", v.analysisCatalog[operation]!)
            v.operationScript(parent, "update", state)
            parents[operation] = parent; outputs[operation] = state
            print("Prepared native parent: \(operation)"); fflush(stdout)
        }

        func follow(_ parent: Document, _ suggestion: [String: Any], writesToSource: Bool = false) async throws -> (Document, [String: Any]) {
            let name = suggestion["operation"] as! String, title = suggestion["title"] as! String
            let fixture = byName[name]!, previous = Set(v.documents.map(\.id))
            let count = report.reportEntries!.count
            v.tabs.selectTabViewItem(parent.item)
            try await wait { try await parent.web.evaluateJavaScript("Array.from(document.querySelectorAll('.follow-on button')).some(b=>b.textContent===\(v.jsString(title)))") as? Bool == true }
            _ = try await parent.web.evaluateJavaScript("Array.from(document.querySelectorAll('.follow-on button')).find(b=>b.textContent===\(v.jsString(title))).click();true")
            try await wait { v.documents.contains { !previous.contains($0.id) && $0.operationName == name } }
            let child = v.documents.first { !previous.contains($0.id) && $0.operationName == name }!
            do {
                try await wait { child.operationReady && !child.operationStarting && (child.completedJobID != nil || child.analysisJobID != nil) }
                try check(child.parentJobID == parent.completedJobID, "\(name) opened on another parent's result")
                var final: [String: Any] = [:]
                for _ in 0..<30 {
                    guard let id = child.completedJobID ?? child.analysisJobID else { throw NSError(domain: name, code: 1) }
                    let state = try await settled(v, id)
                    if state["state"] as? String == "complete" { final = state; break }
                    try check(state["state"] as? String == "input", "\(name) failed: \(state)")
                    let prompt = state["prompt"] as! [String: Any]
                    try check(prompt["error"] as? String == nil, "\(name) rejected its inputs: \(prompt)")
                    // Fill the visible React inputs using native setters/events. Never
                    // send a prepared answer directly across the operation bridge.
                    _ = try await child.web.callAsyncJavaScript(Self.fillControls, arguments: ["prompt": prompt, "steps": fixture["steps"]!], in: nil, contentWorld: .page)
                    try await wait { try await child.web.evaluateJavaScript("!!document.querySelector('form button[type=submit]:not(:disabled)') && !document.querySelector('form fieldset:disabled')") as? Bool == true }
                    let token = state["token"] as! Int
                    _ = try await child.web.evaluateJavaScript("document.querySelector('form').requestSubmit();true")
                    try await wait {
                        if child.completedJobID != nil { return true }
                        let next = try await request(v, ["action": "poll", "id": id])
                        return next["state"] as? String != "input" || next["token"] as? Int != token
                    }
                }
                try check(final["state"] as? String == "complete", "\(name) did not finish")
                try await wait { child.completedJobID != nil && report.reportEntries!.count == count + 1 }
                try check(v.active === report && report.reportEntries!.last!.operation == name, "\(name) did not append to the active report")
                let html = final["html"] as? String ?? "", frames = final["frames"] as? [[String: Any]] ?? []
                try check(!html.isEmpty || !frames.isEmpty, "\(name) produced no result")
                try check(!html.contains("Error rendering"), "\(name) report failed to render")
                if !frames.isEmpty {
                    let sheets = v.documents.filter { !previous.contains($0.id) && $0.kind == "grid" }
                    try check(sheets.count == (writesToSource ? 0 : frames.count), "\(name) lost worksheet output (expected \(writesToSource ? 0 : frames.count) new sheets, got \(sheets.count); entered=\(child.operationInputEntered), source=\(child.operationSnapshotSourceID ?? "none"))")
                    for sheet in sheets { v.remove(sheet) }
                }
                try check(v.methodHelpPath(child) != nil, "\(name) lost inherited help")
                tested.insert(name); paths += 1
                print("PASS native follow-on: \(parent.operationName!) → \(name)"); fflush(stdout)
                return (child, final)
            } catch {
                print("Follow-on diagnostic \(name):", (try? await child.web.evaluateJavaScript("document.body.innerText")) ?? "no page"); fflush(stdout)
                throw error
            }
        }

        for fixture in fixtures where fixture["parent"] == nil {
            let name = fixture["operation"] as! String, parent = parents[name]!, output = outputs[name]!
            for suggestion in output["suggestions"] as! [[String: Any]] {
                let (child, result) = try await follow(parent, suggestion)
                // Exercise a second link, including refitting a polynomial before
                // using its updated fit and a post-hoc test after another post-hoc.
                if child.operationName == "PolynomialRegressionChangeDegree" || (name == "OneWay" && child.operationName == "Tukey") {
                    for next in result["suggestions"] as! [[String: Any]] {
                        let (grandchild, _) = try await follow(child, next)
                        v.remove(grandchild)
                    }
                }
                v.remove(child)
            }
        }
        let expected = Set(fixtures.filter { $0["parent"] != nil }.map { $0["operation"] as! String })
        try check(tested == expected, "Missing native follow-ons: \(expected.subtracting(tested))")
        // Change both the visible worksheet and workbook after the fit. The
        // follow-on must still insert after its original selected columns.
        let source = v.newDocument(kind: "grid", title: "Original Cox data", url: v.root.appendingPathComponent("Grid/index.html"))
        try await wait { try await source.web.evaluateJavaScript("!!window.statsDirectGrid") as? Bool == true }
        let cox = parents["CoxRegression"]!, coxOutput = outputs["CoxRegression"]!
        let dataSteps = byName["CoxRegression"]!["steps"] as! [[String: Any]]
        let columns = ["times", "events", "predictors"].map { name in
            ((dataSteps.first { $0["name"] as? String == name }!["value"] as! [String: Any])["columns"] as! [[String: Any]])[0]["values"]!
        }
        _ = try await source.web.callAsyncJavaScript(#"""
        await statsDirectGrid.loadWorkbook({name:'Cox data',sheets:[
          {name:'Original',rows:13,columns:4,headerRow:true,cells:[
            ...['times','events','predictor','note'].map((text,col)=>({col,row:0,text,kind:'text'})),
            ...columns.flatMap((c,col)=>c.map((n,i)=>({col,row:i+1,text:String(n),kind:'number'}))),
            {col:3,row:1,text:'keep original note',kind:'text'}]},
          {name:'Other',rows:3,columns:2,headerRow:false,cells:[{col:0,row:0,text:'do not change',kind:'text'}]}]});
        return true;
        """#, arguments: ["columns": columns], in: nil, contentWorld: .page)
        try await wait { try await source.web.evaluateJavaScript("statsDirectGrid.analysisSource().sheetName==='Original'") as? Bool == true }
        var snapshot = try await source.web.evaluateJavaScript("statsDirectGrid.analysisSource()") as! [String: Any]
        snapshot["selection"] = [0, 1, 2]
        cox.operationSourceID = source.id; cox.operationSnapshotSourceID = source.id; cox.operationSourceSnapshot = snapshot
        cox.operationInputEntered = false; cox.operationInputRange = ["columns": [0, 1, 2], "firstRow": 2, "lastRow": 13]
        _ = try await source.web.evaluateJavaScript("document.querySelectorAll('.sheetbar button')[1].click();true")
        try await wait { try await source.web.evaluateJavaScript("statsDirectGrid.analysisSource().sheetName==='Other'") as? Bool == true }
        let otherBefore = try await source.web.evaluateJavaScript("statsDirectGrid.csvData()") as! String
        let unrelated = v.newDocument(kind: "grid", title: "Unrelated workbook", url: v.root.appendingPathComponent("Grid/index.html"))
        try await wait { try await unrelated.web.evaluateJavaScript("!!window.statsDirectGrid") as? Bool == true }
        let unrelatedBefore = try await unrelated.web.evaluateJavaScript("statsDirectGrid.csvData()") as! String
        let baseline = (coxOutput["suggestions"] as! [[String: Any]]).first { $0["operation"] as? String == "CoxBaselineToWorksheet" }!
        let (exported, _) = try await follow(cox, baseline, writesToSource: true)
        try check(exported.operationSourceSnapshot?["sheetName"] as? String == "Original", "Export changed the source for the next follow-on")
        let otherAfter = try await source.web.evaluateJavaScript("statsDirectGrid.csvData()") as! String
        let unrelatedAfter = try await unrelated.web.evaluateJavaScript("statsDirectGrid.csvData()") as! String
        try check(otherAfter == otherBefore && unrelatedAfter == unrelatedBefore, "Follow-on changed an unrelated sheet or workbook")
        _ = try await source.web.evaluateJavaScript("document.querySelectorAll('.sheetbar button')[0].click();true")
        try await wait { try await source.web.evaluateJavaScript("statsDirectGrid.analysisSource().sheetName==='Original'") as? Bool == true }
        let csv = try await source.web.evaluateJavaScript("statsDirectGrid.csvData()") as! String
        let headings = csv.components(separatedBy: .newlines)[0].components(separatedBy: ",")
        try check(Array(headings.prefix(3)) == ["times", "events", "predictor"] && headings.count > 4 && headings.last == "note" && csv.contains("keep original note"), "Follow-on ignored the original selected columns: \(headings)")
        print("PASS: follow-on writes to the original worksheet/range after changing sheet and workbook; unrelated data preserved")
        v.remove(exported); v.remove(source); v.remove(unrelated)
        print("PASS: \(paths) native parent/follow-on paths; all \(tested.count) follow-on operations; one active report; inherited help and worksheet output")
        for parent in parents.values { v.remove(parent) }
    }

    static let fillControls = #"""
    const tick=()=>new Promise(r=>setTimeout(r,0));
    const change=async(input,value)=>{
      if(!input)throw new Error('Missing input control');
      if(input.type==='checkbox'||input.type==='radio'){if(input.checked!==Boolean(value))input.click();}
      else {Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(input,String(value));input.dispatchEvent(new Event('input',{bubbles:true}));}
      await tick();
    };
    async function fill(p,root){
      if(p.kind==='form'){
        const children=Array.from(root.children).filter(e=>e.classList.contains('embedded-prompt'));
        for(let i=0;i<p.fields.length;i++)await fill(p.fields[i],children[i]);
        return;
      }
      const step=steps.find(s=>s.kind===p.kind&&(s.name===p.name||(s.name==null&&s.prompt===p.prompt)));
      if(!step)throw new Error('Unexpected follow-on prompt: '+JSON.stringify(p));
      const v=step.value;
      if(p.kind==='boolean'){
        const box=root.querySelector('input[type=checkbox]');
        if(box)await change(box,v);else await change(root.querySelectorAll('.yesno input')[v?0:1],true);
      } else if(['option','options','selectList'].includes(p.kind)){
        const inputs=root.querySelectorAll('.choices input'),offset=p.kind==='selectList'&&p.allowNone&&!p.multiple?1:0;
        if(offset&&v.length===0)await change(inputs[0],true);
        for(let i=0;i<p.options.length;i++){
          const key=p.options[i].value,wanted=p.kind==='options'?v[key]:p.kind==='option'?String(v)===String(key):v.includes(Number(key));
          if(inputs[i+offset].type==='checkbox'||wanted)await change(inputs[i+offset],wanted);
        }
      } else if(p.kind==='fields'){
        const inputs=root.querySelectorAll('.fields input');
        for(let i=0;i<p.fields.length;i++)await change(inputs[i],v[p.fields[i].name]);
      } else await change(root.querySelector('.field input'),v);
    }
    for(let attempt=0;attempt<100&&!document.querySelector('form');attempt++)await new Promise(r=>setTimeout(r,20));
    await fill(prompt,document.querySelector('form'));
    await new Promise(r=>setTimeout(r,450)); // allow combined-form validation previews to settle
    return true;
    """#
}
