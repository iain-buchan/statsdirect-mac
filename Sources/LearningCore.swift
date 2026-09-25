import Foundation

/// The Mac connects to a managed StatsDirect service. Provider credentials stay on that server.
enum LearningTutor {
    struct Failure: LocalizedError {
        let message: String
        var code: String = "unavailable"
        var errorDescription: String? { message }
    }
    struct Session: Codable { let token: String; let expiresAt: String }
    static func serviceURL(_ value: String, allowLocalTesting: Bool = false) throws -> URL {
        guard let url = URL(string:value), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || allowLocalTesting && url.scheme == "http" && host == "127.0.0.1" else {
            throw Failure(message:"The tutor connection needs an HTTPS service address from StatsDirect or your course provider.")
        }
        return url
    }
    static func sessionRequest(service: URL) -> URLRequest {
        var request = URLRequest(url:service.appendingPathComponent("v1/sessions"))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = Data("{}".utf8); return request
    }
    static func session(data: Data, status: Int) throws -> Session {
        try check(status:status,data:data)
        guard data.count <= 16_000, let result = try? JSONDecoder().decode(Session.self,from:data),
              result.token.count == 64, result.token.allSatisfy({$0.isHexDigit}), !result.expiresAt.isEmpty else {
            throw Failure(message:"The learning service did not create a usable session.")
        }
        return result
    }
    static func request(service: URL, token: String, lesson: String, context: String, messages: [[String: String]]) throws -> URLRequest {
        guard token.count == 64, token.allSatisfy({$0.isHexDigit}) else { throw Failure(message:"Reconnect to the learning service.",code:"session_expired") }
        var remaining = 60_000
        let input = messages.suffix(40).reversed().compactMap { row -> [String: String]? in
            guard let role = row["role"], ["user", "assistant"].contains(role), let text = row["text"], !text.isEmpty, remaining > 0 else { return nil }
            let content = String(text.prefix(min(8000,remaining))); remaining -= content.count
            return ["role":role,"text":content]
        }.reversed()
        guard input.last?["role"] == "user" else { throw Failure(message:"Enter a question for the tutor.") }
        var request = URLRequest(url:service.appendingPathComponent("v1/tutor")); request.httpMethod = "POST"; request.timeoutInterval = 95
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"lesson":lesson,"context":String(context.prefix(32000)),"messages":Array(input)])
        return request
    }
    static func check(status: Int, data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let object = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        let known = (object?["error"] as? [String:Any])?["code"] as? String ?? ""
        // Use our own messages; never display arbitrary server/provider error bodies.
        if status == 401 { throw Failure(message:"Your learning connection has expired. Send again to reconnect.",code:"session_expired") }
        if known == "not_activated" { throw Failure(message:"The shared tutor is awaiting activation by StatsDirect or your course provider. You do not need an OpenAI key.") }
        if status == 429 { throw Failure(message:known == "daily_limit" ? "Today's learning allowance has been reached. Please return tomorrow." : "The shared tutor is busy or its allowance has been reached. Please try again later.") }
        if status == 400 || status == 413 { throw Failure(message:"The learning service could not accept this question. Shorten it and try again.") }
        throw Failure(message:"The shared tutor is temporarily unavailable. Your learning record is saved locally; please try again later.")
    }
    static func reply(data: Data, status: Int) throws -> (text: String, model: String, responseID: String, promptVersion: String) {
        try check(status:status,data:data)
        guard data.count <= 2_000_000, let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              object["schemaVersion"] as? Int == 1, let text = object["text"] as? String, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw Failure(message:"The learning service returned no readable answer. Please try again.")
        }
        return (text,object["model"] as? String ?? "unknown",object["responseID"] as? String ?? "",object["promptVersion"] as? String ?? "unknown")
    }
    @MainActor static func converse(service: URL, savedToken: String?, lesson: String, context: String, messages: [[String:String]], saveToken: (String) throws -> Void, removeToken: () -> Void) async throws -> (text: String, model: String, responseID: String, promptVersion: String) {
        let transport = TutorTransport()
        let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil
        let session = URLSession(configuration:configuration,delegate:transport,delegateQueue:nil)
        defer { session.finishTasksAndInvalidate() }
        var token = savedToken
        for attempt in 0...1 {
            if token == nil {
                let (data,response) = try await session.data(for:sessionRequest(service:service))
                try Task.checkCancellation()
                let created = try self.session(data:data,status:(response as? HTTPURLResponse)?.statusCode ?? 0)
                try saveToken(created.token); token = created.token
            }
            let request = try self.request(service:service,token:token!,lesson:lesson,context:context,messages:messages)
            let (data,response) = try await session.data(for:request)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                removeToken(); token = nil
                if attempt == 0 { continue }
            }
            return try reply(data:data,status:status)
        }
        throw Failure(message:"The learning session could not reconnect.")
    }
}

/// A redirect must not forward conversation text or a session credential to a different service.
final class TutorTransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
