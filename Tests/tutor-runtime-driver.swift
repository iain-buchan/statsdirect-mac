import Foundation
import Darwin

@main struct TutorRuntimeTests {
    static func check(_ value: Bool, _ message: String) throws {
        guard value else { throw TutorRuntimePackage.failure("FAIL: "+message) }
        print("PASS: "+message); fflush(stdout)
    }
    static func rejects(_ message: String, _ action: () async throws -> Void) async throws {
        do { try await action() } catch { try check(true,message); return }
        throw TutorRuntimePackage.failure("FAIL: "+message)
    }
    static func main() async {
        do { try await run() } catch { print(error.localizedDescription); fflush(stdout); exit(1) }
    }
    static func run() async throws {
        let manager=FileManager.default, repo=URL(fileURLWithPath:manager.currentDirectoryPath)
        let resources=repo.appendingPathComponent("Content/Tutor")
        let pinned=try TutorRuntimePackage.load(resources)
        try check(pinned.files.count == 5 && pinned.version == "0.157.1","trusted metadata loads the exact pinned Apple Silicon package")
        for url in ["http://github.com/openai/codex", "https://github.com.evil.invalid/", "https://user:secret@release-assets.githubusercontent.com/file", "https://release-assets.githubusercontent.com:444/file", "file:///tmp/runtime"] {
            try check(!pinned.permits(URL(string:url)),"download refuses untrusted destination "+url.replacingOccurrences(of:"user:secret@",with:"credentials@"))
        }
        try check(pinned.permits(pinned.url) && pinned.permits(URL(string:"https://release-assets.githubusercontent.com/example")),"official release and GitHub CDN are allowed")
        let work=repo.appendingPathComponent(".build/runtime-tests-"+UUID().uuidString)
        try manager.createDirectory(at:work,withIntermediateDirectories:true)
        defer { try? manager.removeItem(at:work) }
        let fixture=work.appendingPathComponent("fixture"), archive=work.appendingPathComponent("fixture.tar.gz")
        try manager.createDirectory(at:fixture.appendingPathComponent("bin"),withIntermediateDirectories:true)
        let executable=fixture.appendingPathComponent("bin/codex-app-server")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to:executable)
        try manager.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
        try check(try TutorRuntimePackage.run("/usr/bin/tar",["-czf",archive.path,"-C",fixture.path,"bin"]) == 0,"test package created")
        let files=["bin/codex-app-server":TutorRuntimePackage.File(size:try Data(contentsOf:executable).count,sha256:try TutorRuntimePackage.digest(executable))]
        let digest=try TutorRuntimePackage.digest(archive)
        func package(_ url: URL) -> TutorRuntimePackage {
            TutorRuntimePackage(version:"0.0.1",url:url,sha256:digest,maximumBytes:1024*1024,teamIdentifier:pinned.teamIdentifier,signingIdentifier:pinned.signingIdentifier,files:files)
        }
        let server=Process(); server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        let portFile=work.appendingPathComponent("port")
        server.arguments=[repo.appendingPathComponent("Tests/tutor-runtime-http.py").path,archive.path,portFile.path]
        server.standardOutput=FileHandle.nullDevice;server.standardError=FileHandle.nullDevice
        try server.run();defer {server.terminate();server.waitUntilExit()}
        for _ in 0..<100 where !manager.fileExists(atPath:portFile.path) {try await Task.sleep(nanoseconds:20_000_000)}
        let port=try String(contentsOf:portFile,encoding:.utf8)
        func endpoint(_ path:String) -> URL {URL(string:"http://127.0.0.1:"+port+path)!}
        let testPackage=package(endpoint("/archive")), root=work.appendingPathComponent("installed")
        let installed=try await TutorRuntimeInstallation.install(testPackage,root:root,resources:resources,progress:{_ in},publisher:{_ in})
        try check(manager.isExecutableFile(atPath:installed.appendingPathComponent("bin/codex-app-server").path),"HTTP download is checked, extracted and promoted")
        try check(try String(contentsOf:installed.appendingPathComponent("LICENSE"),encoding:.utf8) == String(contentsOf:resources.appendingPathComponent("Runtime-LICENSE"),encoding:.utf8),"official license is retained")
        let abandoned=root.appendingPathComponent(".staging-"+UUID().uuidString)
        try manager.createDirectory(at:abandoned,withIntermediateDirectories:false)
        try Data("interrupted download".utf8).write(to:abandoned.appendingPathComponent("package.tar.gz"))
        let reused=try await TutorRuntimeInstallation.install(testPackage,root:root,resources:resources,progress:{_ in},download:{_ in throw TutorRuntimePackage.failure("Unexpected download")},publisher:{_ in})
        try check(reused.path == installed.path,"intact installation reuses cached files without any download")
        try check(!manager.fileExists(atPath:abandoned.path),"retry removes staging left by a force-quit")
        try await rejects("unsigned test executable cannot pass OpenAI publisher verification") {try testPackage.verifyPublisher(installed)}
        let marker=root.appendingPathComponent("other-version/keep")
        try manager.createDirectory(at:marker.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("keep".utf8).write(to:marker)
        try Data("damaged".utf8).write(to:installed.appendingPathComponent("bin/codex-app-server"))
        try await rejects("tampered installed bytes are rejected") {try testPackage.verifyFiles(installed)}
        try await rejects("failed repair never replaces the existing installation") {
            _=try await TutorRuntimeInstallation.install(testPackage,root:root,resources:resources,progress:{_ in},publisher:{_ in throw TutorRuntimePackage.failure("Test publisher rejection")})
        }
        try check(try String(contentsOf:installed.appendingPathComponent("bin/codex-app-server"),encoding:.utf8) == "damaged","existing bytes survive failed verification during repair")
        _=try await TutorRuntimeInstallation.install(testPackage,root:root,resources:resources,progress:{_ in},publisher:{_ in})
        try testPackage.verifyFiles(installed)
        try check(manager.fileExists(atPath:marker.path),"corrupt install repairs atomically without changing other versions")
        for path in ["/404","/redirect","/invalid","/oversize","/truncated"] {
            let badRoot=work.appendingPathComponent("fault-"+path.dropFirst())
            try await rejects("rejects "+path+" and leaves no installed runtime") {
                _=try await TutorRuntimeInstallation.install(package(endpoint(path)),root:badRoot,resources:resources,progress:{_ in},publisher:{_ in})
            }
            try check(try manager.contentsOfDirectory(atPath:badRoot.path) == [".install.lock"],"failed "+path+" cleans its staging files")
        }
        let cancelRoot=work.appendingPathComponent("cancel")
        let cancelling=Task {try await TutorRuntimeInstallation.install(package(endpoint("/slow")),root:cancelRoot,resources:resources,progress:{_ in},publisher:{_ in})}
        try await Task.sleep(nanoseconds:150_000_000)
        try await rejects("second process/install is refused while the directory lock is held") {
            _=try await TutorRuntimeInstallation.install(testPackage,root:cancelRoot,resources:resources,progress:{_ in},publisher:{_ in})
        }
        cancelling.cancel()
        try await rejects("cancellation interrupts the download") {_ = try await cancelling.value}
        try check(try manager.contentsOfDirectory(atPath:cancelRoot.path) == [".install.lock"],"cancel cleans partial download before returning")
        _=try await TutorRuntimeInstallation.install(testPackage,root:cancelRoot,resources:resources,progress:{_ in},publisher:{_ in})
        try check(true,"cancelled installation retries successfully")
        let rejectedRoot=work.appendingPathComponent("publisher")
        try await rejects("publisher failure never promotes extracted bytes") {
            _=try await TutorRuntimeInstallation.install(testPackage,root:rejectedRoot,resources:resources,progress:{_ in})
        }
        try check(try manager.contentsOfDirectory(atPath:rejectedRoot.path) == [".install.lock"],"publisher rejection cleans staging")
        let symlink=work.appendingPathComponent("symlink")
        try manager.createSymbolicLink(at:symlink,withDestinationURL:root)
        try await rejects("symbolic-link installation root is rejected") {
            _=try await TutorRuntimeInstallation.install(testPackage,root:symlink,resources:resources,progress:{_ in},publisher:{_ in})
        }
        try manager.createSymbolicLink(at:installed.appendingPathComponent("extra"),withDestinationURL:executable)
        try await rejects("an extra symlink invalidates the cached runtime") {try testPackage.verifyFiles(installed)}
        try manager.removeItem(at:installed.appendingPathComponent("extra"))
        let metadata=work.appendingPathComponent("metadata"); try manager.createDirectory(at:metadata,withIntermediateDirectories:true)
        try JSONEncoder().encode(testPackage).write(to:metadata.appendingPathComponent("runtime.json"))
        try await rejects("production metadata loader rejects loopback/insecure package URLs") {_ = try TutorRuntimePackage.load(metadata)}
        if let index=CommandLine.arguments.firstIndex(of:"--real-root") {
            let realRoot=URL(fileURLWithPath:CommandLine.arguments[index+1]).standardizedFileURL
            let real=try await TutorRuntimeInstallation.install(pinned,root:realRoot,resources:resources,progress:{_ in})
            try await TutorRuntimeInstallation.verify(pinned,at:real)
            try check(true,"official runtime file hashes and OpenAI publisher signature verify after setup")
            _=try await TutorRuntimeInstallation.install(pinned,root:realRoot,resources:resources,progress:{_ in},download:{_ in throw TutorRuntimePackage.failure("Unexpected second download")})
            try check(true,"real signed runtime can be reused offline")
            print("REAL_RUNTIME="+real.appendingPathComponent("bin/codex-app-server").path)
        }
        print("PASS: runtime installation suite completed")
    }
}
