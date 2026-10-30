import Foundation
import Testing
@testable import PDFViewApp

@Test func savedMessageNamesTheFolder() {
    let url = URL(fileURLWithPath: "/Users/a/Documents/lease-signed.pdf")
    #expect(SigningFlowLogic.savedText(for: url) == "Saved “lease-signed.pdf” to Documents")
    #expect(SigningFlowLogic.savedAnnouncement(for: url) == "Saved lease-signed.pdf to Documents")
}

@Test func bannerTextOffersTheKeyboardPath() {
    #expect(
        SigningFlowLogic.statusText(mode: .freePlacement)
            == "Click where you want to sign, or use Sign > Place Signature on Current Page (⌥⌘P)."
    )
    #expect(
        SigningFlowLogic.statusText(mode: .fieldPlacement)
            == "Click a signature field, choose Anywhere, or use Sign > Place Signature in Next Field (⌥⌘N)."
    )
    #expect(SigningFlowLogic.enteredAnnouncement(mode: .freePlacement).hasSuffix("Press Escape to stop."))
    #expect(SigningFlowLogic.exitedAnnouncement == "Stopped signing.")
}

@Test func signatureMenuCreatesUntilAProfileExists() {
    #expect(SigningFlowLogic.signatureMenuTitle(hasProfile: false) == "Create Signature…")
    #expect(SigningFlowLogic.signatureMenuTitle(hasProfile: true) == "Edit Signature…")
}

@Test func escapeStopsTheMostRecentThingFirst() {
    func action(
        exporting: Bool = false,
        signing: Bool = false,
        find: Bool = false,
        selected: Bool = false
    ) -> EscapeAction {
        SigningFlowLogic.escapeAction(
            isExporting: exporting,
            isSigning: signing,
            isFindVisible: find,
            hasSelection: selected
        )
    }
    #expect(action(exporting: true, signing: true, find: true) == .cancelExport)
    #expect(action(signing: true, find: true) == .stopSigning)
    #expect(action(find: true, selected: true) == .closeFind)
    #expect(action(selected: true) == .deselect)
    #expect(action() == .none)
}
