import Foundation

/// Memory-only approval, shared by every AI surface. No persisted preference can
/// restore it at launch. Selecting different data starts a new consent boundary.
@MainActor final class AISharingConsent {
    private(set) var dataDocumentID: String?
    private(set) var accepted = false
    private(set) var revision = 0
    private var approvedDataIDs: Set<String> = []
    var shareDocument = false
    var shareWorkbook = false
    @discardableResult func selectDataDocument(_ id: String?) -> Bool {
        guard dataDocumentID != id else { return false }
        dataDocumentID=id;revoke();return true
    }
    func accepts(_ dataIDs: Set<String> = []) -> Bool { accepted && dataIDs.isSubset(of:approvedDataIDs) }
    func approve(_ dataIDs: Set<String> = []) {
        accepted=true;approvedDataIDs.formUnion(dataIDs)
        if let dataDocumentID { approvedDataIDs.insert(dataDocumentID) }
    }
    func revoke() { accepted=false;approvedDataIDs=[];revision += 1 }
}
