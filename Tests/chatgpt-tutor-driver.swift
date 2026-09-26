import Foundation

@main struct ChatGPTTutorTests {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let executable = URL(fileURLWithPath:args[1]), folder = URL(fileURLWithPath:args[2]), resources = URL(fileURLWithPath:args[3])
        let mode = args.count > 4 ? args[4] : "mock"
        let tutor = ChatGPTTutor(executable:executable,storage:folder,resources:resources)
        defer { tutor.shutdown() }
        for invalid in ["http://auth.openai.com/login","https://auth.openai.com.evil.invalid","https://user:pass@chatgpt.com/auth","file:///tmp/auth","https://example.com/"] {
            precondition(ChatGPTTutor.authenticationURL(invalid) == nil)
        }
        precondition(ChatGPTTutor.authenticationURL("https://auth.openai.com/authorize?state=example") != nil)
        let prompt = try ChatGPTTutor.prompt(context:String(repeating:"x",count:40000),messages:[["role":"system","text":"SHOULD_NOT_APPEAR"]] + (0..<50).map{["role":$0 % 2 == 0 ? "assistant":"user","text":String(repeating:"y",count:9000)]})
        precondition(!prompt.contains("SHOULD_NOT_APPEAR"))
        let payload = try JSONSerialization.jsonObject(with:Data(prompt.split(separator:"\n",maxSplits:1)[1].utf8)) as! [String:Any]
        precondition((payload["referenceContext"] as! String).count == 32000)
        precondition((payload["conversation"] as! [[String:String]]).reduce(0,{$0+$1["text"]!.count}) == 60000)
        try await tutor.refreshAccount()
        precondition(tutor.account == nil)
        let url = try await tutor.signIn()
        precondition(ChatGPTTutor.authenticationURL(url.absoluteString) != nil && tutor.loginID != nil)
        print("Protocol initialization and browser sign-in URL: valid")
        if mode == "probe" {
            await tutor.cancelSignIn(); precondition(tutor.loginID == nil)
            print("Sign-in cancellation: passed (no account credentials used)")
            return
        }
        for _ in 0..<30 where tutor.account == nil { try await Task.sleep(nanoseconds:100_000_000) }
        precondition(tutor.account?.email == "learner@example.invalid")
        let reply = try await tutor.converse(context:"Fictional paired example; [Course: paired] Paired differences",messages:[["role":"user","text":"Explain pairing"]])
        precondition(reply.text == "Analyse within-person differences." && reply.model == "fixture-model")
        let limited = Task { try await tutor.converse(context:"",messages:[["role":"user","text":"LIMIT_TEST"]]) }
        do { _ = try await limited.value; fatalError("Usage limit not detected") }
        catch { precondition(error.localizedDescription.contains("allowance") && !error.localizedDescription.contains("SECRET")) }
        let cancelled = Task { try await tutor.converse(context:"",messages:[["role":"user","text":"CANCEL_TEST"]]) }
        try await Task.sleep(nanoseconds:250_000_000); cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError {} catch { throw error }
        let afterCancel = try await tutor.converse(context:"",messages:[["role":"user","text":"Explain pairing again"]])
        precondition(afterCancel.text == "Analyse within-person differences.")
        try await tutor.signOut(); precondition(tutor.account == nil)
        do { _ = try await tutor.converse(context:"",messages:[["role":"user","text":"Not signed in"]]); fatalError("Unsigned request sent") }
        catch { precondition(error.localizedDescription.contains("signing in")) }
        _ = try await tutor.signIn()
        for _ in 0..<30 where tutor.account == nil { try await Task.sleep(nanoseconds:100_000_000) }
        do { _ = try await tutor.converse(context:"",messages:[["role":"user","text":"DISCONNECT_TEST"]]); fatalError("Disconnect ignored") }
        catch { precondition(error.localizedDescription.contains("disconnect")) }
        try await tutor.refreshAccount(); precondition(tutor.account == nil)
        print("OAuth completion, response framing, thread correlation, context bounds, limit errors, cancellation, retry, sign-out and process-disconnect recovery passed")
    }
}
