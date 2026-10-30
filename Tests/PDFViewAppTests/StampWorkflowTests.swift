import AppKit
@preconcurrency import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

private enum Page {
    static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)
}

// MARK: Stamp sizes

@Test func eachStampKindHasItsOwnDefaultWidth() {
    #expect(StampKind.signature.defaultWidth == 180)
    #expect(StampKind.initials.defaultWidth == 60)
    #expect(StampKind.date.defaultWidth == 110)
}

@MainActor
@Test func stampSizesRememberTheLastWidthPerKindForTheSession() {
    let sizes = StampSizeMemory()
    #expect(sizes.width(for: .initials) == 60)

    sizes.remember(width: 90, for: .initials)
    #expect(sizes.width(for: .initials) == 90)
    #expect(sizes.width(for: .signature) == 180)
    #expect(sizes.width(for: .date) == 110)

    // A width below the resize floor is never remembered as the next default.
    sizes.remember(width: 3, for: .date)
    #expect(sizes.width(for: .date) == PlacementGeometry.minimumWidth)
}

@Test func defaultRectUsesTheRequestedWidth() {
    let rect = PlacementGeometry.defaultRect(
        centeredAt: CGPoint(x: 300, y: 400),
        imageSize: CGSize(width: 200, height: 100),
        pageBounds: Page.letter,
        width: 60
    )
    #expect(rect.width == 60)
    #expect(rect.height == 30)
    #expect(rect.midX == 300)
    #expect(rect.midY == 400)
}

@MainActor
@Test func clickPlacementUsesTheActiveKindsWidth() throws {
    let document = try #require(PDFDocument(data: makeBlankPDF(pages: 1)))
    var placed: [CGRect] = []
    var representable = makeRepresentable(document: document)
    representable.signingMode = .freePlacement
    representable.stampPNGData = try makeStampPNG(width: 120, height: 40)
    representable.stampWidth = 60
    representable.onPlaceSignature = { _, bounds in placed.append(bounds) }
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
    coordinator.attach(to: pdfView)
    pdfView.document = document

    let overlay = PageOverlayView(page: document.page(at: 0))
    coordinator.overlay(overlay, didClickToSignAt: CGPoint(x: 200, y: 200))

    #expect(placed.map(\.width) == [60])
    #expect(placed.first?.height == 20)
}

// MARK: Fixtures

func makeBlankPDF(pages: Int, size: CGSize = CGSize(width: 612, height: 792)) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    let document = PDFDocument()
    for index in 0 ..< pages {
        try document.insert(#require(PDFPage(image: image)), at: index)
    }
    return try #require(document.dataRepresentation())
}

func makeStampPNG(width: Int, height: Int) throws -> Data {
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    return try #require(rep.representation(using: .png, properties: [:]))
}

// MARK: Kind-aware wording

@Test func editNamesSayWhichKindOfStampChanged() {
    #expect(StampKind.signature.actionName(.add) == "Add Signature")
    #expect(StampKind.initials.actionName(.move) == "Move Initials")
    #expect(StampKind.date.actionName(.resize) == "Resize Date")
    #expect(StampKind.initials.actionName(.remove) == "Remove Initials from Page")
}

@MainActor
@Test func undoNamesFollowThePlacementsKind() {
    var document = PDFViewerDocument()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = SignaturePlacementEditor()
    editor.document = Binding(get: { document }, set: { document = $0 })
    editor.undoManager = undoManager
    let initials = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 10, y: 10, width: 60, height: 20),
        signaturePNGData: Data([1]),
        signerName: "Tester",
        kind: .initials
    )

    undoManager.beginUndoGrouping()
    editor.add(initials)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName == "Add Initials")

    undoManager.beginUndoGrouping()
    editor.delete(id: initials.id)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName == "Remove Initials from Page")
}

@MainActor
@Test func contextMenuAndVoiceOverActionsNameTheStampKind() throws {
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
    let stamp = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: blackPixel(),
        kind: .date
    )
    overlay.content = PageOverlayView.Content(cropBox: overlay.frame, stamps: [stamp])

    let menu = try #require(overlay.menu(for: rightClick(at: CGPoint(x: 120, y: 110))))
    #expect(menu.items.map(\.title) == ["Remove Date from Page"])

    let element = try #require(overlay.accessibilityChildren()?.first as? NSAccessibilityElement)
    #expect(element.accessibilityCustomActions()?.map(\.name) == ["Remove Date from Page", "Move"])
}

@Test func moveInstructionsNameTheStampKind() {
    #expect(StampAccessibility.moveInstructions(for: .initials).hasPrefix("Use the arrow keys to move the initials"))
    #expect(StampAccessibility.moveInstructions(for: .signature).contains("the signature"))
}
