import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

// MARK: Push buttons

@Test func aPushButtonSaysItCannotBeUsedFromTheKeyboard() {
    #expect(FormFieldNavigation.unavailableMessage(name: "Submit", kind: .button)
        == "Submit is a button and can’t be pressed from the keyboard.")
    #expect(FormFieldNavigation.unavailableMessage(name: nil, kind: .button)
        == "This button can’t be pressed from the keyboard.")
    #expect(FormFieldNavigation.unavailableMessage(name: "Agree", kind: .checkbox) == "Agree can’t be changed.")
}

// MARK: Saved banner path

@Test func theSavedMessageNamesTheFolderAsAnAbbreviatedPath() {
    let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
    let url = URL(fileURLWithPath: "/Users/a/Documents/Contracts/lease-signed.pdf")
    #expect(SigningFlowLogic.savedText(for: url, home: home) == "Saved “lease-signed.pdf” to ~/Documents/Contracts")
    #expect(SigningFlowLogic.savedAnnouncement(for: url, home: home)
        == "Saved lease-signed.pdf to ~/Documents/Contracts")
}

@Test func savedFolderNamesCoverHomeICloudDriveAndOtherVolumes() {
    let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
    func folder(_ path: String) -> String {
        SigningFlowLogic.folderDisplayName(of: URL(fileURLWithPath: path), home: home)
    }
    #expect(folder("/Users/a/lease.pdf") == "~")
    #expect(folder("/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Leases/lease.pdf") == "iCloud Drive/Leases")
    #expect(folder("/Users/a/Library/Mobile Documents/com~apple~CloudDocs/lease.pdf") == "iCloud Drive")
    #expect(folder("/Volumes/USB/Signed/lease.pdf") == "/Volumes/USB/Signed")
    // A sibling whose name starts with the home folder's name is not inside it.
    #expect(folder("/Users/ab/lease.pdf") == "/Users/ab")
}

@Test func theRealHomeFolderIsUsedNotTheSandboxContainer() {
    #expect(!SigningFlowLogic.userHome.path.contains("/Library/Containers/"))
}

// MARK: Unlock

@Test func aSuccessfulUnlockIsAnnouncedWithThePageCount() {
    #expect(UnlockDocumentSheet.unlockedAnnouncement(pageCount: 1) == "Unlocked, 1 page")
    #expect(UnlockDocumentSheet.unlockedAnnouncement(pageCount: 12) == "Unlocked, 12 pages")
}

// MARK: Save Signed Copy explains itself

@Test func aDisabledSaveSignedCopySaysWhatIsMissing() {
    #expect(SigningFlowLogic.saveSignedCopyUnavailableReason(canSave: true, isLocked: false, isBusy: false) == nil)
    #expect(SigningFlowLogic.saveSignedCopyUnavailableReason(canSave: false, isLocked: false, isBusy: false)
        == "Place a signature or fill a field first.")
    #expect(SigningFlowLogic.saveSignedCopyUnavailableReason(canSave: false, isLocked: true, isBusy: false)
        == "Unlock this PDF first.")
    #expect(SigningFlowLogic.saveSignedCopyUnavailableReason(canSave: false, isLocked: false, isBusy: true)
        == "Wait for the current save or print to finish.")
}

// MARK: Sign > Anywhere

@Test func anywhereIsAvailableOnlyWhileSigningAPDFWithSignatureFields() {
    // While idle, choosing Anywhere would start signing as a side effect, so it is disabled.
    #expect(!SigningFlowLogic.anywhereIsEnabled(mode: .idle, canSign: true, hasSignatureFields: true))
    #expect(SigningFlowLogic.anywhereIsEnabled(mode: .fieldPlacement, canSign: true, hasSignatureFields: true))
    #expect(SigningFlowLogic.anywhereIsEnabled(mode: .freePlacement, canSign: true, hasSignatureFields: true))
    #expect(!SigningFlowLogic.anywhereIsEnabled(mode: .freePlacement, canSign: true, hasSignatureFields: false))
    #expect(!SigningFlowLogic.anywhereIsEnabled(mode: .fieldPlacement, canSign: false, hasSignatureFields: true))
}

// MARK: Read-only form fields

@Test func readingOrderSkipsReadOnlyFields() {
    let fields = [
        FormFieldNavigation.Field(
            pageIndex: 0,
            bounds: CGRect(x: 0, y: 700, width: 10, height: 10),
            name: "A",
            kind: .text
        ),
        FormFieldNavigation.Field(
            pageIndex: 0,
            bounds: CGRect(x: 0, y: 500, width: 10, height: 10),
            name: "Locked",
            kind: .checkbox,
            isReadOnly: true
        ),
        FormFieldNavigation.Field(
            pageIndex: 0,
            bounds: CGRect(x: 0, y: 300, width: 10, height: 10),
            name: "B",
            kind: .text
        ),
    ]
    #expect(FormFieldNavigation.readingOrder(fields).map { fields[$0].name } == ["A", "B"])
}

@Test func aDocumentWithOnlyReadOnlyFieldsSaysThereIsNothingToFillIn() {
    #expect(FormFieldNavigation.noFieldsAnnouncement == "This document has no form fields you can fill in.")
}

// MARK: Focus after Next Form Field

/// A text field above an "Agree" checkbox.
@MainActor
private func makeTextThenCheckboxForm() throws -> PDFDocument {
    let document = try ExportFixture.document()
    let page = try #require(document.page(at: 0))
    let name = PDFAnnotation(
        bounds: CGRect(x: 40, y: 600, width: 160, height: 24),
        forType: .widget,
        withProperties: nil
    )
    name.widgetFieldType = .text
    name.fieldName = "Name"
    page.addAnnotation(name)
    let agree = PDFAnnotation(
        bounds: CGRect(x: 40, y: 500, width: 20, height: 20),
        forType: .widget,
        withProperties: nil
    )
    agree.widgetFieldType = .button
    agree.widgetControlType = .checkBoxControl
    agree.fieldName = "Agree"
    page.addAnnotation(agree)
    return document
}

@MainActor
@Test func movingToACheckboxTakesTheKeyboardBackFromATextFieldBeingEdited() async throws {
    let document = try makeTextThenCheckboxForm()
    let recorder = StateRecorder()
    let coordinator = makeRepresentable(document: document, recorder: recorder).makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    let window = NSWindow(contentRect: pdfView.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = pdfView
    coordinator.attach(to: pdfView)
    pdfView.document = document
    coordinator.documentDidChange(document)
    for _ in 0 ..< 200 where recorder.states.last?.formValues == nil {
        await Task.yield()
    }
    try #require(recorder.states.last?.formValues != nil)

    // Stands in for PDFKit's editor of the text field the user was typing in.
    let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
    pdfView.addSubview(editor)
    window.makeFirstResponder(editor)
    #expect(window.firstResponder === editor)

    #expect(coordinator.moveToFormField(forward: true) == "Name, text field, page 1")
    #expect(coordinator.moveToFormField(forward: true) == "Agree, checkbox, unchecked, page 1")
    // Space and Return now reach the PDF view, which activates the checkbox, not the old text field.
    #expect(window.firstResponder === pdfView)
}

// MARK: Commands that can't act explain why instead of beeping

@Test func signingCommandsSayWhyTheyCannotRun() {
    #expect(SigningFlowLogic.signingUnavailableReason(hasPages: true, isLocked: true, isBusy: false)
        == "Unlock this PDF to sign it.")
    #expect(SigningFlowLogic.signingUnavailableReason(hasPages: true, isLocked: false, isBusy: true)
        == "Wait for the current save or print to finish.")
    #expect(SigningFlowLogic.signingUnavailableReason(hasPages: false, isLocked: false, isBusy: false)
        == "This PDF has no pages to sign.")
    #expect(SigningFlowLogic.signingUnavailableReason(hasPages: true, isLocked: false, isBusy: false)
        == "This PDF is still opening. Try again in a moment.")
}

@Test func selectNextStampWithNoStampsSaysSo() {
    #expect(SigningFlowLogic
        .noStampsNotice == "There are no stamps to select. Place a signature, initials or a date first.")
}

@Test func formFieldNavigationSaysWhyItCannotMove() {
    #expect(FormFieldNavigation.unavailableNotice(isLocked: true, isScanned: false)
        == "Unlock this PDF to use its form fields.")
    #expect(FormFieldNavigation.unavailableNotice(isLocked: false, isScanned: false)
        == "Still finding this PDF’s form fields. Try again in a moment.")
    #expect(FormFieldNavigation.unavailableNotice(isLocked: false, isScanned: true)
        == FormFieldNavigation.noFieldsAnnouncement)
}
