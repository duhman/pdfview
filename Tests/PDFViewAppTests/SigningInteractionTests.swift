import Foundation
import Testing
@testable import PDFViewApp

@Test func savedMessageNamesTheFolder() {
    let url = URL(fileURLWithPath: "/Users/a/Documents/lease-signed.pdf")
    #expect(SigningFlowLogic.savedText(for: url) == "Saved “lease-signed.pdf” to Documents")
    #expect(SigningFlowLogic.savedAnnouncement(for: url) == "Saved lease-signed.pdf to Documents")
}
