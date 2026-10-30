import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct ExportSafetyTests {
    @Test(arguments: [false, true])
    func asyncExportFreezesFormValuesBeforeFirstYield(encrypted: Bool) async throws {
        var source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 8
        ))
        if encrypted {
            let bytes = try #require(source.dataRepresentation(options: [
                PDFDocumentWriteOption.userPasswordOption: "reader",
                PDFDocumentWriteOption.ownerPasswordOption: "owner",
            ]))
            source = try #require(PDFDocument(data: bytes))
            #expect(source.unlock(withPassword: "reader"))
        }
        let fields = try (0 ..< source.pageCount).map {
            try ExportFixture.textField(on: #require(source.page(at: $0)))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
            if progress.completedPages == 1 {
                fields.forEach { $0.widgetStringValue = "Changed during save" }
            }
        }
        let output = try #require(PDFDocument(url: url))
        for index in 0 ..< output.pageCount {
            #expect(output.page(at: index)?.string?.contains("Baseline value") == true)
            #expect(output.page(at: index)?.string?.contains("Changed during save") == false)
        }
        #expect(fields.allSatisfy { $0.widgetStringValue == "Changed during save" })
    }

    @Test func rejectsOriginalByPathSymlinkAndHardLink() throws {
        try ExportFixture.withDirectory { directory in
            let original = directory.appendingPathComponent("original.pdf")
            #expect(try ExportFixture.document().write(to: original))
            let symlink = directory.appendingPathComponent("symlink.pdf")
            let hardlink = directory.appendingPathComponent("hardlink.pdf")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
            try FileManager.default.linkItem(at: original, to: hardlink)
            let baseline = try Data(contentsOf: original)
            for url in [original, symlink, hardlink] {
                #expect(throws: PDFViewerDocument.ExportError.cannotReplaceOriginal) {
                    try SignedCopyOperation.validateDestination(url, originalURL: original)
                }
            }
            try SignedCopyOperation.validateDestination(
                directory.appendingPathComponent("copy.pdf"),
                originalURL: original
            )
            #expect(try Data(contentsOf: original) == baseline)
        }
    }

    @Test func finalizeYieldsBetweenEveryStage() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: -20, y: -30, width: 400, height: 600), count: 300
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var heartbeats: Set<ExportProgress.Stage> = []
        try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
            if progress.stage != .rendering {
                Task { @MainActor in heartbeats.insert(progress.stage) }
            }
        }
        #expect(heartbeats == [.writing, .restoringGeometry, .validating])
        #expect(PDFDocument(url: url)?.pageCount == 300)
    }

    @Test func unsupportedGeometryFailsWithRecoveryAdvice() throws {
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("unsupported.pdf")
            let fixture = Data("%PDF-1.7\nstartxref\n0\n%%EOF\n".utf8)
            try fixture.write(to: url)
            let geometry = PDFExportPageGeometry(
                media: CGRect(x: -20, y: -30, width: 400, height: 600),
                crop: CGRect(x: -20, y: -30, width: 400, height: 600)
            )
            #expect(throws: PDFViewerDocument.ExportError.cannotPreservePageGeometry) {
                try PDFExportGeometry.restore(at: url, pages: [geometry])
            }
            #expect(try Data(contentsOf: url) == fixture)
            let message = try #require(PDFViewerDocument.ExportError.cannotPreservePageGeometry.errorDescription)
            #expect(message.contains("destination was not changed"))
            #expect(message.contains("Print"))
        }
    }

    @Test func lazySignatureScanYieldsAndCancels() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 50
        ))
        for index in [0, 49] {
            let field = PDFAnnotation(bounds: ExportFixture.marker, forType: .widget, withProperties: nil)
            field.widgetFieldType = .signature
            try #require(source.page(at: index)).addAnnotation(field)
        }
        var batches = 0
        let fields = try await ReaderController.scanSignatureFields(in: source, batchSize: 5) { _ in batches += 1 }
        #expect(fields.map(\.pageIndex) == [0, 49])
        #expect(batches == 10)
        let task = Task { @MainActor in
            try await ReaderController.scanSignatureFields(in: source, batchSize: 5) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func operationRejectsTheOpenDocumentURL() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ExportFixture.document().write(to: url))
        let baseline = try Data(contentsOf: url)
        let source = try #require(PDFDocument(url: url))
        let operation = SignedCopyOperation()
        #expect(operation.reserve())
        var result: Result<Void, Error>?
        operation.write(source, placements: [], to: url) { result = $0 }
        for _ in 0 ..< 100 where operation.isBusy {
            await Task.yield()
        }
        if case let .failure(error) = result {
            #expect(error as? PDFViewerDocument.ExportError == .cannotReplaceOriginal)
        } else {
            Issue.record("Expected an original-file rejection")
        }
        #expect(try Data(contentsOf: url) == baseline)
    }

    @Test(arguments: [ExportProgress.Stage.writing, .restoringGeometry, .validating])
    func finalizeCancellationKeepsDestination(stage: ExportProgress.Stage) async throws {
        let source = try ExportFixture.document()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let baseline = Data("existing destination".utf8)
        try baseline.write(to: url)
        let task = Task { @MainActor in
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
                if progress.stage == stage {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: url) == baseline)
    }
}
