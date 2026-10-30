import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct SignedPDFAtomicExportTests {
    @Test(arguments: [false, true])
    func replacesExistingDestinationAfterValidation(signed: Bool) async throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source, signed: signed)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try Data("previous destination".utf8).write(to: url)
            try await model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            #expect(output.pageCount == source.pageCount)
            #expect(output.string?.contains("Original page content") == true)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["signed.pdf"])
        }
    }

    @Test
    func stampsUseGivenBoundsWithoutClamping() async throws {
        let source = try ExportFixture.document()
        var model = try ExportFixture.model(source)
        model.signaturePlacements[0].bounds = CGRect(x: 380, y: 580, width: 80, height: 40)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try await model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let page = try #require(output.page(at: 0))
            #expect(try ExportFixture.colorBounds(on: page, red: true) == CGRect(x: 380, y: 580, width: 20, height: 20))
        }
    }

    @Test
    func rejectsPlacementOnMissingPage() async throws {
        let source = try ExportFixture.document()
        var model = try ExportFixture.model(source)
        try model.addSignaturePlacement(.init(
            pageIndex: 1,
            bounds: ExportFixture.marker,
            signaturePNGData: ExportFixture.signature(),
            signerName: "Tester"
        ))
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            await #expect(throws: PDFViewerDocument.ExportError.invalidPlacementPage(index: 1)) {
                try await model.writeSignedCopy(to: url)
            }
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }

    @Test
    func noPlacementExportUsesLivePageChanges() async throws {
        let source = try ExportFixture.document()
        let additional = try ExportFixture.document()
        try source.insert(#require(additional.page(at: 0)), at: 1)
        let model = try ExportFixture.model(source, signed: false)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try await model.writeSignedCopy(to: url)
            #expect(PDFDocument(url: url)?.pageCount == 2)
        }
    }

    @Test
    func missingDestinationDirectoryFailsWithoutCreatingFiles() async throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("missing/signed.pdf")
            await #expect(throws: PDFViewerDocument.ExportError.self) { try await model.writeSignedCopy(to: url) }
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }
}
