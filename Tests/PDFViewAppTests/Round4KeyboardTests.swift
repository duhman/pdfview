import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
func keyEvent(
    _ key: Int,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = [],
    function: Bool = true
) throws -> NSEvent {
    let character = try String(#require(UnicodeScalar(key)).description)
    return try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: function ? modifiers.union([.numericPad, .function]) : modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: keyCode
    ))
}

@MainActor
private func downArrow(_ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try keyEvent(NSDownArrowFunctionKey, keyCode: 125, modifiers: modifiers)
}

private enum Sample {
    static let stamp = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 40, y: 40, width: 60, height: 20),
        signaturePNGData: Data([1]),
        signerName: "Tester",
        kind: .initials
    )
}

// MARK: Arrow keys after placement

@MainActor
@Test func aJustPlacedStampLeavesPlainArrowsToScrolling() throws {
    let coordinator = makeRepresentable(placements: [Sample.stamp]).makeCoordinator()
    coordinator.select(Sample.stamp.id, ownsArrowKeys: false)
    #expect(coordinator.selectedPlacementID == Sample.stamp.id)
    #expect(!coordinator.stampOwnsArrowKeys)
    #expect(try !coordinator.handleKey(downArrow()))
    #expect(try !coordinator.handleKey(downArrow(.shift)))
}

@MainActor
@Test func anExplicitlySelectedStampTakesTheArrowKeys() throws {
    let coordinator = makeRepresentable(placements: [Sample.stamp]).makeCoordinator()
    coordinator.select(Sample.stamp.id, ownsArrowKeys: true)
    #expect(coordinator.stampOwnsArrowKeys)
    #expect(try coordinator.handleKey(downArrow()))
    // Choosing another stamp, or none, gives the arrows back until it is explicitly selected.
    coordinator.select(nil, ownsArrowKeys: true)
    #expect(!coordinator.stampOwnsArrowKeys)
}

@MainActor
@Test func clickingAStampSelectsItForTheArrowKeys() throws {
    let document = try ExportFixture.document()
    let coordinator = makeRepresentable(document: document, placements: [Sample.stamp]).makeCoordinator()
    let page = try #require(document.page(at: 0))
    coordinator.overlay(PageOverlayView(page: page), didSelect: Sample.stamp.id)
    #expect(coordinator.stampOwnsArrowKeys)
}

@Test func selectNextStampFirstTakesTheStampThatIsAlreadySelected() {
    let other = PDFViewerDocument.SignaturePlacement(
        pageIndex: 1,
        bounds: CGRect(x: 40, y: 40, width: 60, height: 20),
        signaturePNGData: Data([1]),
        signerName: "Tester"
    )
    let placements = [Sample.stamp, other]
    // Just placed: Select Next Stamp hands the arrows to that stamp rather than skipping past it.
    #expect(SigningFlowLogic.stampToSelect(
        after: Sample.stamp.id, ownsArrowKeys: false, in: placements, forward: true
    ) == Sample.stamp.id)
    #expect(SigningFlowLogic.stampToSelect(
        after: Sample.stamp.id, ownsArrowKeys: true, in: placements, forward: true
    ) == other.id)
    #expect(SigningFlowLogic.stampToSelect(after: nil, ownsArrowKeys: false, in: placements, forward: false)
        == other.id)
}

@Test func placementAnnouncementExplainsHowToStartMovingTheStamp() {
    #expect(StampAccessibility.placedAnnouncement(pageIndex: 1, location: "at center", kind: .initials)
        == "Initials placed on page 2, at center. To move it, choose Sign > Select Next Stamp (⌥⌘]), "
        + "then use the arrow keys.")
}

// MARK: Escape

@MainActor
@Test func escapeDeselectsTheStampAndSaysSo() throws {
    let coordinator = makeRepresentable(placements: [Sample.stamp]).makeCoordinator()
    coordinator.select(Sample.stamp.id, ownsArrowKeys: true)
    let escape = try keyEvent(0x1B, keyCode: 53, function: false)
    #expect(coordinator.handleKey(escape))
    #expect(coordinator.selectedPlacementID == nil)
    #expect(StampAccessibility.deselectedAnnouncement == "Stamp deselected.")
}

// MARK: Coarse nudge

@Test func commandArrowsMoveASelectedStampFiftyPoints() {
    #expect(PlacementGeometry.arrowAction(shift: false, option: false, command: true) == .move(50))
    // Option-Command arrows stay with First/Last Page and Next/Previous Form Field.
    #expect(PlacementGeometry.arrowAction(shift: false, option: true, command: true) == nil)
    #expect(PlacementGeometry.arrowAction(shift: true, option: false, command: true) == nil)
    // Control-arrows belong to Mission Control and Spaces.
    #expect(PlacementGeometry.arrowAction(shift: false, option: false, control: true) == nil)
    #expect(PlacementGeometry.arrowAction(shift: false, option: false) == .move(1))
}

@MainActor
@Test func commandArrowIsClaimedBeforeTheMenusButOptionCommandArrowIsNot() throws {
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    let window = NSWindow(contentRect: pdfView.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = pdfView
    window.makeFirstResponder(pdfView)
    var handled = 0
    pdfView.stampOwnsArrowKeys = { true }
    pdfView.keyHandler = { _ in
        handled += 1
        return true
    }
    #expect(try pdfView.performKeyEquivalent(with: downArrow(.command)))
    _ = try pdfView.performKeyEquivalent(with: downArrow([.command, .option]))
    #expect(handled == 1)
}

@Test func moveInstructionsMentionTheCoarseStep() {
    #expect(StampAccessibility.moveInstructions(for: .date).contains("Command moves 50 points"))
}
