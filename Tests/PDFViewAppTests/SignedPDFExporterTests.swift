import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct SignedPDFExporterTests {
    @Test
    func preservesMixedPageSizes() throws {
        let boxes = [
            CGRect(x: 0, y: 0, width: 400, height: 600),
            CGRect(x: 0, y: 0, width: 595, height: 842),
            CGRect(x: 0, y: 0, width: 612, height: 792),
        ]
        let source = try ExportFixture.document(mediaBoxes: boxes)
        let model = try ExportFixture.model(source)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            #expect(output.pageCount == boxes.count)
            for (index, box) in boxes.enumerated() {
                #expect(output.page(at: index)?.bounds(for: .mediaBox) == box)
                #expect(output.page(at: index)?.bounds(for: .cropBox) == box)
            }
        }
    }

    @Test(arguments: [0, 90, 180, 270])
    func preservesRotationAndPageSpaceStamps(rotation: Int) throws {
        let source = try ExportFixture.document()
        let page = try #require(source.page(at: 0))
        page.rotation = rotation
        let sourceBounds = try ExportFixture.colorBounds(on: page, red: false)
        #expect(sourceBounds == ExportFixture.marker)
        var model = try ExportFixture.model(source)
        model.signaturePlacements[0].bounds = ExportFixture.marker.offsetBy(dx: 80, dy: 40)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let result = try #require(output.page(at: 0))
            #expect(result.rotation == rotation)
            #expect(try ExportFixture.colorBounds(on: result, red: true) == sourceBounds?.offsetBy(dx: 80, dy: 40))
            #expect(try ExportFixture.colorBounds(on: result, red: false) == sourceBounds)
            #expect(page.rotation == rotation)
        }
    }

    @Test(arguments: [0, 90, 180, 270], [CGPoint(x: 20, y: 30), CGPoint(x: -20, y: -30)])
    func preservesOffsetCropAndMediaOrigin(rotation: Int, origin: CGPoint) throws {
        let media = CGRect(origin: origin, size: CGSize(width: 400, height: 600))
        let crop = CGRect(x: 50, y: 70, width: 300, height: 400)
        let source = try ExportFixture.document(mediaBoxes: [media])
        let page = try #require(source.page(at: 0))
        page.setBounds(crop, for: .cropBox)
        page.rotation = rotation
        var model = try ExportFixture.model(source)
        model.signaturePlacements[0].bounds = ExportFixture.marker.offsetBy(dx: 80, dy: 40)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let result = try #require(output.page(at: 0))
            #expect(result.bounds(for: .mediaBox) == media)
            #expect(result.bounds(for: .cropBox) == crop)
            #expect(result.rotation == rotation)
            #expect(try ExportFixture.colorBounds(on: result, red: true) == ExportFixture.marker.offsetBy(
                dx: 80,
                dy: 40
            ))
            #expect(try ExportFixture.colorBounds(on: result, red: false) == ExportFixture.marker)
            #expect(page.rotation == rotation)
            #expect(page.bounds(for: .cropBox) == crop)
        }
    }

    @Test(arguments: [false, true])
    func flattensLiveFormValues(signed: Bool) throws {
        let source = try ExportFixture.document()
        let page = try #require(source.page(at: 0))
        let field = ExportFixture.textField(on: page)
        let baseline = try #require(source.dataRepresentation())
        field.widgetStringValue = "Edited contact value"
        let model = try ExportFixture.model(source, baseline: baseline, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            #expect(output.string?.contains("Edited contact value") == true)
            #expect(output.string?.contains("Original page content") == true)
            #expect(output.page(at: 0)?.annotations.isEmpty == true)
            #expect(page.annotations.contains(field))
            #expect(field.widgetStringValue == "Edited contact value")
        }
    }

    @Test(arguments: [false, true])
    func exportsUnlockedEncryptedContent(signed: Bool) throws {
        try ExportFixture.withDirectory { directory in
            let source = try ExportFixture.document()
            let encryptedURL = directory.appendingPathComponent("encrypted.pdf")
            #expect(source.write(to: encryptedURL, withOptions: [
                .userPasswordOption: "test-user", .ownerPasswordOption: "test-owner",
            ]))
            let baseline = try Data(contentsOf: encryptedURL)
            let unlocked = try #require(PDFDocument(data: baseline))
            #expect(unlocked.isLocked)
            #expect(unlocked.unlock(withPassword: "test-user"))
            let model = try ExportFixture.model(unlocked, baseline: baseline, signed: signed)
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            #expect(!output.isLocked)
            #expect(output.string?.contains("Original page content") == true)
            if !signed {
                let page = try #require(output.page(at: 0))
                #expect(try ExportFixture.colorBounds(on: page, red: false) == ExportFixture.marker)
            }
        }
    }

    @Test
    func rejectsUndecodableImageWithoutReplacingDestination() throws {
        let source = try ExportFixture.document()
        var model = try ExportFixture.model(source, signed: false)
        model.addSignaturePlacement(.init(
            pageIndex: 0, bounds: ExportFixture.marker, signaturePNGData: Data("invalid".utf8), signerName: "Tester"
        ))
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            let original = Data("existing destination".utf8)
            try original.write(to: url)
            #expect(throws: PDFViewerDocument.ExportError.cannotDecodeSignature(id: model.signaturePlacements[0].id)) {
                try model.writeSignedCopy(to: url)
            }
            #expect(try Data(contentsOf: url) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["signed.pdf"])
        }
    }

    @Test(arguments: [false, true])
    func failedWriteLeavesDestinationUntouched(signed: Bool) throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            let original = Data("existing destination".utf8)
            try original.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
            #expect(throws: PDFViewerDocument.ExportError.self) { try model.writeSignedCopy(to: url) }
            #expect(try Data(contentsOf: url) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["signed.pdf"])
        }
    }

    @Test(arguments: [false, true])
    func rejectsLockedDocument(signed: Bool) throws {
        try ExportFixture.withDirectory { directory in
            let source = try ExportFixture.document()
            let encryptedURL = directory.appendingPathComponent("encrypted.pdf")
            #expect(source.write(
                to: encryptedURL,
                withOptions: [.userPasswordOption: "test-user", .ownerPasswordOption: "test-owner"]
            ))
            let locked = try #require(PDFDocument(url: encryptedURL))
            #expect(locked.isLocked)
            let model = try ExportFixture.model(locked, signed: signed)
            let url = directory.appendingPathComponent("signed.pdf")
            #expect(throws: PDFViewerDocument.ExportError.documentLocked) { try model.writeSignedCopy(to: url) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
