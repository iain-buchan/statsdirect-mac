import Cocoa
@main struct ProviderLearningTests {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let viewer = Viewer(); app.delegate = viewer
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: provider course and resource integration in native WKWebView") }
                catch { print("FAIL:",error.localizedDescription); fflush(stdout); exit(1) }
                fflush(stdout); viewer.closeApproved = true; app.terminate(nil)
            }
        }
        app.run()
    }
    @MainActor static func wait(_ check: () async throws -> Bool) async throws {
        for _ in 0..<100 { if try await check() { return }; try await Task.sleep(nanoseconds:100_000_000) }
        throw LearningTutor.Failure(message:"Timed out waiting for the provider learning interface")
    }
    @MainActor static func run(_ v: Viewer) async throws {
        v.openLearningOptions(); let d = v.documents.first{$0.kind == "learn"}!
        try await wait { guard d.learningState != nil else { return false }; return (try? await v.learningJavaScript(d,"({ok:!!document.getElementById('addResources')})"))?["ok"] as? Bool == true }
        var rows = try await v.learningJavaScript(d,"({count:document.querySelectorAll('.resource-row').length,text:document.body.innerText})")
        precondition(rows["count"] as? Int == 6 && (rows["text"] as! String).contains("OpenLearn"))
        _ = try await v.learningJavaScript(d,"({ok:document.getElementById('exampleCourse').click()===undefined})")
        try await wait { (v.loadCoursePack()?.schemaVersion == 2) && (d.learningState?["courseKey"] as? String == "service-improvement-demo:1.0") }
        rows = try await v.learningJavaScript(d,"({count:document.querySelectorAll('[data-lesson]').length})"); precondition(rows["count"] as? Int == 10)
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"course:service-improvement-demo:1.0:paired\"]').click()===undefined})")
        try await wait { (try? await v.learningJavaScript(d,"({ok:!!document.getElementById('courseAnswer')})"))?["ok"] as? Bool == true }
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('courseAnswer').value='Mean reduction 2 minutes; eight paired staff. The before-after comparison alone cannot isolate a training effect.',document.getElementById('saveCourseWork').click(),true)})")
        try await wait { (d.learningState?["courseWork"] as? [Any])?.count == 1 }
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-action=r]').click()===undefined})")
        try await wait { v.documents.contains{$0.kind == "r"} }
        let r = v.documents.last{$0.kind == "r"}!; precondition(r.rPane?.isRunning == false && r.rPane!.editor.string.contains("paired=TRUE"))
        v.captureLearningEvidence(d,documentID:r.id)
        try await wait { (d.learningState?["evidence"] as? [Any])?.count == 1 }
        v.learningScript(d,"providerReview",["schemaVersion":1,"portfolioID":d.learningState!["id"]!,"provider":"Example provider","reviewer":"Synthetic tutor","reviewedAt":"2026-09-30","decision":"Further work requested","feedback":"Discuss the comparison group."])
        try await wait { (d.learningState?["providerReviews"] as? [Any])?.count == 1 }
        _ = try await v.learningJavaScript(d,"({ok:document.getElementById('practiceNav').click()===undefined})")
        _ = try await v.learningJavaScript(d,"({ok:document.getElementById('supported').click()===undefined})")
        for choice in ["A","B","C"] {
            let script = "({ok:(document.querySelector('input[name=answer][value=\(choice)]').checked=true,document.getElementById('confidence').value='fairly',document.getElementById('answerForm').requestSubmit(),true)})"
            _ = try await v.learningJavaScript(d,script)
            _ = try await v.learningJavaScript(d,"({ok:document.getElementById('nextQuestion').click()===undefined})")
        }
        try await wait { (d.learningState?["quiz"] as? [String:Any])?["completedAt"] is String }
        let quiz = d.learningState!["quiz"] as! [String:Any]; precondition((quiz["answers"] as! [[String:Any]]).allSatisfy{$0["correct"] as? Bool == true})
        print("PASS: seeded resources, provider import, three course lessons, saved practical work, non-executing R example, attached R snapshot, returned response and three provider MCQs")

        // Exercise the real native context builder through the existing local protocol fixture.
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        v.chatGPTTutor.shutdown()
        v.chatGPTTutor = ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:root.appendingPathComponent(".build/provider-chatgpt-mock"),resources:v.root.appendingPathComponent("Tutor"))
        _ = try await v.chatGPTTutor.signIn()
        try await wait { v.chatGPTTutor.account != nil }
        v.learningSettings(d)
        var resource = LearningResource(url:"https://example.org/course-cohort",title:"Cohort population")
        resource.documents = [.init(id:"cohort",title:"Cohort population",text:"retrieved-cohort-evidence: A cohort follows people at risk over time.",url:resource.url,retrievedAt:"2026-09-30")]
        var disabled = resource; disabled.id = "disabled"; disabled.enabled = false; disabled.documents = [.init(id:"disabled",title:"Cohort",text:"disabled-source-must-not-leak")]
        try v.saveLearningResources([resource,disabled])
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"course:service-improvement-demo:1.0:paired\"]').click()===undefined})")
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('question').value='RESOURCE_TEST Explain cohort population and pairing.',document.getElementById('send').click(),true)})")
        try await wait { (d.learningState?["conversation"] as? [[String:Any]])?.last?["model"] as? String == "fixture-model" }
        let answer = (d.learningState!["conversation"] as! [[String:Any]]).last!
        precondition((answer["courseSources"] as! [[String:String]]).contains{$0["url"] == resource.url})
        _ = try await v.learningJavaScript(d,"({ok:document.getElementById('recordNav').click()===undefined})")
        let review = try await v.learningJavaScript(d,"({text:document.getElementById('recordPreview').textContent,recipient:document.getElementById('recipient').value})")
        let text = review["text"] as! String
        precondition(text.contains("cohort-evidence") == false && text.contains(resource.url) && text.contains("Mean reduction 2 minutes") && text.contains("t.test(") && text.contains("Further work requested"))
        let saved = try Data(contentsOf:v.learningFolder.appendingPathComponent("portfolio.json"))
        v.learningScript(d,"restore",try JSONSerialization.jsonObject(with:saved))
        try await wait { (d.learningState?["courseWork"] as? [Any])?.count == 1 }
        precondition(review["recipient"] as? String == "support@statsdirect.com")
        print("PASS: retrieved source and provider context reach the tutor request; disabled source excluded; cited reply, practical work, evidence and external response survive export and restore. No email sent, no live AI reply claimed.")
    }
}
