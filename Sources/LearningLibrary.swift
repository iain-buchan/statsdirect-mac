import Foundation

/// The selected bundled lesson is small enough to supply whole; no search database is needed.
enum LearningLibrary {
    static let fields = ["id", "contentVersion", "review", "prerequisites", "learningObjectives",
                         "keyConcepts", "misconceptions", "workedExample", "teachingPrompts",
                         "rProgression", "sources", "assessmentIds", "practiceQuestions"]

    static func context(for lesson: [String:Any]) -> String? {
        guard lesson["knowledgeSchemaVersion"] as? Int == 1 else { return nil }
        let selected = lesson.filter { fields.contains($0.key) }
        guard let data = try? JSONSerialization.data(withJSONObject:selected,options:[.sortedKeys,.withoutEscapingSlashes]),
              let json = String(data:data,encoding:.utf8), json.count <= 6500 else { return nil }
        return "\nCURATED STATSDIRECT LESSON (original teaching material; references are editorial links, not pages fetched during this conversation):\n" + json + "\n"
    }

    static func source(for lesson: [String:Any]) -> [String:String] {
        ["id":"library:" + (lesson["id"] as? String ?? "lesson"),
         "title":"StatsDirect lesson: " + (lesson["title"] as? String ?? "Learning") + " · " + (lesson["contentVersion"] as? String ?? "")]
    }
}
