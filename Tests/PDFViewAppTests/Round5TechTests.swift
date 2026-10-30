import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct Round5TechTests {
    @Test(arguments: [false, true])
    func removingSavedWorkCanSaveTheCurrentEmptyState(revertForm: Bool) async throws {
        let source = try ExportFixture.document()
        let field = try ExportFixture.textField(on: #require(source.page(at: 0)))
        var model = try ExportFixture.model(source, signed: !revertForm)
        let protection = DocumentProtection(document: source)
        if revertForm {
            field.widgetStringValue = "Edited form"
        }
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            let exported = try await model.writeSignedCopy(to: url)
            model.signaturePlacements = []
            field.widgetStringValue = "Baseline value"
            let values = protection.formBaseline?.values()
            let work = protection.unsavedWork(placements: [], exported: exported, formValues: values)
            #expect(!work.isEmpty)
            #expect(SigningFlowLogic.hasSignedCopyContent(
                placements: [], formValues: values, originalFormValues: protection.initialFormValues, exported: exported
            ))
            let current = try await model.writeSignedCopy(to: url)
            #expect(current.placements.isEmpty)
            #expect(current.formValues == protection.initialFormValues)
            #expect(protection.unsavedWork(placements: [], exported: current, formValues: values).isEmpty)
            let saved = try #require(PDFDocument(url: url))
            let page = try #require(saved.page(at: 0))
            #expect(try ExportFixture.colorBounds(on: page, red: true) == nil)
            #expect(page.string?.contains("Baseline value") == true)
            #expect(page.string?.contains("Edited form") == false)
        }
    }

    @Test(arguments: [0, 90, 180, 270], [CGPoint.zero, CGPoint(x: -20, y: -30)])
    func snapshotFreezesContentAndAppearance(rotation: Int, origin: CGPoint) async throws {
        let source = try ExportFixture.document(mediaBoxes: [
            CGRect(origin: origin, size: CGSize(width: 400, height: 600)),
        ])
        let page = try #require(source.page(at: 0))
        page.rotation = rotation
        let annotation = PDFAnnotation(bounds: ExportFixture.marker, forType: .square, withProperties: nil)
        annotation.interiorColor = .red
        annotation.color = .red
        annotation.shouldPrint = true
        page.addAnnotation(annotation)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("frozen.pdf")
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
                if progress.stage == .rendering, progress.completedPages == 0 {
                    annotation.interiorColor = .blue
                    annotation.bounds = annotation.bounds.offsetBy(dx: 100, dy: 100)
                    page.removeAnnotation(annotation)
                    source.removePage(at: 0)
                }
            }
            let saved = try #require(PDFDocument(url: url))
            let output = try #require(saved.page(at: 0))
            #expect(output.string?.contains("Original page content") == true)
            let red = try #require(try ExportFixture.colorBounds(on: output, red: true))
            #expect(red.midX == ExportFixture.marker.midX)
            #expect(red.midY == ExportFixture.marker.midY)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func annotationVisibilityMatchesPDFKit(shouldDisplay: Bool, shouldPrint: Bool) async throws {
        let source = try ExportFixture.document()
        let page = try #require(source.page(at: 0))
        let annotation = PDFAnnotation(bounds: ExportFixture.marker, forType: .square, withProperties: nil)
        annotation.interiorColor = .red
        annotation.color = .red
        annotation.shouldDisplay = shouldDisplay
        annotation.shouldPrint = shouldPrint
        page.addAnnotation(annotation)
        try await ExportFixture.withDirectoryAsync { directory in
            let referenceURL = directory.appendingPathComponent("reference.pdf")
            let context = try #require(CGContext(referenceURL as CFURL, mediaBox: nil, nil))
            var media = page.bounds(for: .mediaBox)
            context.beginPDFPage([
                kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size),
            ] as CFDictionary)
            page.displaysAnnotations = true
            page.draw(with: .mediaBox, to: context)
            context.endPDFPage()
            context.closePDF()
            let reference = try #require(PDFDocument(url: referenceURL)?.page(at: 0))
            let expected = try ExportFixture.colorBounds(on: reference, red: true)
            let url = directory.appendingPathComponent("exported.pdf")
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { _ in }
            let output = try #require(PDFDocument(url: url)?.page(at: 0))
            #expect(try ExportFixture.colorBounds(on: output, red: true) == expected)
        }
    }

    @Test func unlockBeforeScanHasNoEditedDotOrCloseReview() throws {
        let source = try ExportFixture.document()
        _ = try ExportFixture.textField(on: #require(source.page(at: 0)))
        let bytes = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "reader", PDFDocumentWriteOption.ownerPasswordOption: "owner",
        ]))
        let locked = try #require(PDFDocument(data: bytes))
        let protection = DocumentProtection(document: locked)
        #expect(protection.unlock(withPassword: "reader"))
        // The reader scan has not reported any values yet; use the baseline captured by unlock.
        let work = protection.unsavedWork(placements: [], exported: nil, formValues: nil)
        #expect(work.isEmpty)
        let closeGuard = DocumentCloseGuard()
        closeGuard.unsavedWork = { protection.unsavedWork(placements: [], exported: nil, formValues: nil) }
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        closeGuard.install(on: window)
        closeGuard.isEdited = !work.isEmpty
        #expect(!window.isDocumentEdited)
        #expect(!closeGuard.hasUnsavedWork)
        if work.isEmpty {
            #expect(closeGuard.windowShouldClose(window))
        }
        let field = try #require(protection.formBaseline?.widgets.first)
        field.widgetStringValue = "Edited before scan"
        #expect(closeGuard.hasUnsavedWork)
        #expect(SigningFlowLogic.hasSignedCopyContent(
            placements: [],
            formValues: protection.formBaseline?.values(),
            originalFormValues: protection.initialFormValues
        ))
    }

    @Test(arguments: [false, true])
    func protectedOffsetRecoveryRespectsPrintPermission(allowsPrinting: Bool) async throws {
        let source = try ExportFixture.document(mediaBoxes: [CGRect(x: -20, y: -30, width: 400, height: 600)])
        let bytes = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "reader",
            PDFDocumentWriteOption.ownerPasswordOption: "owner",
            PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: allowsPrinting ? 255 : 0),
        ]))
        let locked = try #require(PDFDocument(data: bytes))
        #expect(locked.unlock(withPassword: "reader"))
        #expect(locked.allowsPrinting == allowsPrinting)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("copy.pdf")
            let existing = Data("unchanged".utf8)
            try existing.write(to: url)
            do {
                try await SignedPDFExporter.writeAsync(locked, placements: [], to: url, password: "reader") { _ in }
                Issue.record("Expected protected offset geometry rejection")
            } catch {
                let message = error.localizedDescription
                #expect(message.contains("turn off Keep password protection"))
                #expect(message.contains("Print > Save as PDF") == allowsPrinting)
                #expect(message.contains("destination was not changed"))
            }
            #expect(try Data(contentsOf: url) == existing)
        }
    }
}
