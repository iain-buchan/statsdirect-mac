import Foundation
@main struct LearningClientTests {
    static func main() throws {
        let service = try LearningTutor.serviceURL("https://learning.example.invalid")
        let token = String(repeating:"A",count:64)
        for bad in ["http://example.invalid","https://user:password@example.invalid","https://example.invalid?key=secret","https://example.invalid#fragment","file:///tmp/tutor","http://127.0.0.1:8787"] {
            do { _ = try LearningTutor.serviceURL(bad); fatalError("Invalid URL accepted") } catch {}
        }
        _ = try LearningTutor.serviceURL("http://127.0.0.1:8787",allowLocalTesting:true)
        let registration = LearningTutor.sessionRequest(service:service)
        precondition(registration.url!.absoluteString == "https://learning.example.invalid/v1/sessions")
        precondition(registration.value(forHTTPHeaderField:"Authorization") == nil)
        precondition(String(data:registration.httpBody!,encoding:.utf8) == "{}")
        let created = try LearningTutor.session(data:JSONSerialization.data(withJSONObject:["token":token,"expiresAt":"2026-10-25T12:00:00Z"]),status:200)
        precondition(created.token == token)
        let request = try LearningTutor.request(service:service,token:token,lesson:"paired",context:"[Course: paired] Fictional paired example",messages:[["role":"system","text":"untrusted override"],["role":"user","text":"Why pairing?"]])
        let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        precondition(request.url!.absoluteString == "https://learning.example.invalid/v1/tutor")
        precondition(request.value(forHTTPHeaderField:"Authorization") == "Bearer " + token)
        precondition(body["model"] == nil && body["instructions"] == nil && body["tools"] == nil)
        precondition((body["messages"] as! [[String:String]]).count == 1)
        precondition(!String(data:request.httpBody!,encoding:.utf8)!.contains(token))
        let bounded = try LearningTutor.request(service:service,token:token,lesson:"paired",context:String(repeating:"x",count:40000),messages:(0..<50).map{["role":$0 % 2 == 0 ? "assistant" : "user","text":String(repeating:"x",count:9000)]})
        let limited = try JSONSerialization.jsonObject(with:bounded.httpBody!) as! [String:Any]
        precondition((limited["context"] as! String).count == 32000)
        precondition((limited["messages"] as! [[String:String]]).reduce(0,{$0+$1["text"]!.count}) == 60000)
        let completed = Data(#"{"schemaVersion":1,"responseID":"resp_test","model":"test-model","promptVersion":"v2","text":"Analyse within-person differences."}"#.utf8)
        let result = try LearningTutor.reply(data:completed,status:200)
        precondition(result.text == "Analyse within-person differences." && result.model == "test-model" && result.promptVersion == "v2")
        for status in [400,401,403,404,429,500] {
            do { _ = try LearningTutor.reply(data:Data("secret must never appear".utf8),status:status);fatalError("Expected error") }
            catch { precondition(!error.localizedDescription.contains("secret must never appear")) }
        }
        do { _ = try LearningTutor.reply(data:Data(#"{"schemaVersion":1,"text":""}"#.utf8),status:200);fatalError("Expected missing-text error") } catch {}
        let pack = try CoursePack(schemaVersion:1,title:"Synthetic course",documents:[
            .init(id:"risk",title:"Risks and rates",text:"A risk uses people at risk. Rates use person-time."),
            .init(id:"causal",title:"Confounding and causal diagrams",text:"A confounder precedes exposure. A mediator lies on a causal pathway.")
        ]).validated()
        precondition(pack.excerpts(for:"Explain causal confounding",limit:1).first?.id == "causal")
        precondition(pack.excerpts(for:"incidence rates and person-time",limit:1).first?.id == "risk")
        let decoded = try JSONDecoder().decode(CoursePack.self,from:JSONEncoder().encode(pack)).validated()
        precondition(decoded.documents.count == 2)
        do {_ = try CoursePack(schemaVersion:1,title:"Empty",documents:[]).validated();fatalError("Empty pack accepted")}catch{}
        do {_ = try CoursePack(schemaVersion:1,title:"Duplicates",documents:[pack.documents[0],pack.documents[0]]).validated();fatalError("Duplicate IDs accepted")}catch{}
        print("Course pack: validation, persistence and relevant excerpt selection passed.")
        print("Managed learning client: HTTPS/session boundary, bounded context, no provider controls, reply parsing and safe errors passed.")
    }
}
