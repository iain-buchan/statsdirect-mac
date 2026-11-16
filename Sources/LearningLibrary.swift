import Foundation

/// How the learning record is written to portfolio.json: compactly, as Windows writes it. Written indented, the same record
/// took a third more room, so the 10 MB limit that both platforms share was reached sooner on a Mac.
enum LearningRecordFile {
    static let maximumBytes = 10_000_000
    static func data(_ state: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    /// Whether a record is within the limit, measured on the compact form whatever form a copy is then written in: a
    /// record that can be saved can also be exported.
    static func fits(_ record: [String: Any]) -> Bool {
        (try? data(record)).map { $0.count <= maximumBytes } ?? false
    }
}

/// Supplies the selected bundled lesson within the native tutor's context budget.
enum LearningLibrary {
    /// The curated record's usual allowance. Every bundled lesson fits whole, so the tutor sees each lesson's own practice
    /// question and teaching prompts, as it does on Windows.
    static let contextLimit = 9000
    /// The allowance of StatsDirect 1.1.3 and earlier. A lesson is never given less.
    static let minimumContextLimit = 6500
    /// The tutor's whole reference context is cut at this length (ChatGPTTutor and LearningCore).
    static let referenceLimit = 32000

    /// The workspace summary's own limit, and room for the section headings and the lesson's introduction and notes.
    static let workspaceLimit = 6000, headingAllowance = 600

    /// The allowance for one question: what the rest of the reference context leaves, between the two limits above. The
    /// rest is the learner's own settings and text, the workspace summary, the method catalogue and the section headings.
    static func limit(reserving used: Int) -> Int {
        min(contextLimit, max(minimumContextLimit, referenceLimit - used))
    }
    static func limit(learnerText: Int, catalogue: Int) -> Int {
        limit(reserving: learnerText + workspaceLimit + catalogue + headingAllowance)
    }

    /// The most the learner's text, the curated lesson and any course excerpts may come to together, so that the workspace
    /// summary and the method catalogue after them are not cut. Excerpts are added only while they fit under it: the
    /// lesson comes first, as on Windows.
    static func learningContextLimit(catalogue: Int) -> Int {
        referenceLimit - (workspaceLimit + catalogue + headingAllowance)
    }
    static let fields = ["id", "contentVersion", "review", "contentSha256", "difficulty", "learnerGoals", "learnerGoalNotes", "prerequisites", "learningObjectives",
                         "keyConcepts", "misconceptions", "workedExample", "teachingPrompts",
                         "rProgression", "sources", "assessmentIds", "practiceQuestions"]

    static func context(for lesson: [String: Any], limit: Int = contextLimit) -> String? {
        guard lesson["knowledgeSchemaVersion"] as? Int == 1 else { return nil }
        let introduction = "\nCURATED STATSDIRECT LESSON (original teaching material; references are editorial links, not pages fetched during this conversation):\n"
        var selected = lesson.filter { fields.contains($0.key) }
        func boundedJSON(_ selected: [String: Any]) -> String? { self.boundedJSON(selected, limit: limit) }
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

    private static func boundedJSON(_ selected: [String: Any], limit: Int) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8), json.count <= limit else { return nil }
        return json
    }

    static func source(for lesson: [String:Any]) -> [String:String] {
        ["id":"library:" + (lesson["id"] as? String ?? "lesson"),
         "title":"StatsDirect lesson: " + (lesson["title"] as? String ?? "Learning") + " · " + (lesson["contentVersion"] as? String ?? "")]
    }
}
