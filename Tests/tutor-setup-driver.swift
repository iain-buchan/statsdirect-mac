import Cocoa
import WebKit

actor SetupFixture {
    var calls=0
    var mode="wait"
    func set(_ mode:String) {self.mode=mode}
    func count() -> Int {calls}
    func prepare(_ package:TutorRuntimePackage,_ root:URL,_ resources:URL,_ progress:@Sendable(Double?)->Void) async throws -> URL {
        calls += 1
        if mode == "fail" {throw URLError(.notConnectedToInternet)}
        if mode == "success" {progress(nil);return root}
        progress(0.4)
        try await Task.sleep(nanoseconds:30_000_000_000)
        return root
    }
}

@main struct TutorSetupTests {
    @MainActor static func check(_ ok:Bool,_ message:String) throws {
        guard ok else {throw TutorRuntimePackage.failure("FAIL: "+message)}
        print("PASS: "+message);fflush(stdout)
    }
    @MainActor static func wait(_ condition:() async throws -> Bool) async throws {
        let deadline=Date().addingTimeInterval(20)
        while Date()<deadline {if try await condition() {return};try await Task.sleep(nanoseconds:40_000_000)}
        throw TutorRuntimePackage.failure("Timed out waiting for AI setup")
    }
    @MainActor static func buttons(_ view:NSView) -> [NSButton] {(view as? NSButton).map{[$0]} ?? view.subviews.flatMap(buttons)}
    @MainActor static func labels(_ view:NSView) -> [String] {(view as? NSTextField).map{[$0.stringValue]} ?? view.subviews.flatMap(labels)}
    @MainActor static var panel:NSWindow? {NSApp.windows.first{$0.isVisible && $0.title == "Set up ChatGPT"}}
    @MainActor static func click(_ title:String) throws {
        let button=panel.flatMap{$0.contentView}.flatMap{buttons($0).first{$0.title == title && !$0.isHidden && $0.isEnabled}}
        guard let button else {throw TutorRuntimePackage.failure("Missing setup button "+title)}
        button.performClick(nil)
    }
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks");UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        let viewer=Viewer();app.delegate=viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do {try await run(viewer);print("PASS: native first-use setup suite completed");fflush(stdout)}
                catch {print("FAIL:",error.localizedDescription);fflush(stdout);exit(1)}
                viewer.closeApproved=true;app.terminate(nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+150) {print("FAIL: native setup timed out");fflush(stdout);exit(1)}
        app.run()
    }
    @MainActor static func run(_ v:Viewer) async throws {
        let manager=FileManager.default, repo=URL(fileURLWithPath:manager.currentDirectoryPath)
        let work=repo.appendingPathComponent(".build/native-tutor-setup-"+UUID().uuidString)
        try manager.createDirectory(at:work,withIntermediateDirectories:true)
        defer {v.chatGPTTutor.runtime?.shutdown();v.chatGPTTutor.shutdown();try? manager.removeItem(at:work)}
        let resources=v.root.appendingPathComponent("Tutor"), fixture=SetupFixture()
        let runtime=TutorRuntimeInstaller(resources:resources,root:work.appendingPathComponent("runtime"),prepare:{try await fixture.prepare($0,$1,$2,$3)})
        let credentials=work.appendingPathComponent("credentials")
        try manager.createDirectory(at:credentials,withIntermediateDirectories:true)
        let marker=credentials.appendingPathComponent("existing-account.txt")
        try Data("unchanged".utf8).write(to:marker)
        v.chatGPTTutor.shutdown()
        v.chatGPTTutor=ChatGPTTutor(executable:runtime.executable,storage:credentials,resources:resources,runtime:runtime)
        try await v.chatGPTTutor.refreshAccount()
        try check(await fixture.count() == 0 && !manager.fileExists(atPath:runtime.root.path),"passive account check neither installs nor launches an absent runtime")
        v.openLearning()
        let learning=v.documents.first{$0.kind == "learn"}!
        try await wait {(try? await learning.web.evaluateJavaScript("!!window.statsDirectLearn")) as? Bool == true}
        let script=v.makeRScript(script:"# Synthetic draft\nx <- 1:3",saved:true)
        v.scriptAI.open(script)
        v.scriptAI.input.string="Keep my unfinished question"
        try await Task.sleep(nanoseconds:300_000_000)
        try check(await fixture.count() == 0 && panel == nil,"opening Learning and the script AI dock performs no download")
        try check(!v.learningLessons.isEmpty,"offline learning remains available without AI setup")
        v.scriptAI.connection.performClick(nil)
        try await wait {await fixture.count() == 1 && panel != nil}
        try check(v.openingTutorConnection,"explicit Use my ChatGPT starts setup")
        v.configureLearningAI(learning)
        try await Task.sleep(nanoseconds:100_000_000)
        try check(await fixture.count() == 1,"the second entry point cannot start a duplicate download")
        let window=panel!
        window.contentView!.layoutSubtreeIfNeeded()
        try check(labels(window.contentView!).contains{$0.contains("40%")},"native panel displays download progress")
        let shot=repo.appendingPathComponent(".build/tutor-setup-panel.png")
        if let image=window.contentView!.bitmapImageRepForCachingDisplay(in:window.contentView!.bounds) {
            window.contentView!.cacheDisplay(in:window.contentView!.bounds,to:image)
            let captured=NSImage(size:window.contentView!.bounds.size);captured.addRepresentation(image)
            let flattened=NSImage(size:captured.size,flipped:false) { rect in
                NSColor.windowBackgroundColor.setFill();rect.fill()
                captured.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1);return true
            }
            try NSBitmapImageRep(data:flattened.tiffRepresentation!)?.representation(using:.png,properties:[:])?.write(to:shot)
        }
        try click("Cancel")
        try await wait {!v.openingTutorConnection && panel == nil}
        try check(v.scriptAI.input.string == "Keep my unfinished question" && script.rPane!.editor.string.contains("Synthetic draft"),"cancelling setup preserves the question and script")
        try check(try String(contentsOf:marker,encoding:.utf8) == "unchanged","setup does not modify existing credentials")
        await fixture.set("fail")
        let retryTask=Task {await runtime.ensureAvailable()}
        try await wait {panel?.contentView.map{labels($0).contains{$0.contains("Check your connection")}} == true}
        try check(panel?.contentView.map{buttons($0).contains{$0.title == "Retry" && !$0.isHidden}} == true,"offline failure offers Retry and Not Now")
        await fixture.set("success");try click("Retry")
        try check(await retryTask.value && panel == nil,"Retry succeeds and closes setup automatically")
        await fixture.set("wait")
        let before=await fixture.count()
        let shared1=Task {await runtime.ensureAvailable()}, shared2=Task {await runtime.ensureAvailable()}
        try await wait {await fixture.count() == before+1 && panel != nil}
        panel!.performClose(nil)
        let result1=await shared1.value, result2=await shared2.value
        try check(!result1 && !result2 && panel == nil,"closing setup cancels all waiters after cleanup")
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        try check(!(await runtime.ensureAvailable()) && panel == nil,"institutional policy prevents setup before opening a panel")
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        let policyTask=Task {await runtime.ensureAvailable()}
        try await wait {panel != nil}
        UserDefaults.standard.set(true,forKey:"DisableOnlineTutor")
        try check(!(await policyTask.value) && panel == nil,"enabling institutional policy stops an active setup")
        UserDefaults.standard.set(false,forKey:"DisableOnlineTutor")
        if let root=ProcessInfo.processInfo.environment["STATSDIRECT_TEST_RUNTIME_ROOT"] {
            let real=TutorRuntimeInstaller(resources:resources,root:URL(fileURLWithPath:root))
            v.chatGPTTutor.shutdown()
            v.chatGPTTutor=ChatGPTTutor(executable:real.executable,storage:work.appendingPathComponent("real-account-isolated"),resources:resources,runtime:real)
            v.configureLearningAI(script)
            try await wait {v.window.attachedSheet?.contentView.map{labels($0).contains("Use my ChatGPT")} == true}
            try check(panel == nil && v.chatGPTTutor.account == nil,"verified runtime reuse continues to the existing signed-out ChatGPT connection dialog")
            let sheet=v.window.attachedSheet!
            buttons(sheet.contentView!).first{$0.title == "Not Now"}!.performClick(nil)
        }
        try check(!manager.fileExists(atPath:Bundle.main.resourceURL!.appendingPathComponent("TutorRuntime").path),"test application contains no bundled AI executables")
    }
}
