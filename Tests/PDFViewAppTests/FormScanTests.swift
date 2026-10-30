import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
@Test func incrementalScanFindsNamedSignatureFieldsAndEditableWidgets() async throws {
    let document = try makeScanFixture(pageCount: 20)

    let scan = await FormScan.scan(document, pagesPerYield: 3)

    #expect(scan.signatureFields == [
        SignatureField(pageIndex: 17, bounds: CGRect(x: 20, y: 100, width: 220, height: 50), name: "ClientSignature"),
    ])
    #expect(scan.widgets.map(\.fieldName) == ["Name", "Agree"])
}

@MainActor
@Test func cancelledScanStopsBeforeReportingFields() async throws {
    let document = try makeScanFixture(pageCount: 20)
    let task = Task { await FormScan.scan(document, pagesPerYield: 1) }
    task.cancel()
    let scan = await task.value
    #expect(scan.isCancelled)
}

@MainActor
@Test func formValuesDifferAfterTheUserTypesOrTicks() async throws {
    let document = try makeScanFixture(pageCount: 2)
    let scan = await FormScan.scan(document)
    let baseline = scan.values()

    let name = try #require(scan.widgets.first { $0.fieldName == "Name" })
    name.widgetStringValue = "Jane Doe"
    #expect(scan.values() != baseline)

    name.widgetStringValue = ""
    #expect(scan.values() == baseline)

    let agree = try #require(scan.widgets.first { $0.fieldName == "Agree" })
    agree.buttonWidgetState = agree.buttonWidgetState == .onState ? .offState : .onState
    #expect(scan.values() != baseline)
}

@MainActor
@Test func savingAFilledFormWithoutStampsKeepsTheEntry() async throws {
    let document = try makeScanFixture(pageCount: 1)
    let scan = await FormScan.scan(document)
    let name = try #require(scan.widgets.first { $0.fieldName == "Name" })
    name.widgetStringValue = "Jane Doe"

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try SignedPDFExporter.write(document, placements: [], to: url)

    let saved = try #require(PDFDocument(url: url))
    let text = saved.page(at: 0)?.string ?? ""
    let widgetValue = saved.page(at: 0)?.annotations.first { $0.fieldName == "Name" }?.widgetStringValue
    #expect(text.contains("Jane Doe") || widgetValue == "Jane Doe")
}

/// Page 1 has a text field and a checkbox; page 18 (when present) has a /Sig field.
@MainActor
private func makeScanFixture(pageCount: Int) throws -> PDFDocument {
    let image = NSImage(size: NSSize(width: 400, height: 600))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 600).fill()
    image.unlockFocus()

    let document = PDFDocument()
    for index in 0 ..< pageCount {
        try document.insert(#require(PDFPage(image: image)), at: index)
    }

    let name = PDFAnnotation(
        bounds: CGRect(x: 20, y: 20, width: 200, height: 30),
        forType: .widget,
        withProperties: nil
    )
    name.widgetFieldType = .text
    name.fieldName = "Name"
    name.widgetStringValue = ""
    document.page(at: 0)?.addAnnotation(name)

    let agree = PDFAnnotation(
        bounds: CGRect(x: 20, y: 60, width: 20, height: 20),
        forType: .widget,
        withProperties: nil
    )
    agree.widgetFieldType = .button
    agree.widgetControlType = .checkBoxControl
    agree.fieldName = "Agree"
    document.page(at: 0)?.addAnnotation(agree)

    if pageCount > 17 {
        let signature = PDFAnnotation(
            bounds: CGRect(x: 20, y: 100, width: 220, height: 50),
            forType: .widget,
            withProperties: nil
        )
        signature.widgetFieldType = .signature
        signature.fieldName = "ClientSignature"
        document.page(at: 17)?.addAnnotation(signature)
    }

    let data = try #require(document.dataRepresentation())
    return try #require(PDFDocument(data: data))
}
