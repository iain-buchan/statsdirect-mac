import Foundation

/// Local, text-only course material. Referenced excerpts are supplied as context, never executed.
struct CoursePack: Codable {
    struct Material: Codable { let id: String; let title: String; let text: String }
    let schemaVersion: Int
    let title: String
    let documents: [Material]
    func validated() throws -> CoursePack {
        guard schemaVersion == 1, !title.isEmpty, title.count <= 200,
              !documents.isEmpty, documents.count <= 500,
              Set(documents.map(\.id)).count == documents.count,
              documents.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 120 && !$0.title.isEmpty && $0.title.count <= 300 && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }),
              documents.reduce(0,{$0 + $1.text.utf8.count}) <= 1_000_000 else {
            throw LearningTutor.Failure(message:"Use a course pack with a title, unique document IDs and up to 1 MB of readable text across at most 500 documents or PDF pages.")
        }
        return self
    }
    struct Excerpt { let id: String; let title: String; let text: String }
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
                candidates.append((score,candidates.count,Excerpt(id:document.id,title:document.title,text:text)))
            }
        }
        return candidates.sorted{$0.score == $1.score ? $0.order < $1.order : $0.score > $1.score}.prefix(limit).map(\.excerpt)
    }
}
