import Cocoa

// The confirmation covers exactly one question, before even document metadata is sent.
// It is deliberately separate from account sign-in and is never inferred from a saved preference.
enum LearningSharingDecision { case share, lessonsOnly, cancel }

@MainActor private final class SharingConfirmation: NSObject {
    let checkbox = NSButton(checkboxWithTitle:"I have checked these documents and confirm they contain no person identifiers.",target:nil,action:nil)
    weak var shareButton: NSButton?
    init(button: NSButton) {
        super.init(); shareButton = button; button.isEnabled = false
        checkbox.target = self; checkbox.action = #selector(changed)
        checkbox.cell?.wraps = true
    }
    @objc func changed() { shareButton?.isEnabled = checkbox.state == .on }
}

extension Viewer {
    static let learningSharingStatement = "Share the listed document names, worksheet names and column headings with OpenAI for this question. The tutor may read their worksheet values, reports, analysis inputs, R scripts and output, and request StatsDirect calculations. I have checked these documents and confirm they contain no person identifiers: names, dates of birth, postcodes, NHS or hospital numbers, contact details or identifying free-text notes. Heading checks are only a backstop, not anonymisation."

    func confirmLearningSharing(_ documents: [Document]) async -> LearningSharingDecision {
        let alert = NSAlert()
        alert.messageText = "Share document context with the tutor?"
        alert.informativeText = "For this question, OpenAI will receive names and headings and may receive values and content from the documents below. Check every worksheet, report and R output for person identifiers first.\n\nRemove names, dates of birth, postcodes, NHS or hospital numbers, contact details and identifying free-text notes. Heading checks cannot guarantee anonymity. Previously shared content can remain in the learning conversation."
        alert.addButton(withTitle:"Share for This Question")
        alert.addButton(withTitle:"Use Lessons Only")
        alert.addButton(withTitle:"Cancel")
        let confirmation = SharingConfirmation(button:alert.buttons[0])
        let accessory = NSView(frame:NSRect(x:0,y:0,width:420,height:180))
        let list = NSTextView(frame:NSRect(x:0,y:0,width:400,height:100))
        list.isEditable = false; list.font = .systemFont(ofSize:12)
        list.string = documents.map{"• " + $0.title + " (" + $0.kind + ")"}.joined(separator:"\n")
        let scroll = NSScrollView(frame:NSRect(x:0,y:65,width:420,height:115))
        scroll.hasVerticalScroller = true; scroll.documentView = list
        list.isVerticallyResizable = true; list.textContainer?.widthTracksTextView = true
        confirmation.checkbox.frame = NSRect(x:0,y:0,width:420,height:55)
        accessory.addSubview(scroll); accessory.addSubview(confirmation.checkbox); alert.accessoryView = accessory
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for:window) { response in
                if response == .alertFirstButtonReturn && confirmation.checkbox.state == .on { continuation.resume(returning:.share) }
                else if response == .alertSecondButtonReturn { continuation.resume(returning:.lessonsOnly) }
                else { continuation.resume(returning:.cancel) }
            }
        }
    }

    func persistLearningState(_ doc: Document, _ state: [String:Any]) throws {
        guard state["schemaVersion"] as? Int == 2 else { throw ChatGPTTutor.Failure(message:"The learning record is not ready. Reopen Learning and try again.") }
        let data = try JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys])
        guard data.count <= 10_000_000 else { throw ChatGPTTutor.Failure(message:"The learning record is too large to save. Export a copy before continuing.") }
        try FileManager.default.createDirectory(at:learningFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let url = learningFolder.appendingPathComponent("portfolio.json")
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        doc.learningState = state
    }

    func recordLearningSharing(_ doc: Document, _ requestID: String, _ documents: [Document]) async throws {
        let record: [String:Any] = ["id":UUID().uuidString,"at":ISO8601DateFormatter().string(from:Date()),"requestID":requestID,"policyVersion":"document-sharing-v1","noPersonIdentifiers":true,"statement":Self.learningSharingStatement,"documents":documents.map{["id":$0.id,"title":$0.title,"kind":$0.kind,"version":$0.gridVersion] as [String:Any]}]
        let json = String(decoding:try JSONSerialization.data(withJSONObject:record),as:UTF8.self)
        let response = try await learningJavaScript(doc,"window.statsDirectLearn.recordSharingConsent(\(json))")
        guard let state = response["state"] as? [String:Any] else { throw ChatGPTTutor.Failure(message:"Sharing confirmation could not be recorded. No document context was sent.") }
        // Persist synchronously before granting any document access; a queued UI save is not sufficient.
        try persistLearningState(doc,state)
    }
}
