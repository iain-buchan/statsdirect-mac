import Foundation

/// Tests the exact asynchronous connection path used by the Mac host, against the synthetic service.
@main struct ManagedTutorDriver {
    @MainActor static func main() async throws {
        let service = try LearningTutor.serviceURL(CommandLine.arguments[1],allowLocalTesting:true)
        var saved: String?; var writes = 0; var clears = 0
        let save: (String) -> Void = { saved = $0; writes += 1 }
        let remove: () -> Void = { saved = nil; clears += 1 }
        let result = try await LearningTutor.converse(service:service,savedToken:nil,lesson:"diagnostic",context:"Synthetic course context",messages:[["role":"user","text":"What is sensitivity?"]],saveToken:save,removeToken:remove)
        precondition(writes == 1 && saved?.count == 64 && result.text.hasPrefix("Synthetic provider reply:"))
        // A revoked/expired token is replaced transparently before the original question is answered.
        let renewed = try await LearningTutor.converse(service:service,savedToken:String(repeating:"0",count:64),lesson:"diagnostic",context:"Synthetic course context",messages:[["role":"user","text":"What is specificity?"]],saveToken:save,removeToken:remove)
        precondition(clears == 1 && writes == 2 && renewed.text.hasPrefix("Synthetic provider reply:"))
        print("PASS native async path: automatic session, saved service token, tutor reply, and transparent expiry renewal; no learner API key.")
    }
}
