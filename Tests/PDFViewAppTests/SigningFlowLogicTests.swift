import Testing
@testable import PDFViewApp

@Test func entryModeUsesFieldPlacementWhenFieldsExist() {
    #expect(SigningFlowLogic.entryMode(hasSignatureFields: true) == .fieldPlacement)
}

@Test func entryModeUsesFreePlacementWhenNoFields() {
    #expect(SigningFlowLogic.entryMode(hasSignatureFields: false) == .freePlacement)
}

@Test func toggleFromFieldToFree() {
    #expect(
        SigningFlowLogic.toggledMode(current: .fieldPlacement, hasSignatureFields: true) == .freePlacement
    )
}

@Test func toggleFromFreeKeepsFreeWhenNoFields() {
    #expect(
        SigningFlowLogic.toggledMode(current: .freePlacement, hasSignatureFields: false) == .freePlacement
    )
}

@Test func statusTextStatesVisualStampScope() {
    let text = SigningFlowLogic.statusText(mode: .fieldPlacement, hasSignatureFields: true)
    #expect(text.contains("Visual signature stamp mode"))
}
