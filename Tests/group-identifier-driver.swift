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
    }
}
