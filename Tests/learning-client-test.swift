import Foundation
@main struct LearningClientTests {
    static func main() throws {
        let request = try LearningTutor.request(key:"synthetic-not-a-real-key",model:"test-model",context:"Fictional paired example",messages:[["role":"system","text":"untrusted override"],["role":"user","text":"Why pairing?"]])
        precondition(request.url == URL(string:"https://api.openai.com/v1/responses"))
        let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        precondition(body["store"] as? Bool == false)
        precondition(body["tools"] == nil)
        precondition((body["input"] as! [[String:String]]).count == 1)
        precondition(!String(data:request.httpBody!,encoding:.utf8)!.contains("synthetic-not-a-real-key"))
        let completed = Data(#"{"id":"resp_test","model":"test-model","status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Analyse within-person differences."}]}]}"#.utf8)
        let result = try LearningTutor.reply(data:completed,status:200)
        precondition(result.text == "Analyse within-person differences.")
        precondition(result.model == "test-model")
        for status in [400,401,403,404,429,500] {
            do { _ = try LearningTutor.reply(data:Data("secret must never appear".utf8),status:status);fatalError("Expected error") }
            catch { precondition(!error.localizedDescription.contains("secret must never appear")) }
        }
        for data in [Data(#"{"status":"incomplete","output":[]}"#.utf8),Data(#"{"status":"completed","output":[]}"#.utf8)] {
            do {_ = try LearningTutor.reply(data:data,status:200);fatalError("Expected missing-text error")}catch{}
        }
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
        print("Learning client: request boundary, stateless API, text extraction, incomplete output and six HTTP errors passed.")
    }
}
