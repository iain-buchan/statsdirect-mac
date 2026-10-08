import Foundation

@main struct TutorPolicyTests {
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let storage=root.appendingPathComponent(".build/policy-"+UUID().uuidString+"/chatgpt-mock")
        let old=UserDefaults.standard.object(forKey:"DisableOnlineTutor")
        let tutor=ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:storage,resources:root.appendingPathComponent("Content/Tutor"))
        defer {tutor.shutdown();UserDefaults.standard.set(old,forKey:"DisableOnlineTutor");try? FileManager.default.removeItem(at:storage)}
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        for action in 0..<3 {
            do {
                if action==0 {try await tutor.refreshAccount()}
                else if action==1 {_=try await tutor.signIn()}
                else {_=try await tutor.converse(context:"",messages:[["role":"user","text":"Synthetic blocked question"]])}
                fatalError("Institutional policy was ignored")
            } catch {precondition(error.localizedDescription.contains("disabled"))}
        }
        precondition(!FileManager.default.fileExists(atPath:storage.path))
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        _=try await tutor.signIn()
        for _ in 0..<30 where tutor.account == nil {try await Task.sleep(nanoseconds:100_000_000)}
        precondition(tutor.account != nil)
        let running=Task {try await tutor.converse(context:"",messages:[["role":"user","text":"CANCEL_TEST"]])}
        try await Task.sleep(nanoseconds:150_000_000)
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        do {_=try await running.value;fatalError("Active tutor continued after policy changed")}
        catch {precondition(error.localizedDescription.contains("disabled"))}
        precondition(tutor.account == nil)
        print("PASS: institutional policy prevents runtime startup, sign-in and questions, and stops an existing connection and reply")
    }
}
