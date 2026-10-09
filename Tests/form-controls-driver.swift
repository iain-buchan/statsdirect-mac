import Cocoa
import WebKit

@MainActor final class FormAnswerCapture: NSObject, WKScriptMessageHandler {
    var answer:[String:Any]?
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        if let body=message.body as? [String:Any],body["action"] as? String=="answer" {answer=body}
    }
}
struct FormControlTests {
    @MainActor static func run(_ v:Viewer) async throws {
        let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/form-controls.json")
        let fixtures=try JSONSerialization.jsonObject(with:Data(contentsOf:path)) as! [[String:Any]]
        let doc=v.newDocument(kind:"operation",title:"Shared form controls",url:v.root.appendingPathComponent("Grid/operation.html"))
        defer {v.remove(doc)}
        try await ProviderLearningTests.wait {doc.operationReady}
        let capture=FormAnswerCapture(),controller=doc.web.configuration.userContentController
        controller.removeScriptMessageHandler(forName:"statsDirectOperation")
        controller.add(capture,name:"statsDirectOperation")
        _=try await v.learningJavaScript(doc,"({ok:(window.formEqual=(a,b)=>Object.is(a,b)||(a&&b&&typeof a==='object'&&typeof b==='object'&&Array.isArray(a)===Array.isArray(b)&&Object.keys(a).length===Object.keys(b).length&&Object.keys(a).every(k=>Object.hasOwn(b,k)&&formEqual(a[k],b[k]))),true)})")
        var token=10000
        for prompt in fixtures {
            print("Native control fixture:",prompt["kind"]!,prompt["name"] ?? "unnamed");fflush(stdout)
            token+=1;capture.answer=nil
            var fixture=prompt;fixture["name"]="control-\(token)";fixture["error"]=NSNull()
            let data=try JSONSerialization.data(withJSONObject:fixture),json=String(decoding:data,as:UTF8.self)
            _=try await v.learningJavaScript(doc,"({ok:(window.controlFixture=\(json),statsDirectOperation.update({state:'input',token:\(token),prompt:controlFixture}),true)})")
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(doc,"({ok:statsDirectOperation.tutorSnapshot().inputs[0]?.name==='control-\(token)'})"))?["ok"] as? Bool==true}
            let result=try await v.learningJavaScript(doc,"""
            (()=>{const p=controlFixture,v=statsDirectOperation.tutorSnapshot().inputs[0].value;
            const expected=p.kind==='options'?Object.fromEntries(p.options.map(o=>[o.value,o.selected])):p.kind==='fields'?Object.fromEntries(p.fields.map(f=>[f.name,f.defaultValue])):p.defaultValue;
            const checked=p.kind==='selectList'?document.querySelectorAll('.choices input:checked').length:p.kind==='option'?document.querySelectorAll('.choices input:checked').length:0;
            return {ok:JSON.stringify(v)===JSON.stringify(expected)&&(!['selectList','option'].includes(p.kind)||checked>0||p.multiple),kind:p.kind,value:v,expected,checked};})()
            """)
            guard result["ok"] as? Bool==true else {throw ChatGPTTutor.Failure(message:"Native default mismatch: \(result)")}
            if fixture["kind"] as? String=="selectList",fixture["allowNone"] as? Bool==true,fixture["multiple"] as? Bool==false {
                _=try await v.learningJavaScript(doc,"({ok:(document.querySelectorAll('.choices input')[1].click(),true)})")
                try await ProviderLearningTests.wait {(try? await v.learningJavaScript(doc,"({ok:statsDirectOperation.tutorSnapshot().inputs[0].value.length===1})"))?["ok"] as? Bool==true}
                _=try await v.learningJavaScript(doc,"({ok:(document.querySelectorAll('.choices input')[0].click(),true)})")
                try await ProviderLearningTests.wait {(try? await v.learningJavaScript(doc,"({ok:statsDirectOperation.tutorSnapshot().inputs[0].value.length===0})"))?["ok"] as? Bool==true}
            }
            let validity=try await v.learningJavaScript(doc,"({ok:document.querySelector('form').checkValidity(),invalid:Array.from(document.querySelectorAll(':invalid')).map(x=>({name:x.name,value:x.value,min:x.min,max:x.max,message:x.validationMessage}))})")
            guard validity["ok"] as? Bool==true else {throw ChatGPTTutor.Failure(message:"Invalid native test fixture: \(validity)")}
            _=try await v.learningJavaScript(doc,"({ok:(document.querySelector('form').requestSubmit(),true)})")
            try await ProviderLearningTests.wait {capture.answer != nil}
            // Simulate rejection at the real prompt boundary; the previously submitted
            // answer must remain editable rather than reverting to a generated default.
            let sent=try JSONSerialization.data(withJSONObject:capture.answer!["value"]!,options:[.fragmentsAllowed]),sentJSON=String(decoding:sent,as:UTF8.self)
            token+=1
            _=try await v.learningJavaScript(doc,"({ok:(statsDirectOperation.update({state:'input',token:\(token),prompt:{...controlFixture,error:'Correct this test value'}}),true)})")
            try await ProviderLearningTests.wait {(try? await v.learningJavaScript(doc,"({ok:!!document.querySelector('[role=alert]')&&formEqual(statsDirectOperation.tutorSnapshot().inputs[0]?.value,\(sentJSON))})"))?["ok"] as? Bool==true}
        }
        print("PASS: \(fixtures.count) native shared control variants retain engine defaults, submit and restore rejected answers; optional single-choice lists can return to None")
    }
}
