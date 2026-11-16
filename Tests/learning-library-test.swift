import Foundation
@main struct LearningLibraryTests {
    static func contextMetadata(for lesson: [String:Any], limit: Int = LearningLibrary.contextLimit) throws -> [String:Any] {
        let context = LearningLibrary.context(for:lesson,limit:limit)!
        let json = String(context.split(separator:"\n").last!)
        precondition(json.count <= limit)
        return try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
    }

    static func json(_ fields: [String:Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys,.withoutEscapingSlashes])
    }

    static func main() throws {
        let file = URL(fileURLWithPath:CommandLine.arguments[1])
        let lessons = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [[String:Any]]
        precondition(!lessons.isEmpty)
        // The method catalogue as LearnHost sends it, from the menu the app is built with.
        let menu = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
        let operations = menu["operations"] as! [String:[String:Any]]
        let catalogue = operations.keys.sorted().map { $0 + ": " + (operations[$0]?["title"] as? String ?? $0) }.joined(separator:"\n").count
        precondition(catalogue > 5000)
        // The least a lesson is given: the learner's own text at its 8,000 limit and the workspace summary at its 6,000.
        let tight = LearningLibrary.limit(learnerText:8000,catalogue:catalogue)
        precondition(tight == LearningLibrary.limit(reserving:8000 + 6000 + catalogue + 600))
        // Learner text, lesson and course excerpts together leave the workspace summary and the catalogue their room.
        precondition(63 + LearningLibrary.learningContextLimit(catalogue:catalogue) + 60 + LearningLibrary.workspaceLimit + 19 + catalogue <= LearningLibrary.referenceLimit)
        precondition(LearningLibrary.learningContextLimit(catalogue:catalogue) >= 15500, "Course excerpts have less room than before")
        precondition(tight >= LearningLibrary.minimumContextLimit && tight <= LearningLibrary.contextLimit)
        precondition(LearningLibrary.limit(reserving:0) == LearningLibrary.contextLimit)
        precondition(LearningLibrary.limit(reserving:LearningLibrary.referenceLimit) == LearningLibrary.minimumContextLimit)
        precondition(LearningLibrary.limit(reserving:LearningLibrary.referenceLimit - 7000) == 7000)
        var whole = 0, shortened = 0, promptsShortened = 0
        for lesson in lessons {
            let id = lesson["id"] as! String
            // As on Windows, the tutor is normally given every bundled lesson whole, its practice question and prompts included.
            let all = lesson.filter { LearningLibrary.fields.contains($0.key) }
            let given = try json(contextMetadata(for:lesson)), everything = try json(all)
            precondition(given == everything, "The tutor is not given the whole lesson: " + id)
            precondition(LearningLibrary.context(for:lesson)!.contains("omitted for length") == false && LearningLibrary.context(for:lesson)!.contains("have also been omitted") == false)
            whole += 1
            // With less room the embedded practice question and the review notes go first, then the teaching prompts,
            // and the whole reference context still fits its limit.
            for limit in [tight, LearningLibrary.minimumContextLimit] {
                let context = LearningLibrary.context(for:lesson,limit:limit)!
                if limit == tight { precondition(8000 + context.count + 6000 + catalogue + 400 <= LearningLibrary.referenceLimit, "Reference context too long: " + id) }
                let decoded = try contextMetadata(for:lesson,limit:limit)
                var expected = all
                if String(decoding:try json(expected),as:UTF8.self).count > limit {
                    expected.removeValue(forKey:"practiceQuestions")
                    if var review = expected["review"] as? [String:Any] {
                        review.removeValue(forKey:"notes")
                        expected["review"] = review
                    }
                    var promptsDropped = false
                    if String(decoding:try json(expected),as:UTF8.self).count > limit {
                        expected.removeValue(forKey:"teachingPrompts"); promptsDropped = true
                    }
                    precondition(context.contains("Embedded practice questions and detailed review notes have been omitted for length.\n"))
                    precondition(context.contains("Suggested teaching prompts have also been omitted.\n") == promptsDropped, "The note about the teaching prompts is wrong: " + id)
                    if promptsDropped { promptsShortened += 1 }
                    if limit == LearningLibrary.minimumContextLimit { shortened += 1 }
                }
                let actualJSON = try json(decoded), expectedJSON = try json(expected)
                precondition(actualJSON == expectedJSON, "Imported teaching or review metadata changed: " + id)
                precondition((decoded["id"] as! String) == id)
            }
            precondition(LearningLibrary.source(for:lesson)["title"]!.contains(lesson["contentVersion"] as! String))
        }
        precondition(whole == lessons.count && shortened > 0 && promptsShortened > 0, "No bundled lesson exercised the shortened record")
        var reviewed: [String:Any] = ["id":"review-fixture", "knowledgeSchemaVersion":1,
                                      "keyConcepts":["Selection bias"], "assessmentIds":["practice-1"],
                                      "teachingPrompts":["Discuss who enters the cohort."]]
        reviewed["difficulty"] = "advanced"
        reviewed["learnerGoals"] = ["medical", "public-health"]
        reviewed["learnerGoalNotes"] = "Preparing for a public health qualification."
        reviewed["contentSha256"] = String(repeating:"a",count:64)
        let review = ["status":"Human-reviewed", "reviewer":"Course tutor", "date":"2026-11-15",
                      "notes":"Checked the design and answer.", "contentSha256":String(repeating:"a",count:64)]
        reviewed["review"] = review
        reviewed["practiceQuestions"] = [["id":"practice-1", "correct":"A"]]
        let metadata = try contextMetadata(for:reviewed)
        precondition(metadata["difficulty"] as? String == "advanced")
        precondition(metadata["learnerGoals"] as? [String] == ["medical", "public-health"])
        precondition(metadata["learnerGoalNotes"] as? String == "Preparing for a public health qualification.")
        precondition(metadata["contentSha256"] as? String == String(repeating:"a",count:64))
        precondition(metadata["review"] as? [String:String] == review)
        precondition((metadata["practiceQuestions"] as? [[String:String]])?.first?["correct"] == "A")

        let oversizedText = String(repeating:"Additional background. ",count:LearningLibrary.contextLimit / 23 + 10)
        var longerLesson = reviewed
        longerLesson["practiceQuestions"] = [["id":"practice-1", "lesson":oversizedText]]
        longerLesson["review"] = review.merging(["notes":oversizedText]) { _, notes in notes }
        let bounded = try contextMetadata(for:longerLesson)
        let boundedReview = review.filter { $0.key != "notes" }
        precondition(bounded["practiceQuestions"] == nil)
        precondition(bounded["review"] as? [String:String] == boundedReview)
        precondition(bounded["keyConcepts"] as? [String] == ["Selection bias"])
        precondition(bounded["assessmentIds"] as? [String] == ["practice-1"])
        precondition(bounded["teachingPrompts"] as? [String] == ["Discuss who enters the cohort."])

        longerLesson["teachingPrompts"] = [oversizedText]
        let compact = try contextMetadata(for:longerLesson)
        precondition(compact["teachingPrompts"] == nil)
        precondition(compact["review"] as? [String:String] == boundedReview)
        precondition(compact["keyConcepts"] as? [String] == ["Selection bias"])
        precondition(compact["assessmentIds"] as? [String] == ["practice-1"])
        longerLesson["learnerGoalNotes"] = oversizedText
        precondition(LearningLibrary.context(for:longerLesson) == nil)
        precondition(LearningLibrary.context(for:["title":"Old provider lesson"]) == nil)
        // The saved record is written compactly, as Windows writes it, and reads back unchanged.
        let record: [String:Any] = ["schemaVersion":2, "quiz":["questionSnapshots":[["id":"q1","stem":"Rate per 1,000 person-years?","source":"https://www.statsdirect.com/help/"]]], "attempts":[] as [Any]]
        let saved = try LearningRecordFile.data(record)
        let text = String(decoding:saved,as:UTF8.self)
        precondition(!text.contains("\n") && !text.contains("  ") && text.contains("https://www.statsdirect.com/help/") && !text.contains(": "))
        let indented = try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys])
        let reread = try json(JSONSerialization.jsonObject(with:saved) as! [String:Any]), original = try json(record)
        precondition(saved.count < indented.count && reread == original)
        // Sorted keys at every level: the same record always gives the same file.
        let ordered: [String:Any] = ["schemaVersion":2, "view":"study", "lesson":"risk", "draft":"", "courseKey":"", "id":"r1", "profile":"foundation", "stage":"menus",
                                     "identity":["name":"", "goal":"", "email":""], "attempts":[1,2]]
        let orderedText = String(decoding:try LearningRecordFile.data(ordered),as:UTF8.self)
        precondition(orderedText == #"{"attempts":[1,2],"courseKey":"","draft":"","id":"r1","identity":{"email":"","goal":"","name":""},"lesson":"risk","profile":"foundation","schemaVersion":2,"stage":"menus","view":"study"}"#, orderedText)
        // The limit is on the compact form, for saving and for export alike: a record whose indented form is over the
        // limit still fits while its compact form does not exceed it.
        func attempts(_ count:Int) -> [String:Any] { ["schemaVersion":2, "attempts":Array(repeating:["a":1],count:count)] }
        let within = attempts(1_000_000), over = attempts(1_300_000)
        let withinIndented = try JSONSerialization.data(withJSONObject:within,options:[.prettyPrinted,.sortedKeys]).count
        precondition(LearningRecordFile.fits(within) && withinIndented > LearningRecordFile.maximumBytes && !LearningRecordFile.fits(over))
        print("PASS: the tutor is given all \(lessons.count) curated lessons whole; with less room \(shortened) are shortened in the tested order and the reference context still fits")
        print("PASS: the learning record is saved compactly and reads back unchanged")
    }
}
