import Foundation
@main struct LearningLibraryTests {
    static func main() throws {
        let file = URL(fileURLWithPath:CommandLine.arguments[1])
        let lessons = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [[String:Any]]
        precondition(lessons.count == 12)
        for lesson in lessons {
            let context = LearningLibrary.context(for:lesson)!
            let json = String(context.split(separator:"\n").last!)
            let decoded = try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
            for field in LearningLibrary.fields where lesson[field] != nil {
                precondition(decoded[field] != nil,field)
                let expected = try JSONSerialization.data(withJSONObject:["value":lesson[field]!],options:[.sortedKeys])
                let actual = try JSONSerialization.data(withJSONObject:["value":decoded[field]!],options:[.sortedKeys])
                precondition(actual == expected, "Imported metadata changed: " + field)
            }
            precondition((decoded["id"] as! String) == (lesson["id"] as! String))
            precondition(json.count <= 6500)
            let fullBudget = 8000 + context.count + 6000 + 9560 + 400
            precondition(fullBudget < 32000)
            precondition(LearningLibrary.source(for:lesson)["title"]!.contains(lesson["contentVersion"] as! String))
        }
        var reviewed = lessons[0]
        reviewed["difficulty"] = "advanced"
        reviewed["learnerGoals"] = ["medical", "public-health"]
        reviewed["learnerGoalNotes"] = "Preparing for a public health qualification."
        reviewed["contentSha256"] = String(repeating:"a",count:64)
        reviewed["review"] = ["status":"Human-reviewed", "reviewer":"Course tutor", "contentSha256":String(repeating:"a",count:64)]
        let context = LearningLibrary.context(for:reviewed)!
        let metadata = try JSONSerialization.jsonObject(with:Data(String(context.split(separator:"\n").last!).utf8)) as! [String:Any]
        precondition(metadata["difficulty"] as? String == "advanced")
        precondition(metadata["learnerGoals"] as? [String] == ["medical", "public-health"])
        precondition(metadata["learnerGoalNotes"] as? String == "Preparing for a public health qualification.")
        precondition(metadata["contentSha256"] as? String == String(repeating:"a",count:64))
        precondition((metadata["review"] as? [String:String])?["reviewer"] == "Course tutor")
        precondition(LearningLibrary.context(for:["title":"Old provider lesson"]) == nil)
        print("PASS: all 12 complete curated lessons reach bounded, parseable native tutor context; old packs remain compatible")
    }
}
