import Testing
import AppKit
@preconcurrency import Quartz
@testable import PDFViewApp

@Test func placementAddAndRemoveRoundTrip() {
    var document = PDFViewerDocument()
    let placement = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 20, y: 30, width: 120, height: 40),
        signaturePNGData: makeSignaturePNGData(),
        signerName: "Tester"
    )

    document.addSignaturePlacement(placement)
    #expect(document.signaturePlacements.count == 1)

    let removed = document.removeSignaturePlacement(id: placement.id)
    #expect(removed == placement)
    #expect(document.signaturePlacements.isEmpty)
}

@Test func signedCopyFailsForNonFileDestination() {
    let pdfData = makeSamplePDFData()
    let pdf = PDFDocument(data: pdfData)
    var document = PDFViewerDocument(pdfDocument: pdf, originalPDFData: pdfData)
    document.addSignaturePlacement(
        PDFViewerDocument.SignaturePlacement(
            pageIndex: 0,
            bounds: CGRect(x: 20, y: 30, width: 120, height: 40),
            signaturePNGData: makeSignaturePNGData(),
            signerName: "Tester"
        )
    )

    do {
        try document.writeSignedCopy(to: URL(string: "https://example.com/out.pdf")!)
        Issue.record("Expected invalidDestinationURL error")
    } catch let error as PDFViewerDocument.ExportError {
        #expect(error == .invalidDestinationURL)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func noPlacementExportUsesBaselineDataVerbatim() throws {
    let baselineData = makeSamplePDFData()
    let pdf = PDFDocument(data: baselineData)
    let document = PDFViewerDocument(pdfDocument: pdf, originalPDFData: baselineData)

    let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pdfview-tests")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    try document.writeSignedCopy(to: outputURL)
    let exportedData = try Data(contentsOf: outputURL)
    #expect(exportedData == baselineData)
}

@Test func signedCopyDoesNotMutateSourceDocumentAnnotations() throws {
    let baselineData = makeSamplePDFData()
    guard let sourceDocument = PDFDocument(data: baselineData) else {
        Issue.record("Could not create PDFDocument from baseline data")
        return
    }

    var document = PDFViewerDocument(pdfDocument: sourceDocument, originalPDFData: baselineData)
    document.addSignaturePlacement(
        PDFViewerDocument.SignaturePlacement(
            pageIndex: 0,
            bounds: CGRect(x: 30, y: 35, width: 120, height: 40),
            signaturePNGData: makeSignaturePNGData(),
            signerName: "Tester"
        )
    )

    let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pdfview-tests")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let annotationCountBefore = sourceDocument.page(at: 0)?.annotations.count ?? 0
    try document.writeSignedCopy(to: outputURL)
    let annotationCountAfter = sourceDocument.page(at: 0)?.annotations.count ?? 0

    #expect(annotationCountBefore == 0)
    #expect(annotationCountAfter == 0)
}

private func makeSamplePDFData() -> Data {
    let image = NSImage(size: NSSize(width: 400, height: 400))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 400)).fill()
    NSColor.black.setStroke()
    let border = NSBezierPath(rect: NSRect(x: 20, y: 20, width: 360, height: 360))
    border.lineWidth = 2
    border.stroke()
    image.unlockFocus()

    let pdf = PDFDocument()
    guard let page = PDFPage(image: image) else {
        Issue.record("Could not create PDF page for test fixture")
        return Data()
    }
    pdf.insert(page, at: 0)
    guard let data = pdf.dataRepresentation() else {
        Issue.record("Could not create PDF data fixture")
        return Data()
    }
    return data
}

private func makeSignaturePNGData() -> Data {
    let image = NSImage(size: NSSize(width: 180, height: 60))
    image.lockFocus()
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 60)).fill()
    NSColor.black.setStroke()
    let stroke = NSBezierPath()
    stroke.move(to: NSPoint(x: 8, y: 15))
    stroke.line(to: NSPoint(x: 90, y: 45))
    stroke.line(to: NSPoint(x: 172, y: 18))
    stroke.lineWidth = 4
    stroke.stroke()
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("Could not create PNG test data")
        return Data()
    }

    return png
}
