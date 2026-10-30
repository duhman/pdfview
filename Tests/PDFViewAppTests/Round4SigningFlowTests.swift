import Foundation
import Testing
@testable import PDFViewApp

// MARK: Kind-aware entry mode

@Test func onlySignaturesStartInFieldsWhenThePDFHasSignatureFields() {
    let choices = PlacementChoices()
    #expect(choices.entryMode(for: .signature, hasSignatureFields: true) == .fieldPlacement)
    #expect(choices.entryMode(for: .initials, hasSignatureFields: true) == .freePlacement)
    #expect(choices.entryMode(for: .date, hasSignatureFields: true) == .freePlacement)
    for kind in StampKind.allCases {
        #expect(choices.entryMode(for: kind, hasSignatureFields: false) == .freePlacement)
    }
}

@Test func theFieldsOrAnywhereChoiceIsRememberedPerKind() {
    var choices = PlacementChoices()
    choices.remember(anywhere: true, for: .signature)
    choices.remember(anywhere: false, for: .initials)
    #expect(choices.entryMode(for: .signature, hasSignatureFields: true) == .freePlacement)
    #expect(choices.entryMode(for: .initials, hasSignatureFields: true) == .fieldPlacement)
    // Untouched kinds keep their defaults.
    #expect(choices.entryMode(for: .date, hasSignatureFields: true) == .freePlacement)
    // A remembered Fields choice cannot apply to a PDF without fields.
    #expect(choices.entryMode(for: .initials, hasSignatureFields: false) == .freePlacement)
}

@Test func placeInNextFieldIsForSignaturesOnly() {
    #expect(SigningFlowLogic.nextFieldUnavailableReason(kind: .signature, hasSignatureFields: true) == nil)
    #expect(SigningFlowLogic.nextFieldUnavailableReason(kind: .initials, hasSignatureFields: true)
        == "Place in Next Field places signatures. Click a field or the page to place initials.")
    #expect(SigningFlowLogic.nextFieldUnavailableReason(kind: .date, hasSignatureFields: true)
        == "Place in Next Field places signatures. Click a field or the page to place the date.")
    #expect(SigningFlowLogic.nextFieldUnavailableReason(kind: .signature, hasSignatureFields: false)
        == "This PDF has no signature fields.")
}

@Test func initialsInFieldsModeDoNotAdvertisePlaceInNextField() {
    let text = SigningFlowLogic.statusText(mode: .fieldPlacement, kind: .initials)
    #expect(!text.contains("Next Field"))
    #expect(text.hasPrefix("Click a signature field, or choose Anywhere"))
}
