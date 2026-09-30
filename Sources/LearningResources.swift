import Foundation
import PDFKit
import CryptoKit
import Darwin

struct LearningResource: Codable {
    var id = UUID().uuidString
    var url: String
    var title: String
    var note = ""
    var enabled = true
    var status = "Not downloaded"
    var fetchedAt: String? = nil
    var documents: [CoursePack.Material] = []
    var linkedPDFs: [String] = []
}

/// Downloads only public HTTPS resources, without browser cookies, credentials or scripts.
enum LearningResourceReader {
    static func publicAddress(_ host: String) -> Bool {
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host,nil,&hints,&result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var item: UnsafeMutablePointer<addrinfo>? = first
        while let current = item {
            var buffer = [CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(current.pointee.ai_addr,current.pointee.ai_addrlen,&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST) == 0 else { return false }
            let address = String(cString:buffer)
            if address.contains(":") {
                // Global unicast only; excludes loopback, mapped IPv4, link-local and unique-local.
                guard let prefix = UInt16(address.split(separator:":").first ?? "",radix:16), (0x2000..<0x4000).contains(prefix) else { return false }
            } else {
                let p = address.split(separator:".").compactMap{Int($0)}
                guard p.count == 4, p[0] > 0, p[0] < 224, ![10,127].contains(p[0]),
                      !(p[0] == 169 && p[1] == 254), !(p[0] == 172 && (16...31).contains(p[1])),
                      !(p[0] == 192 && [0,168].contains(p[1])), !(p[0] == 100 && (64...127).contains(p[1])),
                      !(p[0] == 198 && [18,19,51].contains(p[1])), !(p[0] == 203 && p[1] == 0 && p[2] == 113) else { return false }
            }
            item = current.pointee.ai_next
        }
        return true
    }
    static func checkedURL(_ text: String) throws -> URL {
        guard let url = LearningLinks.web(text), publicAddress(url.host!) else {
            throw LearningTutor.Failure(message:"Use a public HTTPS learning page or PDF. Local/private addresses, credentials and nonstandard ports are not accepted.")
        }
        return url
    }
    static func load(_ entry: LearningResource) async throws -> LearningResource {
        let url = try await Task.detached { try checkedURL(entry.url) }.value
        let transport = ResourceTransport()
        let (data,response) = try await transport.fetch(url)
        try Task.checkCancellation()
        return try await Task.detached { try parse(data,response:response,entry:entry) }.value
    }
    static func parse(_ data: Data, response: HTTPURLResponse, entry: LearningResource) throws -> LearningResource {
        guard (200..<300).contains(response.statusCode) else { throw LearningTutor.Failure(message:response.statusCode == 401 || response.statusCode == 403 ? "This site blocks direct downloads or needs sign-in. Open the link and import an authorised PDF/text copy instead." : "The site returned HTTP \(response.statusCode). Check the link or try later.") }
        let source = entry.url // Preserve the stable user-supplied address rather than an expiring download redirect.
        let date = ISO8601DateFormatter().string(from:Date())
        let mime = response.mimeType?.lowercased() ?? ""
        var result = entry; result.documents = []; result.linkedPDFs = []
        if mime == "application/pdf" || data.starts(with:Data("%PDF-".utf8)) {
            guard let pdf = PDFDocument(data:data), !pdf.isLocked, pdf.pageCount <= 700 else { throw LearningTutor.Failure(message:"The PDF is locked, unreadable or longer than 700 pages. Import a selected chapter instead.") }
            var count = 0
            for page in 0..<pdf.pageCount {
                if let text = pdf.page(at:page)?.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    count += text.utf8.count
                    guard count <= 2_000_000 else { throw LearningTutor.Failure(message:"The PDF exceeds 2 MB of extracted text. Import a selected chapter instead.") }
                    result.documents.append(.init(id:entry.id+"-page\(page+1)",title:entry.title+" · page \(page+1)",text:text,url:source,retrievedAt:date))
                }
            }
        } else if ["text/html","application/xhtml+xml","text/plain","text/markdown"].contains(mime) {
            guard data.count <= 3_000_000, let raw = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.windowsCP1252) else { throw LearningTutor.Failure(message:"The page is too large or has an unsupported text encoding.") }
            let html = mime.contains("html")
            if html {
                if let title = capture("(?is)<title[^>]*>(.*?)</title>",raw) { result.title = String(plain(title).prefix(200)) }
                let regex = try! NSRegularExpression(pattern:"(?is)<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>")
                result.linkedPDFs = Array(Set(regex.matches(in:raw,range:NSRange(raw.startIndex...,in:raw)).compactMap { match -> String? in
                    guard let r = Range(match.range(at:1),in:raw), let u = URL(string:entities(String(raw[r])),relativeTo:response.url)?.absoluteURL,
                          LearningLinks.web(u.absoluteString) != nil else { return nil }
                    let label = Range(match.range(at:2),in:raw).map{plain(String(raw[$0])).lowercased()} ?? ""
                    guard u.path.lowercased().hasSuffix(".pdf") || (label.contains("pdf") && u.path.contains("resource/view.php")) else { return nil }
                    return u.absoluteString
                })).sorted().prefix(12).map{$0}
            }
            let text = html ? plain(capture("(?is)<main\\b[^>]*>(.*?)</main>",raw) ?? capture("(?is)<article\\b[^>]*>(.*?)</article>",raw) ?? raw) : raw
            guard text.utf8.count <= 2_000_000 else { throw LearningTutor.Failure(message:"The page contains too much text. Use a chapter link instead.") }
            if text.count >= 100 { result.documents = [.init(id:entry.id,title:result.title,text:text,url:source,retrievedAt:date)] }
        } else { throw LearningTutor.Failure(message:"This link does not return a readable web page, text document or PDF.") }
        guard !result.documents.isEmpty else { throw LearningTutor.Failure(message:"No readable teaching text was found. Open the resource and import a text/searchable-PDF copy.") }
        result.fetchedAt = date
        result.status = "Ready · \(result.documents.count) page\(result.documents.count == 1 ? "" : "s") · \(result.documents.reduce(0,{$0+$1.text.count})) characters"
        return result
    }
    static func capture(_ pattern: String, _ text: String) -> String? {
        guard let r = try? NSRegularExpression(pattern:pattern), let m = r.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)), let range = Range(m.range(at:1),in:text) else { return nil }
        return String(text[range])
    }
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of:"(?is)<!--.*?-->",with:"",options:.regularExpression)
        s = s.replacingOccurrences(of:"(?is)<(script|style|noscript|nav|footer|header|aside|form|svg)\\b[^>]*>.*?</\\1\\s*>",with:"",options:.regularExpression)
        s = s.replacingOccurrences(of:"(?i)</?(?:p|div|h[1-6]|li|tr|br|section)\\b[^>]*>",with:"\n",options:.regularExpression)
        s = s.replacingOccurrences(of:"(?s)<[^>]+>",with:" ",options:.regularExpression)
        return entities(s).components(separatedBy:.newlines).map{$0.replacingOccurrences(of:"[ \\t\\r]+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}.joined(separator:"\n")
    }
    static func entities(_ input: String) -> String {
        var s = input
        let r = try! NSRegularExpression(pattern:"&#(x[0-9a-fA-F]+|[0-9]+);")
        for m in r.matches(in:s,range:NSRange(s.startIndex...,in:s)).reversed() {
            if let a = Range(m.range(at:1),in:s), let b = Range(m.range,in:s) {
                let v = String(s[a]); if let n = UInt32(v.hasPrefix("x") ? String(v.dropFirst()) : v,radix:v.hasPrefix("x") ? 16 : 10), let c = UnicodeScalar(n) { s.replaceSubrange(b,with:String(c)) }
            }
        }
        for (a,b) in ["&nbsp;":" ","&quot;":"\"","&apos;":"'","&lt;":"<","&gt;":">","&ndash;":"–","&mdash;":"—","&lsquo;":"‘","&rsquo;":"’","&ldquo;":"“","&rdquo;":"”","&times;":"×","&le;":"≤","&ge;":"≥","&alpha;":"α","&beta;":"β","&mu;":"μ","&sigma;":"σ","&chi;":"χ","&sup2;":"²","&amp;":"&"] { s = s.replacingOccurrences(of:a,with:b) }
        return s
    }
}

private final class ResourceTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<(Data,HTTPURLResponse),Error>?
    private var data = Data(), response: HTTPURLResponse?, redirects = 0
    private var session: URLSession?
    func fetch(_ url: URL) async throws -> (Data,HTTPURLResponse) {
        try await withCheckedThrowingContinuation { c in
            continuation = c
            let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 50
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration:config,delegate:self,delegateQueue:queue); self.session = session
            var request = URLRequest(url:url); request.setValue("StatsDirect-Learning/0.3.15",forHTTPHeaderField:"User-Agent")
            session.dataTask(with:request).resume()
        }
    }
    private func finish(_ result: Result<(Data,HTTPURLResponse),Error>) {
        guard let c = continuation else { return }; continuation = nil; c.resume(with:result); session?.invalidateAndCancel(); session = nil
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= 16_000_000 else { completionHandler(.cancel); finish(.failure(LearningTutor.Failure(message:"The resource exceeds the 16 MB download limit."))); return }
        self.response = http; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard data.count + bytes.count <= 16_000_000 else { finish(.failure(LearningTutor.Failure(message:"The resource exceeds the 16 MB download limit."))); return }; data.append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else if let response { finish(.success((data,response))) } else { finish(.failure(LearningTutor.Failure(message:"No HTTP response was received."))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 4, let text = request.url?.absoluteString, (try? LearningResourceReader.checkedURL(text)) != nil else { completionHandler(nil); finish(.failure(LearningTutor.Failure(message:"The resource redirects to an unsupported address."))); return }
        completionHandler(request)
    }
}
