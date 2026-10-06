import Cocoa
@main struct ProviderLearningTests {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let viewer = Viewer(); app.delegate = viewer
        let fixtureRoot=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        viewer.chatGPTTutor=ChatGPTTutor(executable:fixtureRoot.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:fixtureRoot.appendingPathComponent(".build/startup-chatgpt-mock"),resources:viewer.root.appendingPathComponent("Tutor"))
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do { try await run(viewer); print("PASS: provider course and resource integration in native WKWebView") }
                catch { print("FAIL:",error.localizedDescription); fflush(stdout); exit(1) }
                fflush(stdout); if !CommandLine.arguments.contains("--stay-open") { viewer.closeApproved = true; app.terminate(nil) }
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
        try await wait { guard d.learningState != nil else { return false }; return (try? await v.learningJavaScript(d,"({ok:!!document.getElementById('statisticalSkills')})"))?["ok"] as? Bool == true }
        var rows = try await v.learningJavaScript(d,"({count:document.querySelectorAll('main>.card').length,resources:!!document.getElementById('resourceURLs'),pack:!!document.querySelector('#trainingProvider #importCourse'),recipient:document.getElementById('reviewEmail').value,details:document.querySelector('.option-details').open,assessment:document.getElementById('assessmentType').value})")
        precondition(rows["count"] as? Int == 2 && rows["resources"] as? Bool == false && rows["pack"] as? Bool == true && rows["details"] as? Bool == false)
        precondition(rows["recipient"] as? String == "support@statisticalhelp.org" && rows["assessment"] as? String == "none")
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('statisticalSkills').value='advanced',document.getElementById('statisticalSkills').dispatchEvent(new Event('input')),document.getElementById('priorKnowledge').value='Prior epidemiology module',document.getElementById('priorKnowledge').dispatchEvent(new Event('input')),true)})")
        try await wait { (d.learningState?["learning"] as? [String:Any])?["statisticalSkills"] as? String == "advanced" }
        _ = try await v.learningJavaScript(d,"({ok:document.getElementById('exampleCourse').click()===undefined})")
        try await wait { (v.loadCoursePack()?.schemaVersion == 2) && (d.learningState?["courseKey"] as? String == "service-improvement-demo:1.1") }
        rows = try await v.learningJavaScript(d,"({count:document.querySelectorAll('[data-lesson]').length})"); precondition(rows["count"] as? Int == v.learningLessons.count + 3)
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"course:service-improvement-demo:1.1:paired\"]').click()===undefined})")
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
        print("PASS: simplified options and saved skills, provider import, three course lessons, saved practical work, non-executing R example, attached R snapshot, returned response and three provider MCQs")

        // Exercise the real native context builder through the existing local protocol fixture.
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        v.chatGPTTutor.shutdown()
        v.chatGPTTutor = ChatGPTTutor(executable:root.appendingPathComponent("Tests/mock-chatgpt-server.py"),storage:root.appendingPathComponent(".build/provider-chatgpt-mock"),resources:v.root.appendingPathComponent("Tutor"))
        _ = try await v.chatGPTTutor.signIn()
        try await wait { v.chatGPTTutor.account != nil }
        v.learningSettings(d)
        // Exercise the shipped library through the same UI and native request used by learners.
        for lesson in v.learningLessons {
            let id = lesson["id"] as! String
            _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"\(id)\"]').click()===undefined})")
            let guide = try await v.learningJavaScript(d,"({title:document.querySelector('h1').textContent,text:document.querySelector('.lesson-guide').textContent,links:document.querySelectorAll('.lesson-guide a').length,open:document.querySelector('.lesson-guide').open})")
            precondition(guide["title"] as? String == lesson["title"] as? String)
            precondition((guide["text"] as! String).contains("Key ideas") && (guide["text"] as! String).contains("Common mistakes"))
            precondition(guide["links"] as? Int == (lesson["sources"] as! [Any]).count && guide["open"] as? Bool == false)
        }
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"missing\"]').click()===undefined})")
        _ = try await v.learningJavaScript(d,"({ok:(document.getElementById('question').value='LIBRARY_TEST Explain the missing-outcome bounds.',document.getElementById('send').click(),true)})")
        try await wait { (d.learningState?["conversation"] as? [[String:Any]])?.last?["model"] as? String == "fixture-model" }
        let libraryReply = (d.learningState!["conversation"] as! [[String:Any]]).last!
        precondition((libraryReply["courseSources"] as! [[String:String]]).contains{$0["id"] == "library:missing"})
        print("PASS: all 12 enriched guides display in WKWebView; complete selected lesson, fixed key and source metadata reach the native tutor request; lesson version retained with reply")
        var pack = try JSONSerialization.jsonObject(with:JSONEncoder().encode(v.loadCoursePack()!)) as! [String:Any]
        pack["documents"] = [["id":"cohort","title":"Cohort population","text":"retrieved-cohort-evidence: A cohort follows people at risk over time.","url":"https://example.org/course-cohort","retrievedAt":"2026-10-01"]]
        try JSONSerialization.data(withJSONObject:pack).write(to:v.coursePackURL)
        var resource = LearningResource(url:"https://example.org/course-cohort",title:"Cohort population")
        resource.documents = [.init(id:"cohort",title:"Cohort population",text:"retired-resource-must-not-leak",url:resource.url,retrievedAt:"2026-09-30")]
        var disabled = resource; disabled.id = "disabled"; disabled.enabled = false; disabled.documents = [.init(id:"disabled",title:"Cohort",text:"disabled-source-must-not-leak")]
        try v.saveLearningResources([resource,disabled])
        _ = try await v.learningJavaScript(d,"({ok:document.querySelector('[data-lesson=\"course:service-improvement-demo:1.1:paired\"]').click()===undefined})")
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
        precondition(review["recipient"] as? String == "support@statisticalhelp.org")
        precondition((d.learningState?["learning"] as? [String:Any])?["priorKnowledge"] as? String == "Prior epidemiology module")
        precondition((d.learningState?["training"] as? [String:Any])?["assessmentType"] as? String == "self")
        v.openLearningOptions()
        print("PASS: skills, assessment preference and imported course reference reach the tutor request; retired web caches excluded; cited reply, practical work, evidence and external response survive export and restore. No email sent, no live AI reply claimed.")
    }
}
