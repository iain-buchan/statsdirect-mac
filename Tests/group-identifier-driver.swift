import Cocoa

struct GroupIdentifierTests {
    @MainActor static func run(_ v: Viewer) async throws {
        let defaults=UserDefaults.standard.object(forKey:"analysisDefaults")
        defer {UserDefaults.standard.set(defaults,forKey:"analysisDefaults")}
        UserDefaults.standard.removeObject(forKey:"analysisDefaults")
        let grid=v.newDocument(kind:"grid",title:"Group identifier fixture",url:v.root.appendingPathComponent("Grid/index.html"))
        defer {v.remove(grid)}
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:!!window.statsDirectGrid})"))?["ok"] as? Bool == true}
        _=try await BetaFeedbackTests.asyncJavaScript(grid,"await statsDirectGrid.loadWorkbook({name:'Long data',sheets:[{name:'Groups',columns:2,rows:12,headerRow:false,cells:Array.from({length:12},(_,r)=>[{col:0,row:r,text:String(r+1),kind:'number'},{col:1,row:r,text:r>=1&&r<=4?'A':'B',kind:'text'}]).flat()}]});return {ok:true};")
        _=try await v.learningJavaScript(grid,"({ok:statsDirectGrid.editCommand('selectAll','')})")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(grid,"({ok:statsDirectGrid.analysisSource().range?.last===12})"))?["ok"] as? Bool == true}

        func open(_ operation:String) async throws -> Document {
            let d=v.newDocument(kind:"operation",title:operation+" grouping fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
            d.operationSourceID=grid.id
            try await ProviderLearningTests.wait {d.operationReady && d.operationSourceSnapshot != nil}
            _=try await v.learningJavaScript(d,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.groupState=s;update(s);};return {ok:true};})()")
            d.operationName=operation;v.startOperation(d)
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:window.groupState?.prompt?.kind==='grid'&&!!document.querySelector('.layout-switch')})"))?["ok"] as? Bool == true}
            _=try await v.learningJavaScript(d,"({ok:(Array.from(document.querySelectorAll('.layout-switch button')).find(b=>b.textContent.includes('identified')).click(),true)})")
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:document.querySelectorAll('.roles fieldset').length===2})"))?["ok"] as? Bool == true}
            _=try await v.learningJavaScript(d,"({ok:(document.querySelectorAll('input[name=long-data]')[0].click(),document.querySelectorAll('input[name=long-ids]')[1].click(),true)})")
            return d
        }
        func rows(_ d:Document,_ first:Int,_ last:Int) async throws {
            _=try await v.learningJavaScript(d,"(()=>{const inputs=document.querySelectorAll('.row-range input'),set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;[\(first),\(last)].forEach((value,i)=>{set.call(inputs[i],String(value));inputs[i].dispatchEvent(new Event('input',{bubbles:true}));});return {ok:true};})()")
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:document.querySelectorAll('.row-range input')[0].value==='\(first)'&&document.querySelectorAll('.row-range input')[1].value==='\(last)'})"))?["ok"] as? Bool == true}
        }
        func submit(_ d:Document) async throws {
            _=try await v.learningJavaScript(d,"({ok:(document.querySelector('form').requestSubmit(),true)})")
        }
        func retry(_ d:Document,_ last:Int) async throws {
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(d,"({ok:groupState.prompt?.kind==='grid'&&!!groupState.prompt.error&&!!document.querySelector('.error')})"))?["ok"] as? Bool == true}
            let state=try await v.learningJavaScript(d,"({first:document.querySelectorAll('.row-range input')[0]?.value,last:document.querySelectorAll('.row-range input')[1]?.value,data:document.querySelectorAll('input[name=long-data]')[0]?.checked??false,identifier:document.querySelectorAll('input[name=long-ids]')[1]?.checked??false})")
            guard state["first"] as? String=="2",state["last"] as? String==String(last),state["data"] as? Bool==true,state["identifier"] as? Bool==true else {
                throw ChatGPTTutor.Failure(message:"Rejected grouping selection was not preserved: \(state)")
            }
        }

        let anova=try await open("OneWay");defer {v.remove(anova)}
        try await rows(anova,2,5);try await submit(anova) // Only group A: the engine rejects it.
        try await retry(anova,5)
        try await rows(anova,2,8);try await submit(anova)
        try await ProviderLearningTests.wait {anova.completedJobID != nil}
        let result=try await v.learningJavaScript(anova,"window.groupState")
        let history=result["history"] as! [[String:Any]],input=history.first{$0["name"] as? String=="data"}!["value"] as! [String:Any]
        let columns=input["columns"] as! [[String:Any]],range=input["range"] as! [String:Any]
        precondition(columns[0]["values"] as? [Int]==[2,3,4,5] && columns[1]["values"] as? [Int]==[6,7,8] && range["firstRow"] as? Int==2 && range["lastRow"] as? Int==8)
        let r=try RScriptGenerator.generate(operation:"OneWay",title:"Grouping fixture",output:result,resources:v.root)
        precondition(r.script.contains("c(2.0, 3.0, 4.0, 5.0)") && r.script.contains("c(6.0, 7.0, 8.0)"))
        precondition(UserDefaults.standard.dictionary(forKey:"analysisDefaults")?["selectGroupsByIdentifier"] as? Bool==true)
        print("PASS: native group roles and custom rows survive rejection; corrected selection reaches ANOVA, input history and R; layout preference saved")

        let paired=try await open("TPaired");defer {v.remove(paired)}
        try await rows(paired,2,6);try await submit(paired) // Unequal groups: decline padding.
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(paired,"({ok:groupState.prompt?.kind==='boolean'&&groupState.prompt.prompt.includes('unequal length')&&document.querySelectorAll('.yesno input').length===2})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(paired,"({ok:(document.querySelectorAll('.yesno input')[1].click(),true)})")
        try await submit(paired)
        do {try await retry(paired,6)} catch {
            print("Paired retry diagnostic",try await v.learningJavaScript(paired,"({state:groupState,text:document.body.innerText})"));fflush(stdout)
            throw error
        }
        print("PASS: declining the unequal-group warning preserves the original data roles and custom row range")

        _=try await BetaFeedbackTests.asyncJavaScript(grid,"await statsDirectGrid.loadWorkbook({name:'Nested long data',sheets:[{name:'Nested',columns:3,rows:12,headerRow:false,cells:[[1,2,3,2,3,5,4,5,7,6,7,9],['01','01','01','01','01','01','1','1','1','1','1','1'],['east','east','east','west','west','west','north','north','north','south','south','south']].flatMap((values,col)=>values.map((text,row)=>({col,row,text:String(text),kind:col?'text':'number'})))}]});return {ok:true};")
        let nested=v.newDocument(kind:"operation",title:"Nested identifiers fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
        defer {v.remove(nested)}
        nested.operationSourceID=grid.id
        try await ProviderLearningTests.wait {nested.operationReady && nested.operationSourceSnapshot != nil}
        _=try await v.learningJavaScript(nested,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.groupState=s;update(s);};return {ok:true};})()")
        nested.operationName="TwoWayNested";v.startOperation(nested)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(nested,"({ok:window.groupState?.prompt?.name==='layout2d'&&document.querySelectorAll('.choices input').length===2})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(nested,"({ok:(document.querySelectorAll('.choices input')[1].click(),true)})")
        try await submit(nested)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(nested,"({ok:document.querySelectorAll('.roles fieldset').length===3})"))?["ok"] as? Bool == true}
        // Entered data can return to the layout choice without filling a throwaway table.
        _=try await v.learningJavaScript(nested,"({ok:(Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Enter / paste data').click(),true)})")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(nested,"({ok:Array.from(document.querySelectorAll('button')).some(b=>b.textContent==='Use separate columns')})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(nested,"({ok:(Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Use separate columns').click(),true)})")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(nested,"({ok:groupState.prompt?.name==='layout2d'&&document.querySelectorAll('.choices input').length===2})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(nested,"({ok:(document.querySelectorAll('.choices input')[1].click(),true)})")
        try await submit(nested)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(nested,"({ok:document.querySelectorAll('.roles fieldset').length===3})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(nested,"({ok:(document.querySelectorAll('input[name=long-data]')[0].click(),document.querySelectorAll('input[name=long-ids]')[1].click(),document.querySelectorAll('input[name=long-block]')[2].click(),true)})")
        try await submit(nested)
        try await ProviderLearningTests.wait {nested.completedJobID != nil}
        let nestedResult=try await v.learningJavaScript(nested,"window.groupState")
        let nestedHistory=nestedResult["history"] as! [[String:Any]]
        let nestedColumns=(nestedHistory.first{$0["name"] as? String=="data2d"}!["value"] as! [String:Any])["columns"] as! [[String:Any]]
        precondition(nestedColumns.count==3 && nestedColumns[1]["mode"] as? String=="GroupIdentifiers")
        let nestedR=try RScriptGenerator.generate(operation:"TwoWayNested",title:"Nested fixture",output:nestedResult,resources:v.root)
        precondition(nestedR.script.contains("c(\"01\", \"01\"") && nestedR.script.contains("\"north\""))
        print("PASS: native nested group/subgroup selection and layout fallback; distinct subgroups calculate; numeric-looking group identifiers stay as text in R")

        // Analysis of covariance from long data: a predictor column, two Y replicate columns and a group identifier column.
        _=try await BetaFeedbackTests.asyncJavaScript(grid,"await statsDirectGrid.loadWorkbook({name:'Covariance long data',sheets:[{name:'Covariance',columns:4,rows:6,headerRow:false,cells:[[1,2,3,2,3,4],[2,3,5,3,6,8],[3,4,6,4,7,9],['a','a','a','b','b','b']].flatMap((values,col)=>values.map((text,row)=>({col,row,text:String(text),kind:col<3?'number':'text'})))}]});return {ok:true};")
        let covariance=v.newDocument(kind:"operation",title:"Covariance identifiers fixture",url:v.root.appendingPathComponent("Grid/operation.html"))
        defer {v.remove(covariance)}
        covariance.operationSourceID=grid.id
        try await ProviderLearningTests.wait {covariance.operationReady && covariance.operationSourceSnapshot != nil}
        _=try await v.learningJavaScript(covariance,"(()=>{const update=statsDirectOperation.update;statsDirectOperation.update=s=>{window.groupState=s;update(s);};return {ok:true};})()")
        covariance.operationName="GroupedCovariance";v.startOperation(covariance)
        do {
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(covariance,"({ok:window.groupState?.prompt?.name==='layoutCovariance'&&document.querySelectorAll('.choices input').length===2})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(covariance,"({ok:(document.querySelectorAll('.choices input')[1].click(),true)})")
        try await submit(covariance)
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(covariance,"({ok:groupState.prompt?.name==='gcd'&&document.querySelectorAll('.roles fieldset').length===3&&document.querySelectorAll('input[name=long-outcomes]').length===4})"))?["ok"] as? Bool == true}
        _=try await v.learningJavaScript(covariance,"({ok:(document.querySelectorAll('input[name=long-data]')[0].click(),document.querySelectorAll('input[name=long-ids]')[3].click(),document.querySelectorAll('input[name=long-outcomes]')[1].click(),document.querySelectorAll('input[name=long-outcomes]')[2].click(),true)})")
        try await ProviderLearningTests.wait {(try? await v.learningJavaScript(covariance,"({ok:(document.querySelector('.selection')?.textContent??'').includes('Y:')&&document.querySelectorAll('input[name=long-outcomes]:checked').length===2})"))?["ok"] as? Bool == true}
        var covToken=(try await v.learningJavaScript(covariance,"({token:String(groupState.token)})"))["token"] as? String ?? ""
        try await submit(covariance)
        // The confidence level and the baseline mean for the predictors keep their defaults.
        for _ in 0..<2 {
            let previous=covToken
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(covariance,"({ok:groupState.state==='input'&&String(groupState.token)!=='\(previous)'&&!groupState.prompt?.error})"))?["ok"] as? Bool == true}
            covToken=(try await v.learningJavaScript(covariance,"({token:String(groupState.token)})"))["token"] as? String ?? ""
            try await submit(covariance)
        }
        try await ProviderLearningTests.wait {covariance.completedJobID != nil}
        } catch {
            print("Covariance diagnostic",try await v.learningJavaScript(covariance,"({state:groupState,text:document.body.innerText})"));fflush(stdout)
            throw error
        }
        let covResult=try await v.learningJavaScript(covariance,"window.groupState")
        let covHistory=covResult["history"] as? [[String:Any]] ?? []
        let covRecord=covHistory.first{$0["name"] as? String=="gcd"}?["value"] as? [String:Any] ?? [:]
        let covColumns=covRecord["columns"] as? [[String:Any]] ?? []
        try check(covColumns.count==4 && covColumns[3]["mode"] as? String=="GroupIdentifiers" && (covRecord["roles"] as? [String:Any])?["outcomes"] as? Int==2, "covariance record: \(covRecord)")
        try check(covHistory.first{$0["name"] as? String=="layoutCovariance"}?["value"] as? String=="identifiers", "layout record missing")
        let covR=try RScriptGenerator.generate(operation:"GroupedCovariance",title:"Covariance fixture",output:covResult,resources:v.root)
        try check(covR.script.contains("\"a\"") && covR.script.contains("data_frames[["), "covariance R script")
        print("PASS: native analysis of covariance from long data: the layout choice, the X, Y replicate and identifier roles reach the engine, the input history and R")

    }
}
