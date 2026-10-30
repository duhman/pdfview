import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@Test func entryModeUsesFieldPlacementWhenFieldsExist() {
    #expect(SigningFlowLogic.entryMode(hasSignatureFields: true) == .fieldPlacement)
}

@Test func entryModeUsesFreePlacementWhenNoFields() {
    #expect(SigningFlowLogic.entryMode(hasSignatureFields: false) == .freePlacement)
}

@Test func signToggleStartsAndStopsSigning() {
    #expect(SigningFlowLogic.toggled(.idle, hasSignatureFields: true) == .fieldPlacement)
    #expect(SigningFlowLogic.toggled(.idle, hasSignatureFields: false) == .freePlacement)
    #expect(SigningFlowLogic.toggled(.fieldPlacement, hasSignatureFields: true) == .idle)
    #expect(SigningFlowLogic.toggled(.freePlacement, hasSignatureFields: false) == .idle)
}

@Test func doneAndEscapeReturnToIdleFromEverySigningMode() {
    for mode in [SigningMode.idle, .fieldPlacement, .freePlacement] {
        #expect(SigningFlowLogic.exited(mode) == .idle)
    }
}

@Test func placingOneSignatureEndsSigning() {
    #expect(SigningFlowLogic.afterPlacement(.fieldPlacement) == .idle)
    #expect(SigningFlowLogic.afterPlacement(.freePlacement) == .idle)
}

@Test func anywhereChoiceSelectsPlacementMode() {
    #expect(SigningFlowLogic.mode(anywhere: true, hasSignatureFields: true) == .freePlacement)
    #expect(SigningFlowLogic.mode(anywhere: false, hasSignatureFields: true) == .fieldPlacement)
    // Without fields there is nothing else to choose.
    #expect(SigningFlowLogic.mode(anywhere: false, hasSignatureFields: false) == .freePlacement)
}

@Test func losingFieldsWhileSigningFallsBackToAnywhere() {
    #expect(SigningFlowLogic.refreshed(.fieldPlacement, hasSignatureFields: false) == .freePlacement)
    #expect(SigningFlowLogic.refreshed(.fieldPlacement, hasSignatureFields: true) == .fieldPlacement)
    #expect(SigningFlowLogic.refreshed(.idle, hasSignatureFields: false) == .idle)
}

@Test func announcementsDescribeTheOutcome() {
    #expect(SigningFlowLogic.enteredAnnouncement(mode: .freePlacement).contains("Escape"))
}

@Test func nextFieldCyclesThroughDetectedFields() {
    #expect(SigningFlowLogic.nextFieldIndex(after: nil, count: 3) == 0)
    #expect(SigningFlowLogic.nextFieldIndex(after: 0, count: 3) == 1)
    #expect(SigningFlowLogic.nextFieldIndex(after: 2, count: 3) == 0)
    #expect(SigningFlowLogic.nextFieldIndex(after: 7, count: 3) == 0)
    #expect(SigningFlowLogic.nextFieldIndex(after: nil, count: 0) == nil)
}

@Test func unexportedStateTracksTheLastSavedPlacements() {
    let placement = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
        signaturePNGData: Data([1]),
        signerName: "A"
    )
    var moved = placement
    moved.bounds.origin.x = 5

    #expect(!SigningFlowLogic.hasUnexportedPlacements([], exported: nil))
    #expect(SigningFlowLogic.hasUnexportedPlacements([placement], exported: nil))
    #expect(!SigningFlowLogic.hasUnexportedPlacements([placement], exported: [placement]))
    #expect(SigningFlowLogic.hasUnexportedPlacements([moved], exported: [placement]))
    #expect(!SigningFlowLogic.hasUnexportedPlacements([], exported: [placement]))
}

@Test func signedFileNameComesFromTheDocumentsOwnURL() {
    let url = URL(fileURLWithPath: "/Users/a/Contracts/lease 2026.pdf")
    #expect(SigningFlowLogic.signedFileName(for: url) == "lease 2026-signed.pdf")
    #expect(SigningFlowLogic.signedFileName(for: nil) == "document-signed.pdf")
}

@Test func errorAlertNamesTheFailedActionAndAddsRecovery() {
    struct Failure: LocalizedError {
        var errorDescription: String? {
            "The disk is full."
        }

        var recoverySuggestion: String? {
            "Free up space and try again."
        }
    }

    let alert = ErrorAlert(title: "Couldn’t Save Signed Copy", error: Failure())
    #expect(alert.title == "Couldn’t Save Signed Copy")
    #expect(alert.message == "The disk is full. Free up space and try again.")

    let plain = ErrorAlert(title: "Couldn’t Save Signed Copy", error: CocoaError(.fileWriteNoPermission))
    #expect(!plain.message.isEmpty)
}

@Test func onlyRealSignatureFieldsAreDetected() throws {
    let document = try makeFormDocument()
    let fields = SigningFlowLogic.signatureFields(in: document)

    #expect(fields == [
        SignatureField(pageIndex: 1, bounds: CGRect(x: 20, y: 100, width: 220, height: 50), name: "ClientSignature"),
    ])
}

@Test func textFieldNamedLikeASignatureIsNotDetected() throws {
    let document = try makeFormDocument()
    let contact = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "DesignatedContact" })

    #expect(!SigningFlowLogic.isSignatureField(contact))
}

/// Two pages: page 1 has a text field whose name contains "sig"; page 2 has a real /Sig field.
private func makeFormDocument() throws -> PDFDocument {
    let image = NSImage(size: NSSize(width: 400, height: 600))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 600).fill()
    image.unlockFocus()

    let document = PDFDocument()
    for index in 0 ..< 2 {
        try document.insert(#require(PDFPage(image: image)), at: index)
    }

    let contact = PDFAnnotation(
        bounds: CGRect(x: 20, y: 20, width: 200, height: 30),
        forType: .widget,
        withProperties: nil
    )
    contact.widgetFieldType = .text
    contact.fieldName = "DesignatedContact"
    document.page(at: 0)?.addAnnotation(contact)

    let signature = PDFAnnotation(
        bounds: CGRect(x: 20, y: 100, width: 220, height: 50),
        forType: .widget,
        withProperties: nil
    )
    signature.widgetFieldType = .signature
    signature.fieldName = "ClientSignature"
    document.page(at: 1)?.addAnnotation(signature)

    // Round-trip through bytes so detection runs on parsed fields, as it does for opened files.
    let data = try #require(document.dataRepresentation())
    return try #require(PDFDocument(data: data))
}
