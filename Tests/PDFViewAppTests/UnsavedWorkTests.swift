import Foundation
import Testing
@testable import PDFViewApp

private enum Sample {
    static let placement = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
        signaturePNGData: Data([1]),
        signerName: "A"
    )
    static let empty = [FormFieldValue(fieldName: "Name", stringValue: "", buttonState: 0)]
    static let filled = [FormFieldValue(fieldName: "Name", stringValue: "Jane", buttonState: 0)]
}

@Test func formEntriesCountAsUnsavedWorkUntilSaved() {
    let none = SigningFlowLogic.unsavedWork(
        placements: [],
        exported: nil,
        formValues: Sample.empty,
        savedFormValues: Sample.empty
    )
    #expect(none.isEmpty)

    let form = SigningFlowLogic.unsavedWork(
        placements: [],
        exported: nil,
        formValues: Sample.filled,
        savedFormValues: Sample.empty
    )
    #expect(form == UnsavedWork(signatures: false, formEntries: true))

    let saved = SigningFlowLogic.unsavedWork(
        placements: [],
        exported: nil,
        formValues: Sample.filled,
        savedFormValues: Sample.filled
    )
    #expect(saved.isEmpty)

    let both = SigningFlowLogic.unsavedWork(
        placements: [Sample.placement], exported: nil, formValues: Sample.filled, savedFormValues: Sample.empty
    )
    #expect(both == UnsavedWork(signatures: true, formEntries: true))
}

@Test func unavailableFormValuesMustWarnBeforeClose() {
    let work = SigningFlowLogic.unsavedWork(placements: [], exported: nil, formValues: nil, savedFormValues: nil)
    #expect(work.formEntries)
}

@Test func closeWarningNamesWhatWillBeLost() {
    #expect(UnsavedWork(signatures: true).lossWarning == "Your signatures will be lost if you don’t save.")
    #expect(UnsavedWork(formEntries: true).lossWarning == "Your form entries will be lost if you don’t save.")
    #expect(
        UnsavedWork(signatures: true, formEntries: true).lossWarning
            == "Your signatures and form entries will be lost if you don’t save."
    )
}

@Test func filledFormWithoutStampsCanBeSaved() {
    #expect(SigningFlowLogic.hasSignedCopyContent(
        placements: [],
        formValues: Sample.filled,
        originalFormValues: Sample.empty
    ))
    #expect(!SigningFlowLogic.hasSignedCopyContent(
        placements: [],
        formValues: Sample.empty,
        originalFormValues: Sample.empty
    ))
    #expect(SigningFlowLogic.hasSignedCopyContent(
        placements: [Sample.placement],
        formValues: nil,
        originalFormValues: nil
    ))
}

@Test func deletingAllExportedPlacementsIsUnsavedWork() {
    #expect(SigningFlowLogic.hasUnexportedPlacements([], exported: [Sample.placement]))
}
