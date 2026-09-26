import Cocoa
import WebKit
import UniformTypeIdentifiers

extension Viewer {
    var learningFolder: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.statsdirect.viewer.prototype").appendingPathComponent("Learning")
    }
    var learningLessons: [[String: Any]] {
        (try? JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Learn/lessons.json")))) as? [[String:Any]] ?? []
    }
    @objc func openLearning() {
        if let existing = documents.first(where:{$0.kind == "learn"}) { tabs.selectTabViewItem(existing.item); return }
        newDocument(kind:"learn",title:"Learning",url:root.appendingPathComponent("Learn/index.html"))
    }
    @objc func openLearningOptions() {
        if let existing = documents.first(where:{$0.kind == "learn"}) { tabs.selectTabViewItem(existing.item); learningScript(existing,"showOptions",NSNull()); return }
        let doc = newDocument(kind:"learn",title:"Learning",url:root.appendingPathComponent("Learn/index.html")); doc.initialLearningView = "options"
    }
    func learningScript(_ doc: Document, _ action: String, _ value: Any) {
        guard documents.contains(where:{$0 === doc}), let data = try? JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]) else { return }
        doc.web.evaluateJavaScript("window.statsDirectLearn?.\(action)(\(String(decoding:data,as:UTF8.self)))")
    }
    func learningSettings(_ doc: Document) {
        learningScript(doc,"settings",["configured":chatGPTTutor.account != nil,"service":"ChatGPT","label":chatGPTTutor.status,"signingIn":chatGPTTutor.loginID != nil])
    }
    func handleLearning(_ message: WKScriptMessage) {
        guard message.name == "statsDirectLearn", message.frameInfo.isMainFrame,
              let web = message.webView, let doc = document(for:web), doc.kind == "learn",
              web.url?.standardizedFileURL == root.appendingPathComponent("Learn/index.html").standardizedFileURL,
              let body = message.body as? [String:Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            do {
                let url = learningFolder.appendingPathComponent("portfolio.json")
                if FileManager.default.fileExists(atPath:url.path) {
                    let data = try Data(contentsOf:url)
                    guard data.count <= 10_000_000 else { throw LearningTutor.Failure(message:"The saved learning record is too large to open. Export a copy from the Learning folder.") }
                    let saved = try JSONSerialization.jsonObject(with:data)
                    learningScript(doc,"restore",saved)
                } else { learningScript(doc,"restore",NSNull()) }
                learningSettings(doc)
                refreshLearningWorkspace(doc)
                Task { @MainActor in
                    do { try await self.chatGPTTutor.refreshAccount() }
                    catch { self.learningScript(doc,"notice",error.localizedDescription) }
                }
                coursePackInfo(doc)
                if doc.initialLearningView == "options" { doc.initialLearningView = nil; learningScript(doc,"showOptions",NSNull()) }
            } catch { learningScript(doc,"loadError",error.localizedDescription) }
        case "save":
            guard let state = body["state"] as? [String:Any], state["schemaVersion"] as? Int == 2,
                  let data = try? JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys]), data.count <= 10_000_000 else { learningScript(doc,"notice","The learning record could not be saved. Export it before closing."); return }
            do {
                try FileManager.default.createDirectory(at:learningFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let url = learningFolder.appendingPathComponent("portfolio.json")
                try data.write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                doc.learningState = state
                learningScript(doc,"saved",body["revision"] ?? 0)
            } catch { learningScript(doc,"notice","Learning record was not saved: " + error.localizedDescription) }
        case "importCoursePack": importCoursePack(doc)
        case "workspace":
            guard doc.learningTask == nil else { return }
            if let choice = body["choice"] as? String, choice.isEmpty || choice == "__none__" || documents.contains(where:{$0.id == choice && $0.kind != "learn"}) { doc.learningSourceID = choice; UserDefaults.standard.set(choice == "__none__",forKey:"learningLessonsOnly") }
            refreshLearningWorkspace(doc)
        case "settings": configureLearningAI(doc)
        case "ask": askLearningTutor(doc,body)
        case "cancel": doc.learningTask?.cancel(); doc.learningTask = nil; doc.learningRequestID = nil; chatGPTTutor.cancelReply(); learningScript(doc,"tutorError",["id":body["id"] ?? "","message":"Reply stopped. You can send another question."])
        case "help":
            if let id = body["lesson"] as? String, let lesson = learningLessons.first(where:{$0["id"] as? String == id}), let help = lesson["help"] as? String {
                openHelp(root.appendingPathComponent("Help/" + help),title:lesson["title"] as? String ?? "Learning")
            }
        case "example", "r":
            if let id = body["lesson"] as? String, let lesson = learningLessons.first(where:{$0["id"] as? String == id}) { openLearningExample(lesson,inR:action == "r") }
        case "export": exportLearningRecord(doc,body:body,email:false)
        case "email": exportLearningRecord(doc,body:body,email:true)
        default: break
        }
    }
    func configureLearningAI(_ doc: Document) {
        guard !openingTutorConnection else { return }
        openingTutorConnection = true
        Task { @MainActor in
            defer { self.openingTutorConnection = false }
            do { try await self.chatGPTTutor.refreshAccount() }
            catch { self.learningScript(doc,"notice",error.localizedDescription); return }
            guard self.documents.contains(where:{$0 === doc}) else { return }
            let tutor = self.chatGPTTutor
            let alert = NSAlert()
            if let account = tutor.account {
                alert.messageText = "Connected to ChatGPT"
                let identity = account.email.isEmpty ? "Your ChatGPT account" : account.email
                alert.informativeText = "\(identity)\(account.plan.isEmpty ? "" : " · " + account.plan.capitalized)\n\nYour tutor uses this account's Codex access and usage allowance. Each Send shares your question, recent learning conversation, learning options and relevant course excerpts with OpenAI. The tutor can read the open StatsDirect worksheets, reports, help and R output shown in Learning and request engine calculations. Choose Lessons only to exclude open documents.\n\nSigning out here leaves your local learning record and your other apps unchanged."
                alert.addButton(withTitle:"Done"); alert.addButton(withTitle:"Sign Out")
                alert.beginSheetModal(for:self.window) { response in
                    if response == .alertSecondButtonReturn {
                        Task { @MainActor in
                            do { try await tutor.signOut() }
                            catch { self.learningScript(doc,"notice",error.localizedDescription) }
                        }
                    }
                }
            } else if let url = tutor.loginURL {
                alert.messageText = "Finish signing in to ChatGPT"
                alert.informativeText = "Complete sign-in in your browser, then return to StatsDirect. Your draft question is kept here. The connection will update automatically."
                alert.addButton(withTitle:"Open Browser"); alert.addButton(withTitle:"Cancel Sign-in"); alert.addButton(withTitle:"Done")
                alert.beginSheetModal(for:self.window) { response in
                    if response == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                    if response == .alertSecondButtonReturn { Task { await tutor.cancelSignIn() } }
                }
            } else {
                alert.messageText = "Use my ChatGPT"
                alert.informativeText = "Sign in with your own ChatGPT account in your browser. No API key is needed.\n\nThe tutor uses the Codex access and usage allowance included with your account, subject to your plan and workspace settings. It teaches inside StatsDirect; your existing ChatGPT chats are not imported.\n\nWhen you press Send, your question, recent learning conversation, learning options, relevant course excerpts and the application context shown in Learning are shared with OpenAI. Choose Lessons only to exclude open documents."
                alert.addButton(withTitle:"Use my ChatGPT"); alert.addButton(withTitle:"Not Now")
                alert.beginSheetModal(for:self.window) { response in
                    guard response == .alertFirstButtonReturn else { return }
                    Task { @MainActor in
                        do {
                            let url = try await tutor.signIn()
                            if !NSWorkspace.shared.open(url) { throw ChatGPTTutor.Failure(message:"The browser could not open. Choose Tutor connection to reopen the sign-in page.") }
                            self.learningScript(doc,"notice","Finish signing in in your browser, then return here and send your question.")
                        } catch { self.learningScript(doc,"notice",error.localizedDescription) }
                    }
                }
            }
        }
    }
    func askLearningTutor(_ doc: Document, _ body: [String:Any]) {
        guard doc.learningTask == nil, let id = body["id"] as? String else { return }
        func failure(_ message: String) { learningScript(doc,"tutorError",["id":id,"message":message]) }
        if let quiz = doc.learningState?["quiz"] as? [String:Any], quiz["mode"] as? String == "test", quiz["completedAt"] is NSNull { failure("Finish or end the independent practice before asking the tutor."); return }
        guard chatGPTTutor.account != nil else { failure("Choose Use my ChatGPT to connect your account, then send your question."); return }
        guard let lessonID = body["lesson"] as? String, let lesson = learningLessons.first(where:{$0["id"] as? String == lessonID}),
              let messages = body["messages"] as? [[String:String]], let profile = body["profile"] as? String, let stage = body["stage"] as? String else { return }
        var context = "Learner pathway: \(profile.prefix(100)). R experience: \(stage.prefix(100)).\n"
        for field in ["title","objective","summary","challenge","steps","r"] { context += "\(field): \(lesson[field] as? String ?? "")\n" }
        if let question = body["practiceContext"] as? String { context += "Practice discussion: \(question.prefix(6000))\n" }
        if let goals = body["learningGoals"] as? [String:Any] {
            for field in ["needs","qualifications","priorKnowledge","targetDate","style"] { if let text = goals[field] as? String { context += "Learner \(field): \(text.prefix(2500))\n" } }
            if let focus = goals["focus"] as? [String] { context += "Learning priorities: " + focus.prefix(10).joined(separator:", ") + "\n" }
        }
        var courseSources: [[String:String]] = []
        if let pack = loadCoursePack() {
            let excerpts = pack.excerpts(for:(messages.last?["text"] ?? "") + " " + (lesson["topic"] as? String ?? ""))
            context += "\nCOURSE REFERENCE EXCERPTS from " + pack.title + ":\n"
            for excerpt in excerpts {
                context += "[Course: " + excerpt.id + "] " + excerpt.title + "\n" + excerpt.text + "\n\n"
                courseSources.append(["id":excerpt.id,"title":excerpt.title])
            }
        }
        doc.learningRequestID = id
        doc.learningTask = Task { @MainActor [weak self, weak doc] in
            guard let self, let doc else { return }
            defer { if doc.learningRequestID == id { doc.learningTask = nil; doc.learningRequestID = nil; self.refreshLearningWorkspace(doc) } }
            do {
                let workspace = LearningWorkspace(self,doc,id)
                let overview = try await workspace.overview()
                let metadata = String(decoding:try JSONSerialization.data(withJSONObject:overview,options:[.sortedKeys]),as:UTF8.self)
                let methods = self.analysisCatalog.keys.sorted().map { $0 + ": " + (self.analysisCatalog[$0]?["title"] as? String ?? $0) }.joined(separator:"\n")
                let tools = TutorTools.definitions.filter { !workspace.allowed.isEmpty || ["statsdirect_method_help","statsdirect_workspace"].contains($0["name"] as? String ?? "") }
                let result = try await self.chatGPTTutor.converse(context:"CURRENT STATSDIRECT WORKSPACE (metadata, not cell values):\n" + String(metadata.prefix(18000)) + "\nBUNDLED LESSON AND LEARNING CONTEXT (separate from open data):\n" + context + "\nMETHOD CATALOGUE:\n" + methods,messages:messages,tools:tools) { name, arguments in
                    try await workspace.call(name,arguments)
                }
                try Task.checkCancellation()
                guard doc.learningRequestID == id else { return }
                self.learningScript(doc,"reply",["id":id,"text":result.text,"model":result.model,"responseID":result.responseID,"promptVersion":result.promptVersion,"courseSources":courseSources,"workspaceSources":workspace.sources])
            } catch {
                if !Task.isCancelled, doc.learningRequestID == id {
                    self.learningScript(doc,"tutorError",["id":id,"message":error is URLError ? "ChatGPT could not be reached. Check your network and try again." : error.localizedDescription])
                }
            }
        }
    }

    func openLearningExample(_ lesson: [String:Any], inR: Bool) {
        let title = lesson["title"] as? String ?? "Learning example"
        if inR, let script = lesson["r"] as? String {
            let doc = newDocument(kind:"r",title:"R · " + title)
            let pane = RPane(script:script); doc.rPane = pane; doc.item.view = pane.view; pane.runScript(); return
        }
        guard let operation = lesson["operation"] as? String, let definition = analysisCatalog[operation] else { return }
        var source: [String:Any]?
        if let columns = lesson["columns"] as? [[String:Any]], !columns.isEmpty {
            var cells: [[String:Any]] = []; var rows = 0
            for (col,column) in columns.enumerated() {
                cells.append(["col":col,"row":0,"text":column["title"] as? String ?? "Variable","kind":"text"])
                let values = column["values"] as? [NSNumber] ?? []; rows = max(rows,values.count)
                for (row,value) in values.enumerated() { cells.append(["col":col,"row":row+1,"text":value.stringValue,"kind":"number"]) }
            }
            let grid = newDocument(kind:"grid",title:"Example · " + title,url:root.appendingPathComponent("Grid/index.html"))
            grid.workbookName = title + ".xlsx"
            grid.pendingWorkbook = ["name":grid.workbookName,"formulaCount":0,"sheets":[["name":"Fictional data","rows":max(100,rows+1),"columns":max(8,columns.count),"headerRow":true,"cells":cells]]]
            source = ["name":title + " / Fictional data","columns":columns.map{$0["title"] as? String ?? "Variable"},"cells":cells,"firstRow":2,"rows":rows+1,"selection":Array(0..<columns.count),"range":["first":2,"last":rows+1],"formulasStale":false]
        }
        let doc = newDocument(kind:"operation",title:nextAnalysisTitle(definition["title"] as? String ?? title),url:root.appendingPathComponent("Grid/operation.html"))
        doc.operationName = operation; doc.initialOperationSource = source
    }
    func exportLearningRecord(_ doc: Document, body: [String:Any], email: Bool) {
        guard let text = body["text"] as? String, text.utf8.count <= 10_000_000, let record = body["record"] as? [String:Any],
              let json = try? JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]), json.count <= 10_000_000 else { return }
        let filename = "StatsDirect-learning-" + ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
        if email {
            guard let recipient = body["recipient"] as? String, ["support@statsdirect.com","chil@liverpool.ac.uk"].contains(recipient) else { return }
            do {
                let folder = learningFolder.appendingPathComponent("Review drafts").appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let attachment = folder.appendingPathComponent(filename + ".txt")
                try Data(text.utf8).write(to:attachment,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:attachment.path)
                guard let service = NSSharingService(named:.composeEmail), service.canPerform(withItems:[attachment]) else {
                    NSWorkspace.shared.activateFileViewerSelecting([attachment])
                    learningScript(doc,"notice","Mail is not configured. The review record is ready in Finder; attach it to your own email to " + recipient + "."); return
                }
                service.recipients = [recipient]; service.subject = "StatsDirect learning record — external review request"
                service.perform(withItems:["Please review my attached StatsDirect learning record, including practice answers and the teaching conversation, and advise whether it can support external accreditation or CPD. The provisional score has not been independently verified and no credit has been awarded.",attachment])
                learningScript(doc,"notice","Email draft opened with the complete learning record attached. Review it and send it in Mail. StatsDirect cannot confirm delivery or accreditation.")
            } catch { learningScript(doc,"notice","Could not prepare the email attachment: " + error.localizedDescription) }
        } else {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText,.json]; panel.nameFieldStringValue = filename + ".txt"
            panel.beginSheetModal(for:window) { response in
                guard response == .OK, let url = panel.url else { return }
                do { try (url.pathExtension.lowercased() == "json" ? json : Data(text.utf8)).write(to:url,options:.atomic); self.learningScript(doc,"notice","Learning record exported to " + url.lastPathComponent) }
                catch { self.showError(error.localizedDescription) }
            }
        }
    }
}
