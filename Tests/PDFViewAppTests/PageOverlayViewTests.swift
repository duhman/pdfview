import AppKit
@preconcurrency import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

private enum Fixture {
    static let cropBox = CGRect(x: 50, y: 70, width: 300, height: 400)
}

private func solidImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

@MainActor
private func makeOverlay(_ content: PageOverlayView.Content) -> PageOverlayView {
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(origin: .zero, size: Fixture.cropBox.size)
    overlay.content = content
    return overlay
}

/// Renders the overlay and returns the colour at a page-space point.
@MainActor
private func color(of overlay: PageOverlayView, atPagePoint point: CGPoint) throws -> NSColor {
    let rep = try #require(overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds))
    overlay.cacheDisplay(in: overlay.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / overlay.bounds.width
    let local = CGPoint(x: point.x - Fixture.cropBox.minX, y: point.y - Fixture.cropBox.minY)
    let pixelY = Int((overlay.bounds.height - local.y) * scale)
    let color = try #require(rep.colorAt(x: Int(local.x * scale), y: pixelY))
    return try #require(color.usingColorSpace(.deviceRGB))
}

@MainActor
@Test func stampIsDrawnAtItsPageSpaceBoundsOnAnOffsetCropBox() throws {
    let stamp = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: solidImage(width: 60, height: 20)
    )
    let overlay = makeOverlay(PageOverlayView.Content(cropBox: Fixture.cropBox, stamps: [stamp]))

    let inside = try color(of: overlay, atPagePoint: CGPoint(x: 130, y: 110))
    #expect(inside.alphaComponent > 0.9 && inside.redComponent < 0.1)

    let outside = try color(of: overlay, atPagePoint: CGPoint(x: 200, y: 200))
    #expect(outside.alphaComponent < 0.1)
}

@MainActor
@Test func selectedStampGetsCornerHandles() throws {
    let id = UUID()
    let stamp = try PageOverlayView.Stamp(
        id: id,
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: solidImage(width: 60, height: 20)
    )
    let unselected = makeOverlay(PageOverlayView.Content(cropBox: Fixture.cropBox, stamps: [stamp]))
    let selected = makeOverlay(PageOverlayView.Content(cropBox: Fixture.cropBox, stamps: [stamp], selectedID: id))

    // Just outside the top-right corner: only the handle covers it.
    let probe = CGPoint(x: 162.5, y: 122.5)
    #expect(try color(of: unselected, atPagePoint: probe).alphaComponent < 0.1)
    #expect(try color(of: selected, atPagePoint: probe).alphaComponent > 0.9)
}

@MainActor
@Test func signatureFieldsAreOutlinedWhileSigning() throws {
    let field = CGRect(x: 100, y: 200, width: 220, height: 50)
    let overlay = makeOverlay(PageOverlayView.Content(
        cropBox: Fixture.cropBox,
        signingMode: .fieldPlacement,
        fields: [field]
    ))

    let border = try color(of: overlay, atPagePoint: CGPoint(x: 101, y: 225))
    #expect(border.alphaComponent > 0.9)

    let fill = try color(of: overlay, atPagePoint: CGPoint(x: 200, y: 225))
    #expect(fill.alphaComponent > 0.05 && fill.alphaComponent < 0.2)
}

@MainActor
@Test func idleOverlayOnlyClaimsClicksOnStamps() throws {
    let stamp = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: solidImage(width: 60, height: 20)
    )
    let container = NSView(frame: CGRect(origin: .zero, size: Fixture.cropBox.size))
    let overlay = makeOverlay(PageOverlayView.Content(cropBox: Fixture.cropBox, stamps: [stamp]))
    container.addSubview(overlay)

    // Local point = page point minus the crop origin.
    #expect(overlay.hitTest(CGPoint(x: 80, y: 40)) === overlay)
    #expect(overlay.hitTest(CGPoint(x: 200, y: 200)) == nil)

    overlay.content.signingMode = .freePlacement
    #expect(overlay.hitTest(CGPoint(x: 200, y: 200)) === overlay)
}

@MainActor
@Test func pdfViewHostsStampsInPageOverlays() throws {
    let document = try #require(PDFDocument(data: makeTwoPagePDF()))
    let placement = try PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 40, y: 40, width: 120, height: 40),
        signaturePNGData: makeSignaturePNG(),
        signerName: "Tester"
    )
    var zoom = ZoomState.fit
    let representable = PDFKitView(
        document: document,
        signaturePlacements: [placement],
        zoom: Binding(get: { zoom }, set: { zoom = $0 }),
        signingMode: .idle,
        signatureProfile: nil,
        viewer: PDFViewerProxy(),
        onWindow: { _ in },
        onPlaceSignature: { _, _ in },
        onUpdatePlacementBounds: { _, _, _ in },
        onDeletePlacement: { _ in },
        onExitSigning: {},
        onDocumentStateChange: { _ in }
    )
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
    coordinator.attach(to: pdfView)
    let window = NSWindow(contentRect: pdfView.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = pdfView
    pdfView.document = document
    coordinator.documentDidChange(document)
    pdfView.layoutDocumentView()
    window.displayIfNeeded()

    let overlays = pdfView.documentView.map { allSubviews(of: $0) }?.compactMap { $0 as? PageOverlayView } ?? []
    let firstPage = overlays.first { $0.page === document.page(at: 0) }
    #expect(firstPage?.content.stamps.map(\.id) == [placement.id])
    // Fit stays fit through PDFKit's own auto-scaling.
    #expect(zoom == .fit)
}

@MainActor
private func allSubviews(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allSubviews)
}

private func makeTwoPagePDF() throws -> Data {
    let image = NSImage(size: NSSize(width: 400, height: 600))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 600).fill()
    image.unlockFocus()

    let document = PDFDocument()
    for index in 0 ..< 2 {
        try document.insert(#require(PDFPage(image: image)), at: index)
    }
    return try #require(document.dataRepresentation())
}

private func makeSignaturePNG() throws -> Data {
    let rep = try NSBitmapImageRep(cgImage: solidImage(width: 120, height: 40))
    return try #require(rep.representation(using: .png, properties: [:]))
}
