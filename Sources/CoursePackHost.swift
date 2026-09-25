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
            learningScript(doc,"coursePack",["title":pack.title,"documents":pack.documents.map{["id":$0.id,"title":$0.title]},"textBytes":pack.documents.reduce(0,{$0+$1.text.utf8.count})])
        } else { learningScript(doc,"coursePack",NSNull()) }
    }
    func importCoursePack(_ doc: Document) {
        guard doc.learningTask == nil else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf,.plainText,.json,UTType(filenameExtension:"md") ?? .plainText]
        panel.message = "Choose a tutor's JSON pack, or PDF, Markdown and text notes. Readable excerpts will be included when you send questions to OpenAI. A new import replaces the active pack; previous imports are kept locally."
        panel.beginSheetModal(for:window) { response in
            guard response == .OK else { return }
            do {
                var materials: [CoursePack.Material] = []; var packTitle = panel.urls.first?.deletingPathExtension().lastPathComponent ?? "Course pack"
                for (fileIndex,url) in panel.urls.enumerated() {
                    let data = try Data(contentsOf:url,options:.mappedIfSafe)
                    guard data.count <= 16_000_000 else { throw LearningTutor.Failure(message:"Each source file must be 16 MB or smaller.") }
                    let prefix = "file\(fileIndex+1)"
                    switch url.pathExtension.lowercased() {
                    case "json":
                        let imported = try JSONDecoder().decode(CoursePack.self,from:data).validated()
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
                guard !materials.isEmpty else { throw LearningTutor.Failure(message:"No readable text was found. For scanned notes, use an OCR-enabled PDF or a text export.") }
                let pack = try CoursePack(schemaVersion:1,title:packTitle,documents:materials).validated()
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
}
