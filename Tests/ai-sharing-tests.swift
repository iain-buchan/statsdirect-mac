import Foundation
@main struct SharingTests {
    @MainActor static func main() {
        let session=AISharingConsent()
        precondition(!session.accepted)
        session.selectDataDocument("A");session.approve()
        let original=session.revision
        precondition(session.accepts(["A"]) && !session.accepts(["B"]))
        precondition(!session.selectDataDocument("A") && session.revision==original && session.accepted)
        session.approve(["A","B"])
        session.approve([]) // A report-only question must not forget already approved workbooks.
        precondition(session.accepts(["A","B"]))
        session.shareDocument=true;session.shareWorkbook=true
        precondition(session.selectDataDocument("B") && !session.accepted && session.revision>original)
        precondition(session.shareDocument && session.shareWorkbook)
        session.approve();precondition(session.accepts(["B"]) && !session.accepts(["A"]))
        session.revoke();precondition(!session.accepted)
        precondition(!AISharingConsent().accepted)
        print("PASS: app-session consent, same-data reuse, approved-set retention, new-data reset, explicit revocation and restart boundaries")
    }
}
