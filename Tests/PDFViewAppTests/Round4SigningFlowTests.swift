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

// MARK: Cancelling setup

@Test func cancellingInitialsSetupWhileSigningRestoresTheSignatureAndItsMode() {
    let request = SetupRequest(
        pending: .enter(.freePlacement),
        restoring: SigningState(kind: .signature, mode: .fieldPlacement)
    )
    #expect(request.stateAfterCancel == SigningState(kind: .signature, mode: .fieldPlacement))
}

@Test func cancellingSetupFromIdleLeavesTheWindowIdleWithSignature() {
    let request = SetupRequest(pending: .placeOnCurrentPage, restoring: SigningState(kind: .signature, mode: .idle))
    #expect(request.stateAfterCancel == SigningState(kind: .signature, mode: .idle))
}

@Test func aRestoredKindOutsideSigningIsAlwaysSignature() {
    // Idle windows always offer Signature next, whatever was active when the sheet opened.
    let request = SetupRequest(pending: nil, restoring: SigningState(kind: .initials, mode: .idle))
    #expect(request.stateAfterCancel == SigningState(kind: .signature, mode: .idle))
}

// MARK: Initials on every page

@Test func initialsOnEveryPageHasItsOwnShortcut() {
    let chords = MenuShortcuts.appSpecific.map(MenuShortcuts.Chord.init)
    #expect(chords.contains(MenuShortcuts.Chord(MenuShortcuts.placeInitialsOnEveryPage)))
    #expect(MenuShortcuts.Chord(MenuShortcuts.placeInitialsOnEveryPage) == MenuShortcuts.Chord(
        "i",
        [.command, .option]
    ))
}

@Test func theBannerOffersInitialsOnEveryPageWhilePlacingInitials() {
    for mode in [SigningMode.freePlacement, .fieldPlacement] {
        #expect(SigningFlowLogic.statusText(mode: mode, kind: .initials)
            .hasSuffix("Sign > Place Initials on Every Page (⌥⌘I) initials every page at once."))
    }
    #expect(!SigningFlowLogic.statusText(mode: .freePlacement, kind: .date).contains("Every Page"))
}
