import Cocoa

struct FormContractTests {
    @MainActor static func run(_ v: Viewer) async throws {
        let defaults=UserDefaults.standard.object(forKey:"analysisDefaults")
        defer {UserDefaults.standard.set(defaults,forKey:"analysisDefaults")}
        UserDefaults.standard.removeObject(forKey:"analysisDefaults")
        let grid=v.newDocument(kind:"grid",title:"Form contract fixture",url:v.root.appendingPathComponent("Grid/index.html"))
        defer {v.remove(grid)}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}

        func load(_ data:String) async throws {
            _=try await BetaFeedbackTests.asyncJavaScript(grid,"const columns="+data+";await statsDirectGrid.loadWorkbook({name:'Form fixture',sheets:[{name:'Data',columns:columns.length,rows:columns[0].length,headerRow:false,cells:columns.flatMap((values,col)=>values.map((text,row)=>({col,row,text:String(text),kind:'number'})))}]});return {ok:true};")
            // Workbook loading schedules a React render. Select after its column model updates,
            // as a user would, rather than selecting the previous workbook in the same JS turn.
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().columns.length===("+data+").length})"))?["ok"] as? Bool == true}
            _=try await v.learningJavaScript(grid,"({ok:statsDirectGrid.editCommand('selectAll','')})")
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().range?.last===("+data+")[0].length&&statsDirectGrid.analysisSource().selection.length===("+data+").length})"))?["ok"] as? Bool == true}
        }
        func open(_ operation:String) async throws -> Document {
            let d=v.newDocument(kind:"operation",title:operation+" form fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
            d.operationSourceID=grid.id
            try await ProviderLearningTests.wait {d.operationReady && d.operationSourceSnapshot != nil}
            _=try await v.learningJavaScript(d,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.formState=s;update(s);};return {ok:true};})()")
            d.operationName=operation;v.startOperation(d)
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:window.formState?.state==='input'&&!!document.querySelector('form')})"))?["ok"] as? Bool == true}
            return d
        }
        func submit(_ d:Document) async throws {
            _=try await v.learningJavaScript(d,"({ok:(document.querySelector('form').requestSubmit(),true)})")
        }
        func check(_ d:Document,_ predicate:String,_ message:String) async throws {
            let result=try await v.learningJavaScript(d,"({ok:("+predicate+"),text:document.body.innerText})")
            guard result["ok"] as? Bool == true else {throw ChatGPTTutor.Failure(message:message+": "+String(describing:result))}
        }
        try await load("[[1,2,3,4],[3,4,5,6],[6,7,8,9]]")
        let cuzick=try await open("Cuzick")
        defer {v.remove(cuzick)}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(cuzick,"({ok:document.querySelectorAll('.column-chooser input:checked').length===3})"))?["ok"] as? Bool == true}
        try await submit(cuzick)
        do {
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(cuzick,"({ok:formState.prompt?.name==='scores'&&!!document.querySelector('.grid-tools')&&!!document.querySelector('[aria-label=\"Selected data cell\"]')?.value})"))?["ok"] as? Bool == true}
        } catch {
            print("Cuzick native form diagnostic:",try await v.learningJavaScript(cuzick,"({state:formState,text:document.body.innerText,inputs:statsDirectOperation.tutorSnapshot()})"));fflush(stdout)
            throw error
        }
        try await check(cuzick,"document.querySelector('.grid-tools').textContent.includes('3 rows × 1 columns')&&JSON.stringify(statsDirectOperation.tutorSnapshot().inputs[0].value.columns[0].values)==='[\"1\",\"2\",\"3\"]'","Engine-prepared Cuzick scores must replace the selected worksheet data")
        // Edit the actual React-controlled cell, submit it, and check the rejected value survives.
        _=try await v.learningJavaScript(cuzick,"(()=>{const input=document.querySelector('[aria-label=\"Selected data cell\"]');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(input,'-1');input.dispatchEvent(new Event('input',{bubbles:true}));return {ok:true};})()")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(cuzick,"({ok:statsDirectOperation.tutorSnapshot().inputs[0]?.value?.columns[0].values[0]==='-1'})"))?["ok"] as? Bool == true}
        try await submit(cuzick)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(cuzick,"({ok:!!formState.prompt?.error&&document.querySelector('[aria-label=\"Selected data cell\"]')?.value==='-1'})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(cuzick,#"({ok:(statsDirectOperation.pasteText('1\n2\n4'),true)})"#)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(cuzick,"({ok:JSON.stringify(statsDirectOperation.tutorSnapshot().inputs[0]?.value?.columns[0].values)==='[\"1\",\"2\",\"4\"]'})"))?["ok"] as? Bool == true}
        try await submit(cuzick)
        try await ProviderLearningTests.wait {cuzick.completedJobID != nil}
        try await check(cuzick,"formState.state==='complete'&&JSON.stringify(formState.history.find(h=>h.name==='scores').value.columns[0].values.map(Number))==='[1,2,4]'","Custom scores must reach the calculation engine")
        print("PASS: native Cuzick scores render as 1/2/3 despite a selected worksheet; edits survive rejection; corrected 1/2/4 scores reach the engine")

        try await load("[[20,10,15,10],[10,20,10,25]]")
        for operation in ["ChiWoolfScreen","MantelHaenszelScreen"] {
            let d=try await open(operation)
            defer {v.remove(d)}
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:!!document.querySelector('.grid-tools')&&document.querySelector('[aria-label=\"Selected data cell\"]')?.value==='20'})"))?["ok"] as? Bool == true}
            try await check(d,"!document.querySelector('.column-chooser')&&JSON.stringify(statsDirectOperation.tutorSnapshot().inputs[0].value.columns.map(c=>c.values))==='[[\"20\",\"10\",\"15\",\"10\"],[\"10\",\"20\",\"10\",\"25\"]]'",operation+" must open an embedded table with the highlighted worksheet values")
        }
        print("PASS: native Woolf and Mantel–Haenszel open embedded tables and copy the selected strata without extra clicks")
    }
}
