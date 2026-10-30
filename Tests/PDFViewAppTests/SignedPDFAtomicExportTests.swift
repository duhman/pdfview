import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct SignedPDFAtomicExportTests {
    @Test(arguments: [false, true])
    func replacesExistingDestinationAfterValidation(signed: Bool) throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try Data("previous destination".utf8).write(to: url)
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            #expect(output.pageCount == source.pageCount)
            #expect(output.string?.contains("Original page content") == true)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["signed.pdf"])
        }
    }

    @Test
    func stampsUseGivenBoundsWithoutClamping() throws {
        let source = try ExportFixture.document()
        var model = try ExportFixture.model(source)
        model.signaturePlacements[0].bounds = CGRect(x: 380, y: 580, width: 80, height: 40)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let page = try #require(output.page(at: 0))
            #expect(try ExportFixture.colorBounds(on: page, red: true) == CGRect(x: 380, y: 580, width: 20, height: 20))
        }
    }

    @Test
    func rejectsPlacementOnMissingPage() throws {
        let source = try ExportFixture.document()
        var model = try ExportFixture.model(source)
        try model.addSignaturePlacement(.init(
            pageIndex: 1,
            bounds: ExportFixture.marker,
            signaturePNGData: ExportFixture.signature(),
            signerName: "Tester"
        ))
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            #expect(throws: PDFViewerDocument.ExportError.invalidPlacementPage(index: 1)) {
                try model.writeSignedCopy(to: url)
            }
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }

    @Test
    func noPlacementExportUsesLivePageChanges() throws {
        let source = try ExportFixture.document()
        let baseline = try #require(source.dataRepresentation())
        let additional = try ExportFixture.document()
        try source.insert(#require(additional.page(at: 0)), at: 1)
        let model = try ExportFixture.model(source, baseline: baseline, signed: false)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            #expect(PDFDocument(url: url)?.pageCount == 2)
        }
    }

    @Test
    func missingDestinationDirectoryFailsWithoutCreatingFiles() throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("missing/signed.pdf")
            #expect(throws: PDFViewerDocument.ExportError.self) { try model.writeSignedCopy(to: url) }
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }
}
