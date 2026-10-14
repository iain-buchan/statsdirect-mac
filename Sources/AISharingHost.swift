import Foundation

@MainActor extension Viewer {
    func selectAIDataDocument(_ id: String?) {
        guard aiSharing.selectDataDocument(id) else { return }
        scriptAI.sessionSharingChanged()
        for doc in documents where doc.kind == "learn" {
            doc.learningTask?.cancel()
            refreshLearningWorkspace(doc)
        }
    }
}
