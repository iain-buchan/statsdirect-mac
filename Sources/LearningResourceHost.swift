import Cocoa

extension Viewer {
    var learningResourceURL: URL { learningFolder.appendingPathComponent("resources.json") }
    func loadLearningResources() throws -> [LearningResource] {
        if FileManager.default.fileExists(atPath:learningResourceURL.path) {
            let data = try Data(contentsOf:learningResourceURL)
            guard data.count <= 20_000_000 else { throw LearningTutor.Failure(message:"The saved resource library is too large. It has not been replaced.") }
            let entries = try JSONDecoder().decode([LearningResource].self,from:data)
            guard entries.count <= 30, Set(entries.map(\.id)).count == entries.count, entries.allSatisfy({LearningLinks.web($0.url) != nil}) else { throw LearningTutor.Failure(message:"The saved resource library needs attention. It has not been replaced.") }
            return entries
        }
        let seeds = (try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Learn/resources.json")))) as? [[String:String]] ?? []
        return seeds.compactMap { item in
            guard let url = item["url"], let title = item["title"], LearningLinks.web(url) != nil else { return nil }
            return LearningResource(url:url,title:title,note:item["note"] ?? "")
        }
    }
    func saveLearningResources(_ entries: [LearningResource]) throws {
        let data = try JSONEncoder().encode(entries)
        guard entries.count <= 30, data.count <= 20_000_000 else { throw LearningTutor.Failure(message:"Keep at most 30 resources and 20 MB of extracted text in your library. Remove an unused resource first.") }
        try FileManager.default.createDirectory(at:learningFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try data.write(to:learningResourceURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:learningResourceURL.path)
    }
    func learningResourcesInfo(_ doc: Document) {
        do {
            let entries = try loadLearningResources()
            // Persist seed IDs once: subsequent toggle/import requests refer to these same entries.
            if !FileManager.default.fileExists(atPath:learningResourceURL.path) { try saveLearningResources(entries) }
            let info: [[String:Any]] = entries.map { ["id":$0.id,"url":$0.url,"title":$0.title,"note":$0.note,"enabled":$0.enabled,"status":$0.status,"fetchedAt":$0.fetchedAt ?? "","pages":$0.documents.count,"linkedPDFs":$0.linkedPDFs] }
            learningScript(doc,"resources",["entries":info,"busy":doc.learningResourceTask != nil])
        } catch { learningScript(doc,"notice","Resources could not be opened: " + error.localizedDescription) }
    }
    func addLearningResourceURLs(_ urls: [String], doc: Document) {
        guard doc.learningResourceTask == nil else { return }
        do {
            var entries = try loadLearningResources()
            for text in urls {
                guard let url = LearningLinks.web(text.trimmingCharacters(in:.whitespacesAndNewlines)) else { throw LearningTutor.Failure(message:"Enter one public HTTPS page or PDF address per line.") }
                if !entries.contains(where:{$0.url == url.absoluteString}) { entries.append(LearningResource(url:url.absoluteString,title:url.host!)) }
            }
            try saveLearningResources(entries); learningResourcesInfo(doc)
        } catch { learningScript(doc,"notice",error.localizedDescription) }
    }
    func handleLearningResources(_ doc: Document, body: [String:Any]) {
        guard doc.learningResourceTask == nil, doc.learningTask == nil else { return }
        do {
            var entries = try loadLearningResources()
            switch body["action"] as? String {
            case "addResources": addLearningResourceURLs(body["urls"] as? [String] ?? [],doc:doc); return
            case "removeResource": entries.removeAll{$0.id == body["id"] as? String}
            case "toggleResource":
                if let i = entries.firstIndex(where:{$0.id == body["id"] as? String}), let enabled = body["enabled"] as? Bool { entries[i].enabled = enabled }
            case "loadResources":
                let ids = Set(body["ids"] as? [String] ?? entries.filter(\.enabled).map(\.id))
                let selected = entries.filter{ids.contains($0.id)}
                doc.learningResourceTask = Task { @MainActor in
                    for entry in selected {
                        guard !Task.isCancelled, self.documents.contains(where:{$0 === doc}) else { break }
                        self.learningScript(doc,"notice","Reading " + entry.title + "…")
                        do {
                            let loaded = try await LearningResourceReader.load(entry)
                            try Task.checkCancellation()
                            var current = try self.loadLearningResources()
                            if let i = current.firstIndex(where:{$0.id == entry.id}) { current[i] = loaded; try self.saveLearningResources(current) }
                        } catch {
                            if Task.isCancelled { break }
                            do {
                                var current = try self.loadLearningResources()
                                if let i = current.firstIndex(where:{$0.id == entry.id}) {
                                    current[i].status = (current[i].documents.isEmpty ? "Not loaded: " : "Refresh failed; previous text retained: ") + error.localizedDescription
                                    try self.saveLearningResources(current)
                                }
                            } catch { self.learningScript(doc,"notice",error.localizedDescription) }
                        }
                        self.learningResourcesInfo(doc)
                    }
                    doc.learningResourceTask = nil; self.learningResourcesInfo(doc)
                    self.learningScript(doc,"notice","Resource loading finished. Check each status below. Only enabled, downloaded text is available to the tutor.")
                }
                learningResourcesInfo(doc); return
            default: return
            }
            try saveLearningResources(entries); learningResourcesInfo(doc)
        } catch { learningScript(doc,"notice",error.localizedDescription) }
    }
}
