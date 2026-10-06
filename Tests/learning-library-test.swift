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
            for field in LearningLibrary.fields { precondition(decoded[field] != nil,field) }
            precondition((decoded["id"] as! String) == (lesson["id"] as! String))
            precondition(json.count <= 6500)
            let fullBudget = 8000 + context.count + 6000 + 9560 + 400
            precondition(fullBudget < 32000)
            precondition(LearningLibrary.source(for:lesson)["title"]!.contains("2026-10-01"))
        }
        precondition(LearningLibrary.context(for:["title":"Old provider lesson"]) == nil)
        print("PASS: all 12 complete curated lessons reach bounded, parseable native tutor context; old packs remain compatible")
    }
}
