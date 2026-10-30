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
