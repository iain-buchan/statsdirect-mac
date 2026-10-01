import Cocoa
import PDFKit
import UniformTypeIdentifiers

extension Viewer {
    var coursePackURL: URL { learningFolder.appendingPathComponent("course-pack.json") }
    func loadCoursePack() -> CoursePack? {
        guard let data = try? Data(contentsOf:coursePackURL), data.count <= 2_000_000,
              let pack = try? JSONDecoder().decode(CoursePack.self,from:data), let valid = try? pack.validated() else { return nil }
        return valid
    }
    func coursePackInfo(_ doc: Document) {
        if let pack = loadCoursePack() {
            var info = (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(pack))) as? [String:Any] ?? [:]
            info["documents"] = pack.documents.map{["id":$0.id,"title":$0.title]}
            info["textBytes"] = pack.documents.reduce(0,{$0+$1.text.utf8.count})
            learningScript(doc,"coursePack",info)
        } else { learningScript(doc,"coursePack",NSNull()) }
    }
    func importCoursePack(_ doc: Document) {
        guard doc.learningTask == nil, doc.learningResourceTask == nil else {
            learningScript(doc,"notice","Wait for the tutor reply or resource download to finish before changing course packs."); return
        }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf,.plainText,.json,UTType(filenameExtension:"md") ?? .plainText]
        panel.message = "Choose a tutor's JSON pack, or PDF, Markdown and text notes. Readable excerpts will be included when you send questions through the tutor service to OpenAI. A new import replaces the active pack; previous imports are kept locally."
        panel.beginSheetModal(for:window) { response in
            guard response == .OK else { return }
            do {
                var materials: [CoursePack.Material] = []; var packTitle = panel.urls.first?.deletingPathExtension().lastPathComponent ?? "Course pack"
                var providerPack: CoursePack?
                for (fileIndex,url) in panel.urls.enumerated() {
                    let data = try Data(contentsOf:url,options:.mappedIfSafe)
                    guard data.count <= 16_000_000 else { throw LearningTutor.Failure(message:"Each source file must be 16 MB or smaller.") }
                    let prefix = "file\(fileIndex+1)"
                    switch url.pathExtension.lowercased() {
                    case "json":
                        let imported = try JSONDecoder().decode(CoursePack.self,from:data).validated()
                        if imported.schemaVersion == 2 {
                            guard panel.urls.count == 1 else { throw LearningTutor.Failure(message:"Import a provider course on its own so its lessons and assessment stay together.") }
                            providerPack = imported
                        }
                        if panel.urls.count == 1 { packTitle = imported.title }
                        materials += imported.documents.map{CoursePack.Material(id:prefix+"-"+$0.id,title:$0.title,text:$0.text)}
                    case "pdf":
                        guard let pdf = PDFDocument(data:data), !pdf.isLocked, pdf.pageCount <= 500 else { throw LearningTutor.Failure(message:"This PDF is locked, unreadable or longer than 500 pages.") }
                        for page in 0..<pdf.pageCount {
                            if let text = pdf.page(at:page)?.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                                materials.append(CoursePack.Material(id:"\(prefix)-page\(page+1)",title:url.lastPathComponent+" · page \(page+1)",text:text))
                            }
                        }
                    default:
                        guard let text = String(data:data,encoding:.utf8) else { throw LearningTutor.Failure(message:"Text and Markdown files must be UTF-8. Export this document as text or PDF first.") }
                        materials.append(CoursePack.Material(id:prefix,title:url.lastPathComponent,text:text))
                    }
                }
                guard !materials.isEmpty || providerPack != nil else { throw LearningTutor.Failure(message:"No readable text was found. For scanned notes, use an OCR-enabled PDF or a text export.") }
                let pack = try (providerPack ?? CoursePack(schemaVersion:1,title:packTitle,documents:materials)).validated()
                try FileManager.default.createDirectory(at:self.learningFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                if FileManager.default.fileExists(atPath:self.coursePackURL.path) {
                    let archive = self.learningFolder.appendingPathComponent("Previous course packs")
                    try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    try FileManager.default.copyItem(at:self.coursePackURL,to:archive.appendingPathComponent(UUID().uuidString+".json"))
                }
                try JSONEncoder().encode(pack).write(to:self.coursePackURL,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:self.coursePackURL.path)
                self.coursePackInfo(doc)
                self.learningScript(doc,"notice","Course pack imported locally. Relevant excerpts will be sent with your next tutor question; no API call was made during import.")
            } catch { self.learningScript(doc,"notice","Course pack was not replaced: " + error.localizedDescription) }
        }
    }
    func useExampleCourse(_ doc: Document) {
        guard doc.learningTask == nil, doc.learningResourceTask == nil else {
            learningScript(doc,"notice","Wait for the tutor reply or resource download to finish before changing course packs."); return
        }
        do {
            let pack = try JSONDecoder().decode(CoursePack.self,from:Data(contentsOf:root.appendingPathComponent("Learn/provider-course-example.json"))).validated()
            try FileManager.default.createDirectory(at:learningFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            if FileManager.default.fileExists(atPath:coursePackURL.path) {
                let archive = learningFolder.appendingPathComponent("Previous course packs")
                try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try FileManager.default.copyItem(at:coursePackURL,to:archive.appendingPathComponent(UUID().uuidString+".json"))
            }
            try JSONEncoder().encode(pack).write(to:coursePackURL,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:coursePackURL.path)
            coursePackInfo(doc)
            learningScript(doc,"notice","Example provider course loaded. Its three lessons appear after the foundation lessons. Previous course packs are archived locally.")
        } catch { learningScript(doc,"notice",error.localizedDescription) }
    }
    var providerLessons: [[String:Any]] {
        guard let pack = loadCoursePack(), let id = pack.id, let version = pack.version else { return [] }
        return (pack.lessons ?? []).compactMap { lesson in
            guard var value = (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(lesson))) as? [String:Any] else { return nil }
            value["id"] = "course:\(id):\(version):\(lesson.id)"
            value["topic"] = lesson.topic ?? pack.title; value["steps"] = lesson.steps ?? ""
            value["challenge"] = lesson.challenge ?? "Explain what you have learned and how you would use it in your work."
            value["providerCourse"] = true; value["courseTitle"] = pack.title
            return value
        }
    }
    func importProviderReview(_ doc: Document) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.message = "Import the assessment response returned by your provider. It must name this learning record. File authenticity is not independently verified by StatsDirect."
        panel.beginSheetModal(for:window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf:url)
                guard data.count <= 100_000, let review = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                      review["portfolioID"] as? String == doc.learningState?["id"] as? String,
                      ["provider","reviewer","reviewedAt","decision","feedback"].allSatisfy({ !(review[$0] as? String ?? "").isEmpty }) else {
                    throw LearningTutor.Failure(message:"The response must contain this portfolioID, provider, reviewer, reviewedAt, decision and feedback.")
                }
                self.learningScript(doc,"providerReview",review)
            } catch { self.learningScript(doc,"notice","Assessment response was not imported: " + error.localizedDescription) }
        }
    }
}
