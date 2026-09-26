import Foundation
import Darwin
private typealias Invoke = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
@main struct TutorEngineTests {
    @MainActor static func main() async {
        do { try await run() } catch { print("FAIL",error.localizedDescription); exit(1) }
    }
    @MainActor static func run() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let handle=dlopen(root.appendingPathComponent("FullEngine/publish/StatsDirectEngine.dylib").path,RTLD_NOW|RTLD_LOCAL)!
        let invoke=unsafeBitCast(dlsym(handle,"statsdirect_operation"),to:Invoke.self), free=unsafeBitCast(dlsym(handle,"statsdirect_operation_free"),to:Free.self)
        func request(_ input:[String:Any]) async throws -> [String:Any] {
            let json=String(decoding:try JSONSerialization.data(withJSONObject:input),as:UTF8.self)
            let pointer=json.withCString{invoke($0)}!;defer{free(pointer)}
            let output = try JSONSerialization.jsonObject(with:Data(String(cString:pointer).utf8)) as! [String:Any]
            if let error = output["error"] as? String { print("ENGINE",error) }
            return output
        }
        func dataset(_ columns:[[Any]]) -> [String:Any] {
            ["complete":true,"hasErrors":false,"hasStaleFormulas":false,"rowCount":columns[0].count,"firstRow":2,"lastRow":columns[0].count+1,"workbook":"test.xlsx","sheet":"PEFR","range":"A, B · rows 2–10","columns":columns.enumerated().map{["index":$0.offset,"title":$0.offset==0 ? "PEFR Before":"PEFR After","values":$0.element]}]
        }
        let a:[Any]=[312,242,340,388,296,254,391,402,290],b:[Any]=[300,201,232,312,220,256,328,330,231]
        let data=dataset([a,b])
        let paired=try await TutorTools.run(operation:"TPaired",dataset:data,agreement:true,preferences:[:],request:request)
        let html=paired["html"] as! String
        precondition(html.contains("56.111111") && html.contains("<svg") && html.contains("95%"))
        let report=try JSONSerialization.data(withJSONObject:paired,options:[.prettyPrinted,.sortedKeys]);try report.write(to:root.appendingPathComponent(".build/tutor-paired-output.json"))
        let plan=try RScriptGenerator.generate(operation:"TPaired",title:"Paired t test",output:paired,resources:root.appendingPathComponent("Content"))
        try plan.script.write(to:root.appendingPathComponent(".build/tutor-paired.R"),atomically:true,encoding:.utf8)
        print("PASS: actual engine paired t test, default 95% interval, agreement SVG and equivalent R script")
        for name in TutorTools.operations where name != "TPaired" {
            let values:[[Any]] = ["Chi2by2","ExactFisher"].contains(name) ? [[20,10],[10,20]] : ["UnivariateSummary","QuickSummary","Normality"].contains(name) ? [a] : [a,b]
            let result=try await TutorTools.run(operation:name,dataset:dataset(values),agreement:false,studyType:"neither",preferences:[:],request:request)
            precondition(result["state"] as? String == "complete"); print("PASS: " + name)
        }
        var missing=a;missing[2]=NSNull()
        let result=try await TutorTools.run(operation:"TPaired",dataset:dataset([missing,b]),agreement:true,preferences:[:],request:request)
        let missingValues=result["values"] as! [String:Any]
        precondition((missingValues["n"] as! NSNumber).intValue == 8 && abs((missingValues["mean"] as! NSNumber).doubleValue - 49.625)<1e-10)
        precondition((result["html"] as! String).components(separatedBy:"<ellipse").count - 1 == 8)
        do {_=try TutorTools.answer(["kind":"option","name":"study_type","defaultValue":"casecontrol"],frame:[:],agreement:false);fatalError("Guessed the study design")}catch{}
        do {_=try TutorTools.answer(["kind":"grid","minColumns":2,"maxColumns":2,"fixedRows":true,"rows":2],frame:TutorTools.frame(data),agreement:false);fatalError("Cropped a table")}catch{}
        try JSONSerialization.data(withJSONObject:result).write(to:root.appendingPathComponent(".build/tutor-missing-output.json"))
        var bad=data;bad["hasStaleFormulas"]=true
        do {_=try TutorTools.frame(bad);fatalError("Stale formula accepted")}catch{}
        do {_=try TutorTools.answer(["kind":"option","options":[]],frame:[:],agreement:false);fatalError("Guessed an unspecified choice")}catch{}
        try await Task.sleep(nanoseconds:200_000_000)
        print("PASS: missing pairs retain row positions; stale formulas and unspecified choices are refused")
    }
}
