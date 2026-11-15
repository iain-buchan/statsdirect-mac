import Foundation

/// Supplies the selected bundled lesson within the native tutor's context budget.
enum LearningLibrary {
    static let contextLimit = 6500
    static let fields = ["id", "contentVersion", "review", "contentSha256", "difficulty", "learnerGoals", "learnerGoalNotes", "prerequisites", "learningObjectives",
                         "keyConcepts", "misconceptions", "workedExample", "teachingPrompts",
                         "rProgression", "sources", "assessmentIds", "practiceQuestions"]

    static func context(for lesson: [String: Any]) -> String? {
        guard lesson["knowledgeSchemaVersion"] as? Int == 1 else { return nil }
        let introduction = "\nCURATED STATSDIRECT LESSON (original teaching material; references are editorial links, not pages fetched during this conversation):\n"
        var selected = lesson.filter { fields.contains($0.key) }
        if let json = boundedJSON(selected) {
            return introduction + json + "\n"
        }

        // The question bank retains the embedded items, and current practice context arrives separately.
        // Keep the lesson's teaching material and review identity when the full record is too large.
        selected.removeValue(forKey: "practiceQuestions")
        if var review = selected["review"] as? [String: Any] {
            review.removeValue(forKey: "notes")
            selected["review"] = review
        }
        let compactNote = "Embedded practice questions and detailed review notes have been omitted for length.\n"
        if let json = boundedJSON(selected) {
            return introduction + compactNote + json + "\n"
        }

        // Retain the review identity and worked example ahead of suggested tutor prompts.
        selected.removeValue(forKey: "teachingPrompts")
        guard let json = boundedJSON(selected) else { return nil }
        return introduction + compactNote + "Suggested teaching prompts have also been omitted.\n" + json + "\n"
    }

    private static func boundedJSON(_ selected: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8), json.count <= contextLimit else { return nil }
        return json
    }

    static func source(for lesson: [String:Any]) -> [String:String] {
        ["id":"library:" + (lesson["id"] as? String ?? "lesson"),
         "title":"StatsDirect lesson: " + (lesson["title"] as? String ?? "Learning") + " · " + (lesson["contentVersion"] as? String ?? "")]
    }
}
