import AppKit
@preconcurrency import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

@MainActor
final class StateRecorder {
    var states: [PDFKitView.DocumentState] = []
    var formValues: [[FormFieldValue]] = []
}

@MainActor
func makeRepresentable(
    document: PDFDocument? = nil,
    placements: [PDFViewerDocument.SignaturePlacement] = [],
    recorder: StateRecorder = StateRecorder()
) -> PDFKitView {
    PDFKitView(
        document: document,
        signaturePlacements: placements,
        zoom: .constant(.fit),
        signingMode: .idle,
        stampPNGData: nil,
        viewer: PDFViewerProxy(),
        reader: ReaderController(),
        fileURL: nil,
        onEscape: {},
        onStopSigning: {},
        isExporting: false,
        onWindow: { _ in },
        onPlaceSignature: { _, _ in },
        onUpdatePlacementBounds: { _, _, _ in },
        onDeletePlacement: { _ in },
        onDocumentStateChange: { recorder.states.append($0) },
        onFormValuesChange: { recorder.formValues.append($0) }
    )
}

@MainActor
@Test func overlaysFollowPlacementsAndSelection() throws {
    let document = try ExportFixture.document()
    let model = try ExportFixture.model(document)
    let placement = try #require(model.signaturePlacements.first)
    var representable = makeRepresentable(document: document)
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    pdfView.document = document
    let page = try #require(document.page(at: 0))
    let overlay = try #require(coordinator.pdfView(pdfView, overlayViewFor: page) as? PageOverlayView)

    overlay.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
    coordinator.updateOverlaysIfNeeded()
    coordinator.updateOverlaysIfNeeded()
    #expect(overlay.content.stamps.isEmpty)

    representable.signaturePlacements = [placement]
    coordinator.parent = representable
    coordinator.updateOverlaysIfNeeded()
    #expect(overlay.content.stamps.map(\.id) == [placement.id])
    #expect(overlay.content.stamps.first?.bounds == placement.bounds)

    coordinator.selectedPlacementID = placement.id
    #expect(overlay.content.selectedID == placement.id)
    coordinator.selectedPlacementID = placement.id
    #expect(overlay.content.selectedID == placement.id)
    #expect(overlay.content.stamps.map(\.id) == [placement.id])

    representable.signaturePlacements = []
    coordinator.parent = representable
    coordinator.updateOverlaysIfNeeded()
    #expect(overlay.content.stamps.isEmpty)
}

@MainActor
@Test func documentStateReportsLockStateFirstAndFieldsAfterTheScan() async throws {
    let document = try makeSignableForm()
    let recorder = StateRecorder()
    let coordinator = makeRepresentable(document: document, recorder: recorder).makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    pdfView.document = document
    coordinator.documentDidChange(document)

    for _ in 0 ..< 200 where recorder.states.count < 2 {
        await Task.yield()
    }

    #expect(recorder.states.first == PDFKitView.DocumentState(signatureFields: [], isLocked: false))
    let scanned = try #require(recorder.states.last)
    #expect(scanned.signatureFields.map(\.name) == ["ClientSignature"])
    #expect(scanned.formValues?.map(\.fieldName) == ["Name"])

    // A form edit is reported once, and only when the value really changed.
    let name = try #require(coordinator.formScan?.widgets.first)
    name.widgetStringValue = "Jane"
    coordinator.checkFormValues()
    coordinator.checkFormValues()
    #expect(recorder.formValues.count == 1)
}

/// One page with a text field and a /Sig field, round-tripped through bytes.
@MainActor
func makeSignableForm() throws -> PDFDocument {
    let image = NSImage(size: NSSize(width: 400, height: 600))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 600).fill()
    image.unlockFocus()
    let document = PDFDocument()
    try document.insert(#require(PDFPage(image: image)), at: 0)

    let name = PDFAnnotation(
        bounds: CGRect(x: 20, y: 20, width: 200, height: 30),
        forType: .widget,
        withProperties: nil
    )
    name.widgetFieldType = .text
    name.fieldName = "Name"
    name.widgetStringValue = ""
    document.page(at: 0)?.addAnnotation(name)

    let signature = PDFAnnotation(
        bounds: CGRect(x: 20, y: 100, width: 220, height: 50),
        forType: .widget,
        withProperties: nil
    )
    signature.widgetFieldType = .signature
    signature.fieldName = "ClientSignature"
    document.page(at: 0)?.addAnnotation(signature)
    let data = try #require(document.dataRepresentation())
    return try #require(PDFDocument(data: data))
}
