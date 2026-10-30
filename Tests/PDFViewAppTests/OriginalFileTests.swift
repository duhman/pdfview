import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

/// The original PDF must never change on disk. macOS autosave writes whatever `fileWrapper`
/// returns over the original, so it has to be the bytes the file was opened with.
@MainActor
struct OriginalFileTests {
    @Test
    func fileWrapperWritesTheOpenedBytesEvenAfterFormEdits() throws {
        let source = try ExportFixture.document()
        let page = try #require(source.page(at: 0))
        let field = ExportFixture.textField(on: page)
        field.fieldName = "ClientName"
        let opened = try #require(source.dataRepresentation())

        let document = try PDFViewerDocument(data: opened)
        let live = try #require(document.pdfDocument?.page(at: 0)?.annotations.first { $0.fieldName == "ClientName" })
        live.widgetStringValue = "Typed after opening"

        let written = try document.persistedData()
        #expect(written == opened)
    }

    @Test
    func unreadableDataIsRejected() {
        #expect(throws: CocoaError.self) {
            try PDFViewerDocument(data: Data("not a pdf".utf8))
        }
    }
}
