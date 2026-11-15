import Foundation
@main struct LearningLibraryTests {
    static func contextMetadata(for lesson: [String:Any]) throws -> [String:Any] {
        let context = LearningLibrary.context(for:lesson)!
        let json = String(context.split(separator:"\n").last!)
        precondition(json.count <= 6500)
        let fullBudget = 8000 + context.count + 6000 + 9560 + 400
        precondition(fullBudget < 32000)
        return try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
    }

    static func json(_ fields: [String:Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys,.withoutEscapingSlashes])
    }

    static func main() throws {
        let file = URL(fileURLWithPath:CommandLine.arguments[1])
        let lessons = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [[String:Any]]
        precondition(!lessons.isEmpty)
        for lesson in lessons {
            let decoded = try contextMetadata(for:lesson)
            var expected = lesson.filter { LearningLibrary.fields.contains($0.key) }
            let fullJSON = try json(expected)
            if String(decoding:fullJSON,as:UTF8.self).count > 6500 {
                expected.removeValue(forKey:"practiceQuestions")
                if var review = expected["review"] as? [String:Any] {
                    review.removeValue(forKey:"notes")
                    expected["review"] = review
                }
                let compactJSON = try json(expected)
                if String(decoding:compactJSON,as:UTF8.self).count > 6500 {
                    expected.removeValue(forKey:"teachingPrompts")
                }
            }
            let actualJSON = try json(decoded)
            let expectedJSON = try json(expected)
            precondition(actualJSON == expectedJSON, "Imported teaching or review metadata changed: " + (lesson["id"] as! String))
            precondition((decoded["id"] as! String) == (lesson["id"] as! String))
            precondition(LearningLibrary.source(for:lesson)["title"]!.contains(lesson["contentVersion"] as! String))
        }
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

        let oversizedText = String(repeating:"Additional background. ",count:400)
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
        print("PASS: all \(lessons.count) curated lessons have bounded, parseable native tutor context with preserved teaching and review fields")
    }
}
