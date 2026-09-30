import Foundation

/// Local, text-only course material. Referenced excerpts are supplied as context, never executed.
struct CoursePack: Codable {
    struct Material: Codable { let id: String; let title: String; let text: String; var url: String? = nil; var retrievedAt: String? = nil }
    struct Provider: Codable { let name: String; let reviewEmail: String; var assessmentRequirements: String?; var cpdStatement: String? }
    struct Column: Codable { let title: String; let values: [Double] }
    struct Lesson: Codable {
        let id: String; let title: String; let objective: String; let summary: String
        var topic: String?; var steps: String?; var challenge: String?; var readingURLs: [String]?
        var operation: String?; var columns: [Column]?; var r: String?; var help: String?
    }
    struct Question: Codable {
        struct Option: Codable { let id: String; let text: String; var feedback: String? }
        let id: String; let stem: String; let options: [Option]; let correct: String; let explanation: String
        var topic: String?; var objective: String?; var hint: String?; var lesson: String?; var help: String?
    }
    let schemaVersion: Int
    let title: String
    let documents: [Material]
    var id: String? = nil
    var version: String? = nil
    var provider: Provider? = nil
    var lessons: [Lesson]? = nil
    var questions: [Question]? = nil
    var resourceURLs: [String]? = nil
    func validated() throws -> CoursePack {
        guard [1,2].contains(schemaVersion), !title.isEmpty, title.count <= 200,
              (!documents.isEmpty || schemaVersion == 2 && !(lessons ?? []).isEmpty), documents.count <= 500,
              Set(documents.map(\.id)).count == documents.count,
              documents.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 120 && !$0.title.isEmpty && $0.title.count <= 300 && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && ($0.url == nil || LearningLinks.web($0.url!) != nil) }),
              documents.reduce(0,{$0 + $1.text.utf8.count}) <= 1_000_000 else {
            throw LearningTutor.Failure(message:"Use a course pack with a title, unique document IDs and up to 1 MB of readable text across at most 500 documents or PDF pages.")
        }
        if schemaVersion == 2 {
            let lessons = lessons ?? [], questions = questions ?? []
            guard Self.identifier(id ?? ""), !(version ?? "").isEmpty, (version ?? "").count <= 80,
                  let provider, !provider.name.isEmpty, provider.name.count <= 200, LearningLinks.email(provider.reviewEmail),
                  (provider.assessmentRequirements ?? "").count <= 5000, (provider.cpdStatement ?? "").count <= 2000,
                  lessons.count <= 100, Set(lessons.map(\.id)).count == lessons.count,
                  questions.count <= 300, Set(questions.map(\.id)).count == questions.count,
                  (resourceURLs ?? []).count <= 30, (resourceURLs ?? []).allSatisfy({LearningLinks.web($0) != nil}) else {
                throw LearningTutor.Failure(message:"A provider course needs a unique ID, version, provider name, single review email address, and valid lesson, question and HTTPS resource lists.")
            }
            for lesson in lessons {
                guard Self.identifier(lesson.id), !lesson.title.isEmpty, lesson.title.count <= 200,
                      !lesson.objective.isEmpty, lesson.objective.count <= 3000, !lesson.summary.isEmpty, lesson.summary.count <= 30000,
                      (lesson.steps ?? "").count <= 20000, (lesson.challenge ?? "").count <= 5000, (lesson.r ?? "").count <= 50000,
                      (lesson.readingURLs ?? []).count <= 20, (lesson.readingURLs ?? []).allSatisfy({LearningLinks.web($0) != nil}),
                      (lesson.columns ?? []).count <= 32, (lesson.columns ?? []).reduce(0,{$0+$1.values.count}) <= 20000,
                      (lesson.columns ?? []).allSatisfy({!$0.title.isEmpty && $0.title.count <= 200 && $0.values.allSatisfy(\.isFinite)}),
                      Self.helpPath(lesson.help) else { throw LearningTutor.Failure(message:"A course lesson has invalid text, data, help or reading links.") }
            }
            for question in questions {
                guard Self.identifier(question.id), !question.stem.isEmpty, question.stem.count <= 6000,
                      (2...8).contains(question.options.count), Set(question.options.map(\.id)).count == question.options.count,
                      question.options.allSatisfy({$0.id.count == 1 && "ABCDEFGH".contains($0.id) && !$0.text.isEmpty && $0.text.count <= 3000 && ($0.feedback ?? "").count <= 6000}),
                      question.options.contains(where:{$0.id == question.correct}), !question.explanation.isEmpty, question.explanation.count <= 10000,
                      Self.helpPath(question.help) else { throw LearningTutor.Failure(message:"A course question needs 2–8 labelled choices, one answer key and an explanation.") }
            }
        } else if provider != nil || lessons != nil || questions != nil || resourceURLs != nil {
            throw LearningTutor.Failure(message:"Use schemaVersion 2 for provider courses.")
        }
        return self
    }
    static func identifier(_ s: String) -> Bool { !s.isEmpty && s.count <= 100 && s.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil }
    static func helpPath(_ s: String?) -> Bool { s == nil || s == "" || (s!.hasSuffix(".htm") && !s!.contains("..") && !s!.hasPrefix("/") && s!.range(of:"^[A-Za-z0-9_/-]+\\.htm$",options:.regularExpression) != nil) }
    struct Excerpt { let id: String; let title: String; let text: String; var url: String?; var retrievedAt: String? }
    /// Simple transparent local retrieval; no embedding upload, remote index or hidden file search.
    func excerpts(for query: String, limit: Int = 5) -> [Excerpt] {
        let stop = Set(["this","that","with","from","what","would","could","should","have","about","explain","help","then","than","which","when","your","their","into","also","they","them"])
        let terms = Set(query.lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter{$0.count > 3 && !stop.contains($0)})
        var candidates: [(score:Int,order:Int,excerpt:Excerpt)] = []
        for document in documents {
            let characters = Array(document.text)
            for start in stride(from:0,to:characters.count,by:1400) {
                let text = String(characters[start..<min(start+1700,characters.count)])
                let lower = text.lowercased(), heading = document.title.lowercased()
                let score = terms.reduce(0){$0 + (heading.contains($1) ? 4 : 0) + (lower.contains($1) ? 1 : 0)}
                if score > 0 { candidates.append((score,candidates.count,Excerpt(id:document.id,title:document.title,text:text,url:document.url,retrievedAt:document.retrievedAt))) }
            }
        }
        return candidates.sorted{$0.score == $1.score ? $0.order < $1.order : $0.score > $1.score}.prefix(limit).map(\.excerpt)
    }
}

enum LearningLinks {
    static func email(_ value: String) -> Bool {
        value.count <= 254 && !value.contains(where:{$0.isWhitespace}) && value.range(of:"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\\.[A-Za-z]{2,63}$",options:.regularExpression) != nil
    }
    static func web(_ value: String) -> URL? {
        guard value.count <= 2000, !value.contains(where:{$0.isWhitespace}), let url = URL(string:value), url.scheme == "https",
              let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host != "localhost", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }
}
