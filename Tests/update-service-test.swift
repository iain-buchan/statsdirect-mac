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
  // 1.0.1 follows 1.0.0 (the first release after 0.3.30): exercise the real check entry point
  // for both GitHub routes, including versions whose ordering is not lexical.
  let nextTag = "v1.0.1", nextURL = URL(string:"https://github.com/iain-buchan/statsdirect-mac/releases/tag/v1.0.1")!
  for installedVersion in ["0.0.0","0.3.2","0.3.9","0.3.10","0.3.29","0.3.30","1.0.0","1.0.1","1.0.2","1.1.0"] {
   for fallback in [false,true] {
    fixture(fallback
     ? [.error(.cannotFindHost),.response(nextURL,200,Data("unused HTML".utf8))]
     : [.response(UpdateService.endpoint,200,try release(nextTag))])
    let result = try await UpdateService.check(installed:installedVersion,session:session)
    if AppVersion(installedVersion)! < AppVersion(nextTag)! {
     guard case .available(let found) = result else { fatalError("1.0.1 was not offered to \(installedVersion) via \(fallback ? "website" : "API")") }
     precondition(found.version == nextTag && found.url == nextURL,"The update must open the published 1.0.1 release")
    } else {
     guard case .current = result else { fatalError("1.0.1 was offered to current/newer \(installedVersion)") }
    }
    precondition(UpdateFixture.requests == (fallback ? [UpdateService.endpoint,UpdateService.latestRelease] : [UpdateService.endpoint]))
    precondition(UpdateFixture.replies.isEmpty)
   }
  }
  for flags in [(true,false),(false,true),(true,true)] {
   fixture([.response(UpdateService.endpoint,200,try release(nextTag,draft:flags.0,prerelease:flags.1))])
   guard case .noRelease = try await UpdateService.check(installed:"0.3.30",session:session) else { fatalError("Unpublished 1.0.1 was offered") }
   precondition(UpdateFixture.requests == [UpdateService.endpoint],"Draft/prerelease responses must not trigger the website fallback")
  }
  for invalidTag in ["v1.0.1-beta","v1.0.1.1","v1..0"] {
   do { _ = try UpdateService.interpret(release(invalidTag),status:200,installed:"0.3.29");fatalError("Invalid release version accepted") } catch {}
   let invalidURL = UpdateService.releases.appendingPathComponent("tag").appendingPathComponent(invalidTag)
   do { _ = try UpdateService.interpretReleasePage(page(invalidURL.absoluteString),installed:"0.3.29");fatalError("Invalid website release version accepted") } catch {}
  }
  print("PASS: 1.0.1 offered to 1.0.0 and older through API and website fallback, current/newer excluded, draft/prerelease/invalid versions excluded")
  var installed = "0.3.2"
  if let index = CommandLine.arguments.firstIndex(of:"--app") {
   guard index + 1 < CommandLine.arguments.count,
         let bundle = Bundle(url:URL(fileURLWithPath:CommandLine.arguments[index + 1])),
         let version = bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,
         AppVersion(version) != nil else { fatalError("Cannot read the packaged application version") }
   installed = version
   let candidate = try release("v" + version)
   if case .current = try UpdateService.interpret(candidate,status:200,installed:version) {} else { fatalError("The packaged version offers itself as an update") }
   if case .available(let found) = try UpdateService.interpret(candidate,status:200,installed:"0.3.2") {
    assert(found.version == "v" + version)
   } else { fatalError("An older installation cannot detect the packaged version") }
   print("PASS: packaged version \(version) is recognised by older installations and does not update to itself (release-response fixture)")
  }
  if CommandLine.arguments.contains("--live") {
   switch try await UpdateService.check(installed:installed) {
    case .noRelease: print("PASS: real public GitHub endpoint reports no published release")
    case .current: print("PASS: no newer published release than installed version \(installed) at the real public GitHub endpoint")
    case .available(let r): print("PASS: real public GitHub endpoint returned \(r.version)")
   }
  }
  // Use after publication to verify visibility, rather than treating any valid
  // response (including an older latest release) as a successful release check.
  if let index = CommandLine.arguments.firstIndex(of:"--live-release") {
   guard index + 1 < CommandLine.arguments.count,
         let expectedVersion = AppVersion(CommandLine.arguments[index + 1]),
         expectedVersion > AppVersion("0.3.29")! else { fatalError("Supply the published release tag after --live-release") }
   let expectedTag = CommandLine.arguments[index + 1]
   let expectedURL = UpdateService.releases.appendingPathComponent("tag").appendingPathComponent(expectedTag)
   let currentVersion = expectedTag.hasPrefix("v") ? String(expectedTag.dropFirst()) : expectedTag
   var apiRequest = URLRequest(url:UpdateService.endpoint,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
   apiRequest.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
   apiRequest.setValue("StatsDirect-Mac-release-verification",forHTTPHeaderField:"User-Agent")
   let (apiData,apiResponse) = try await URLSession.shared.data(for:apiRequest)
   guard let apiResponse = apiResponse as? HTTPURLResponse else { fatalError("The public release API returned no HTTP response") }
   guard case .available(let apiRelease) = try UpdateService.interpret(apiData,status:apiResponse.statusCode,installed:"0.3.29"),
         apiRelease.version == expectedTag, apiRelease.url == expectedURL else { fatalError("The public latest-release API does not identify \(expectedTag)") }
   for installedVersion in ["0.3.2","0.3.29",currentVersion] {
    let result = try await UpdateService.check(installed:installedVersion)
    if installedVersion == currentVersion {
     guard case .current = result else { fatalError("The published app offers itself as an update") }
    } else {
     guard case .available(let found) = result, found.version == expectedTag, found.url == expectedURL else { fatalError("The public update check did not offer \(expectedTag) to \(installedVersion)") }
    }
   }
   var request = URLRequest(url:UpdateService.latestRelease,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
   request.setValue("StatsDirect-Mac-release-verification",forHTTPHeaderField:"User-Agent")
   let (_,response) = try await URLSession.shared.data(for:request)
   guard let response = response as? HTTPURLResponse else { fatalError("The public latest-release redirect returned no HTTP response") }
   for installedVersion in ["0.3.29",currentVersion] {
    let result = try UpdateService.interpretReleasePage(response,installed:installedVersion)
    if installedVersion == currentVersion {
     guard case .current = result else { fatalError("The public website offers the current version again") }
    } else {
     guard case .available(let found) = result, found.version == expectedTag, found.url == expectedURL else { fatalError("The public latest-release redirect did not offer \(expectedTag)") }
    }
   }
   print("PASS: live public GitHub check offers \(expectedTag) to 0.3.29 and older, current version is not offered, and the real latest-release website redirect agrees")
  }
 }
}
