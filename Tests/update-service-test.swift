import Foundation

private final class UpdateFixture: URLProtocol {
 enum Reply { case error(URLError.Code), response(URL, Int, Data) }
 static var replies: [Reply] = []
 static var requests: [URL] = []
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.requests.append(request.url!)
  precondition(!Self.replies.isEmpty, "Unexpected update request")
  switch Self.replies.removeFirst() {
   case .error(let code): client?.urlProtocol(self,didFailWithError:URLError(code))
   case .response(let url,let status,let data):
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
  }
 }
 override func stopLoading() {}
}

@main struct UpdateTests {
 static func main() async throws {
  func release(_ version:String="v0.4.0", _ url:String?=nil, draft:Bool=false, prerelease:Bool=false) throws -> Data {
   try JSONSerialization.data(withJSONObject:["tag_name":version,"html_url":url ?? "https://github.com/iain-buchan/statsdirect-mac/releases/tag/" + version,"draft":draft,"prerelease":prerelease])
  }
  assert(AppVersion("v0.10.0")! > AppVersion("0.9.9")!)
  assert(AppVersion("0.3")! == AppVersion("0.3.0")!)
  assert(AppVersion("0.3.2-beta") == nil && AppVersion("0..3") == nil)
  if case .available(let r) = try UpdateService.interpret(release(),status:200,installed:"0.3.2") {assert(r.version == "v0.4.0")} else {fatalError("New release not found")}
  for tag in ["v0.3.2","v0.3.1"] {if case .current = try UpdateService.interpret(release(tag),status:200,installed:"0.3.2") {} else {fatalError("Downgrade suggested")}}
  if case .noRelease = try UpdateService.interpret(Data(),status:404,installed:"0.3.2") {} else {fatalError("404")}
  for flags in [(true,false),(false,true)] {if case .noRelease = try UpdateService.interpret(release(draft:flags.0,prerelease:flags.1),status:200,installed:"0.3.2") {} else {fatalError("Nonpublic release offered")}}
  for status in [403,429,500] {do {_ = try UpdateService.interpret(Data(),status:status,installed:"0.3.2");fatalError("HTTP failure claimed success")}catch{}}
  for url in ["http://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.4.0","https://other.example/release","https://github.com/other/repo/releases/tag/v0.4.0"] {do {_ = try UpdateService.interpret(release("v0.4.0",url),status:200,installed:"0.3.2");fatalError("Untrusted update link accepted")}catch{}}
  do {_ = try UpdateService.interpret(Data("not JSON".utf8),status:200,installed:"0.3.2");fatalError("Malformed JSON accepted")}catch{}
  print("PASS: version comparison, updates, no releases, draft/prerelease exclusion, HTTP failures, malformed responses and trusted release URLs")
  func page(_ url: String, _ status: Int = 200) -> HTTPURLResponse { HTTPURLResponse(url:URL(string:url)!,statusCode:status,httpVersion:nil,headerFields:nil)! }
  let tag = "https://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.4.0"
  if case .available(let r) = try UpdateService.interpretReleasePage(page(tag),installed:"0.3.7") { assert(r.version == "v0.4.0") } else { fatalError("Fallback lost new version") }
  for version in ["0.4.0","0.5.0"] { if case .current = try UpdateService.interpretReleasePage(page(tag),installed:version) {} else { fatalError("Fallback proposed a downgrade") } }
  for response in [page(UpdateService.releases.absoluteString),page(UpdateService.latestRelease.absoluteString,404)] {
   if case .noRelease = try UpdateService.interpretReleasePage(response,installed:"0.3.7") {} else { fatalError("Missing releases not recognised") }
  }
  for url in ["https://github.com/login", "https://example.org/releases/tag/v0.4.0", "https://github.com/other/repo/releases/tag/v0.4.0", tag + "?redirect=1", tag + "-beta", "http://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.4.0", UpdateService.latestRelease.absoluteString] {
   do { _ = try UpdateService.interpretReleasePage(page(url),installed:"0.3.7");fatalError("Invalid fallback accepted") } catch {}
  }
  for status in [403,429,500] { do { _ = try UpdateService.interpretReleasePage(page(UpdateService.releases.absoluteString,status),installed:"0.3.7");fatalError("Website failure claimed no update") } catch {} }
  print("PASS: website latest-release validation, newer/current versions, no release, login/wrong-repository/HTTP rejection")
  let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [UpdateFixture.self]
  let session = URLSession(configuration:configuration); defer { session.invalidateAndCancel() }
  func fixture(_ replies: [UpdateFixture.Reply]) { UpdateFixture.replies = replies; UpdateFixture.requests = [] }
  fixture([.response(UpdateService.endpoint,200,try release())])
  if case .available = try await UpdateService.check(installed:"0.3.7",session:session) {} else { fatalError("API success") }
  assert(UpdateFixture.requests == [UpdateService.endpoint])
  for problem in [UpdateFixture.Reply.error(.cannotFindHost),.response(UpdateService.endpoint,429,Data()),.response(UpdateService.endpoint,500,Data())] {
   fixture([problem,.response(URL(string:tag)!,200,Data("unused HTML".utf8))])
   if case .available = try await UpdateService.check(installed:"0.3.7",session:session) {} else { fatalError("API failure did not fall back") }
   assert(UpdateFixture.requests == [UpdateService.endpoint,UpdateService.latestRelease])
  }
  fixture([.error(.cannotFindHost),.response(UpdateService.releases,200,Data())])
  if case .noRelease = try await UpdateService.check(installed:"0.3.7",session:session) {} else { fatalError("Fallback no releases") }
  fixture([.error(.cannotFindHost),.error(.cannotFindHost)])
  do { _ = try await UpdateService.check(installed:"0.3.7",session:session);fatalError("DNS failure claimed success") }
  catch { assert(UpdateService.message(for:error).contains("DNS")) }
  fixture([.error(.cancelled)])
  do { _ = try await UpdateService.check(installed:"0.3.7",session:session);fatalError("Cancellation ignored") } catch {}
  assert(UpdateFixture.requests == [UpdateService.endpoint])
  assert(UpdateService.message(for:URLError(.notConnectedToInternet)).contains("offline"))
  assert(UpdateService.message(for:URLError(.timedOut)).contains("in time"))
  assert(UpdateService.message(for:URLError(.serverCertificateUntrusted)).contains("secure connection"))
  print("PASS: actual URLSession fallback after DNS/rate-limit/server errors, API-only success, both-host failure, cancellation and readable connection errors")
  if CommandLine.arguments.contains("--live") {
   switch try await UpdateService.check(installed:"0.3.2") {
    case .noRelease: print("PASS: real public GitHub endpoint reports no published release")
    case .current: print("PASS: real public GitHub endpoint reports current version")
    case .available(let r): print("PASS: real public GitHub endpoint returned \(r.version)")
   }
  }
 }
}
