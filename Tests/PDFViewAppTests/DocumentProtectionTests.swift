import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct DocumentProtectionTests {
    private let phrase = UUID().uuidString

    @Test func unlockKeepsOnlySuccessfulPassword() throws {
        let protection = try DocumentProtection(document: encryptedDocument())
        #expect(protection.isEncrypted)
        #expect(protection.isLocked)
        #expect(!protection.unlock(withPassword: UUID().uuidString))
        #expect(protection.knownPassword == nil)
        #expect(protection.unlock(withPassword: phrase))
        #expect(!protection.isLocked)
        #expect(protection.knownPassword == phrase)
        #expect(protection.keepPasswordProtection)
        #expect(try DocumentProtection(document: encryptedDocument()).knownPassword == nil)
    }

    @Test(arguments: [false, true])
    func protectedRoundTripAndOptOut(keepProtection: Bool) async throws {
        let source = try encryptedDocument()
        let protection = DocumentProtection(document: source)
        #expect(protection.unlock(withPassword: phrase))
        protection.keepPasswordProtection = keepProtection
        let model = try ExportFixture.model(source)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let selected = protection.exportPassword
        try await SignedPDFExporter.writeAsync(
            source, placements: model.signaturePlacements, to: url, password: selected
        ) { _ in }
        let output = try #require(PDFDocument(url: url))
        #expect(output.isEncrypted == keepProtection)
        if keepProtection {
            #expect(output.isLocked)
            #expect(!output.unlock(withPassword: UUID().uuidString))
            #expect(output.unlock(withPassword: phrase))
        } else {
            #expect(protection.exportNotice.contains("will not be password protected"))
        }
        #expect(output.string?.contains("Original page content") == true)
        #expect(try ExportFixture.colorBounds(on: #require(output.page(at: 0)), red: true) == ExportFixture.marker)
    }

    @Test func unknownPasswordIsExplicitlyUnprotected() async throws {
        let source = try encryptedDocument()
        #expect(source.unlock(withPassword: phrase))
        let protection = DocumentProtection(document: source)
        #expect(protection.knownPassword == nil)
        #expect(!protection.canKeepPasswordProtection)
        #expect(protection.exportPassword == nil)
        #expect(protection.exportNotice.contains("password is unknown"))
        #expect(protection.exportNotice.contains("will not be password protected"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let selected = protection.exportPassword
        try await SignedPDFExporter.writeAsync(source, placements: [], to: url, password: selected) { _ in }
        #expect(PDFDocument(url: url)?.isEncrypted == false)
    }

    @Test func protectedOffsetGeometryFailsWithoutReplacingDestination() async throws {
        let source = try encryptedDocument()
        #expect(source.unlock(withPassword: phrase))
        let page = try #require(source.page(at: 0))
        page.setBounds(CGRect(x: -20, y: -30, width: 400, height: 600), for: .mediaBox)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let baseline = Data("existing destination".utf8)
        try baseline.write(to: url)
        await #expect(throws: PDFViewerDocument.ExportError.cannotPreservePageGeometry) {
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url, password: phrase) { _ in }
        }
        #expect(try Data(contentsOf: url) == baseline)
    }

    private func encryptedDocument() throws -> PDFDocument {
        let source = try ExportFixture.document()
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: phrase, .ownerPasswordOption: UUID().uuidString,
        ]
        let data = try #require(source.dataRepresentation(options: options))
        return try #require(PDFDocument(data: data))
    }
}
