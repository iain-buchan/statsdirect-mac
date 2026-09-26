import Foundation
@main struct UpdateTests {
 static func main() async throws {
  func release(_ version:String="v0.4.0", _ url:String="https://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.4.0", draft:Bool=false, prerelease:Bool=false) throws -> Data {
   try JSONSerialization.data(withJSONObject:["tag_name":version,"html_url":url,"draft":draft,"prerelease":prerelease])
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
  if CommandLine.arguments.contains("--live") {
   switch try await UpdateService.check(installed:"0.3.2") {
    case .noRelease: print("PASS: real public GitHub endpoint reports no published release")
    case .current: print("PASS: real public GitHub endpoint reports current version")
    case .available(let r): print("PASS: real public GitHub endpoint returned \(r.version)")
   }
  }
 }
}
