import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

private enum Page {
    static let crop = CGRect(x: 0, y: 0, width: 300, height: 300)
}

@Test func positionUsesThirdsOfThePageAsShownOnScreen() {
    let topLeft = CGRect(x: 10, y: 250, width: 20, height: 20)
    #expect(StampAccessibility.position(of: topLeft, in: Page.crop, rotation: 0) == "top left")
    #expect(StampAccessibility.position(of: CGRect(x: 140, y: 140, width: 20, height: 20), in: Page.crop) == "center")
    #expect(StampAccessibility
        .position(of: CGRect(x: 250, y: 10, width: 20, height: 20), in: Page.crop) == "bottom right")
    // A page shown rotated 90° clockwise puts its top-left corner at the top right of the screen.
    #expect(StampAccessibility.position(of: topLeft, in: Page.crop, rotation: 90) == "top right")
    #expect(StampAccessibility.position(of: topLeft, in: Page.crop, rotation: 180) == "bottom right")
    #expect(StampAccessibility.position(of: topLeft, in: Page.crop, rotation: 270) == "bottom left")
}

@Test func labelNamesSignerPageAndFieldOrPosition() {
    let fields = [SignatureField(pageIndex: 1, bounds: CGRect(x: 0, y: 0, width: 200, height: 60), name: "Buyer")]
    let inField = CGRect(x: 10, y: 10, width: 100, height: 30)
    #expect(
        StampAccessibility.label(
            signerName: "Jane Doe",
            pageIndex: 1,
            bounds: inField,
            cropBox: Page.crop,
            fields: fields
        )
            == "Signature by Jane Doe, page 2, in field Buyer"
    )
    #expect(
        StampAccessibility.label(
            signerName: "Jane Doe",
            pageIndex: 0,
            bounds: inField,
            cropBox: Page.crop,
            fields: fields
        )
            == "Signature by Jane Doe, page 1, at bottom left"
    )
    let unnamed = [SignatureField(pageIndex: 0, bounds: CGRect(x: 0, y: 0, width: 200, height: 60))]
    #expect(
        StampAccessibility.location(of: inField, pageIndex: 0, cropBox: Page.crop, fields: unnamed)
            == "in a signature field"
    )
    #expect(
        StampAccessibility.placedAnnouncement(pageIndex: 1, location: "in field Buyer")
            == "Signature placed on page 2, in field Buyer"
    )
    #expect(StampAccessibility.movedAnnouncement(pageIndex: 0, location: "at center") == "Moved, page 1, at center")
}

@MainActor
@Test func overlayExposesEachStampToVoiceOverWithRemoveAndMoveActions() throws {
    let delegate = RecordingOverlayDelegate()
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(origin: .zero, size: Page.crop.size)
    overlay.delegate = delegate
    var first = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 10, y: 10, width: 60, height: 20),
        image: blackPixel()
    )
    first.accessibilityLabel = "Signature by A, page 1, at bottom left"
    var second = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 200, y: 250, width: 60, height: 20),
        image: blackPixel()
    )
    second.accessibilityLabel = "Signature by A, page 1, at top right"
    overlay.content = PageOverlayView.Content(cropBox: Page.crop, stamps: [first, second])

    let children = try #require(overlay.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(children.map { $0.accessibilityLabel() } == [first.accessibilityLabel, second.accessibilityLabel])
    #expect(children.allSatisfy { $0.accessibilityRole() == .button })
    // Elements are reused, so VoiceOver keeps its place when the content refreshes.
    let again = try #require(overlay.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(again[0] === children[0])

    let actions = children[1].accessibilityCustomActions() ?? []
    #expect(actions.map(\.name) == ["Remove Signature from Page", "Move"])
    _ = actions[0].handler?()
    #expect(delegate.deleted == [second.id])
    _ = actions[1].handler?()
    #expect(delegate.moveRequests == [second.id])
    #expect(children[0].accessibilityPerformPress())
    #expect(delegate.selected == [first.id])
}

@Test func nudgeDistanceFollowsModifiers() {
    #expect(PlacementGeometry.nudgeDistance(shift: false, option: false) == 1)
    #expect(PlacementGeometry.nudgeDistance(shift: true, option: false) == 10)
    #expect(PlacementGeometry.nudgeDistance(shift: false, option: true) == 50)
    #expect(PlacementGeometry.nudgeDistance(shift: true, option: true) == nil)
}

@Test func keyboardResizeKeepsAspectAndBottomLeftCorner() {
    let rect = CGRect(x: 20, y: 30, width: 100, height: 40)
    let page = CGRect(x: 0, y: 0, width: 300, height: 300)
    let grown = PlacementGeometry.scaled(rect, byWidth: 10, within: page)
    #expect(grown.origin == rect.origin)
    #expect(abs(grown.width - 110) < 0.001 && abs(grown.height - 44) < 0.001)

    let shrunk = PlacementGeometry.scaled(rect, byWidth: -500, within: page)
    #expect(abs(shrunk.width - PlacementGeometry.minimumWidth) < 0.001)

    let capped = PlacementGeometry.scaled(rect, byWidth: 1000, within: page)
    #expect(capped.maxX <= page.maxX + 0.001 && capped.maxY <= page.maxY + 0.001)
}

@Test func nextAndPreviousSignatureFollowReadingOrderAndWrap() {
    func placement(_ page: Int, x: CGFloat, y: CGFloat) -> PDFViewerDocument.SignaturePlacement {
        PDFViewerDocument.SignaturePlacement(
            pageIndex: page,
            bounds: CGRect(x: x, y: y, width: 10, height: 10),
            signaturePNGData: Data([1]),
            signerName: "A"
        )
    }
    let lowerOnPage0 = placement(0, x: 0, y: 10)
    let page1 = placement(1, x: 0, y: 500)
    let upperOnPage0 = placement(0, x: 0, y: 500)
    let placements = [lowerOnPage0, page1, upperOnPage0]

    #expect(SigningFlowLogic.adjacentPlacement(after: nil, in: placements, forward: true) == upperOnPage0.id)
    #expect(SigningFlowLogic.adjacentPlacement(after: upperOnPage0.id, in: placements, forward: true) == lowerOnPage0
        .id)
    #expect(SigningFlowLogic.adjacentPlacement(after: page1.id, in: placements, forward: true) == upperOnPage0.id)
    #expect(SigningFlowLogic.adjacentPlacement(after: nil, in: placements, forward: false) == page1.id)
    #expect(SigningFlowLogic.adjacentPlacement(after: upperOnPage0.id, in: placements, forward: false) == page1.id)
    #expect(SigningFlowLogic.adjacentPlacement(after: nil, in: [], forward: true) == nil)
}

@MainActor
@Test func optionArrowsReachTheStampBeforeTheGoMenu() throws {
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    let window = NSWindow(contentRect: pdfView.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = pdfView
    window.makeFirstResponder(pdfView)
    var handled: [NSEvent] = []
    pdfView.keyHandler = { event in
        handled.append(event)
        return true
    }
    let downArrow = try #require(UnicodeScalar(NSDownArrowFunctionKey))
    let optionDown = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.option, .numericPad, .function],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: String(downArrow),
        charactersIgnoringModifiers: String(downArrow),
        isARepeat: false,
        keyCode: 125
    ))

    pdfView.hasSelectedStamp = { false }
    #expect(!pdfView.performKeyEquivalent(with: optionDown))
    pdfView.hasSelectedStamp = { true }
    #expect(pdfView.performKeyEquivalent(with: optionDown))
    #expect(handled.count == 1)
}
