import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct CorrectnessRegressionTests {
    @Test(arguments: [UInt(0), UInt(16), UInt(255)], ["reader", "owner"])
    func protectedCopyRetainsPermissionsAndPasswordRole(mask: UInt, password: String) async throws {
        let restricted = try encryptedDocument(mask: mask)
        #expect(restricted.unlock(withPassword: password))
        let expected = restricted.accessPermissions
        let role = restricted.permissionsStatus
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("protected.pdf")
            try await SignedPDFExporter.writeAsync(restricted, placements: [], to: url, password: password) { _ in }
            let copy = try #require(PDFDocument(url: url))
            #expect(copy.isLocked)
            #expect(!copy.unlock(withPassword: "wrong"))
            if password == "reader" {
                // The unknown source owner credential is not reused by the copy.
                #expect(!copy.unlock(withPassword: "owner"))
            }
            #expect(copy.unlock(withPassword: password))
            #expect(copy.permissionsStatus == role)
            #expect(copy.accessPermissions == expected)
            #expect(copy.allowsPrinting == restricted.allowsPrinting)
            #expect(copy.allowsCopying == restricted.allowsCopying)
            #expect(copy.string?.contains("Original page content") == true)
        }
    }

    @Test func unrepresentablePermissionsFailWithoutReplacingDestination() async throws {
        let source = try encryptedDocument(mask: PDFAccessPermissions.allowsFormFieldEntry.rawValue)
        #expect(source.unlock(withPassword: "reader"))
        #expect(!source.allowsPrinting)
        #expect(!source.allowsCopying)
        try await ExportFixture.withDirectoryAsync { directory in
            let url = directory.appendingPathComponent("protected.pdf")
            let existing = Data("existing destination".utf8)
            try existing.write(to: url)
            await #expect(throws: PDFViewerDocument.ExportError.cannotPreserveAccessPermissions) {
                try await SignedPDFExporter.writeAsync(source, placements: [], to: url, password: "reader") { _ in }
            }
            #expect(try Data(contentsOf: url) == existing)
            // Explicit opt-out still permits an unprotected copy.
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { _ in }
            #expect(PDFDocument(url: url)?.isEncrypted == false)
        }
    }

    private func encryptedDocument(mask: UInt) throws -> PDFDocument {
        let source = try ExportFixture.document()
        let data = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "reader",
            PDFDocumentWriteOption.ownerPasswordOption: "owner",
            PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: mask),
        ]))
        return try #require(PDFDocument(data: data))
    }

    @Test func lockedDocumentClosesAndQuitsWithoutReview() throws {
        let source = try ExportFixture.document()
        let data = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "reader",
            PDFDocumentWriteOption.ownerPasswordOption: "owner",
        ]))
        let locked = try #require(PDFDocument(data: data))
        let model = PDFViewerDocument(pdfDocument: locked)
        let protection = DocumentProtection(document: locked, formBaseline: model.formBaseline)
        let work = SigningFlowLogic.unsavedWork(
            placements: [],
            exported: nil,
            formValues: protection.formBaseline?.values(),
            savedFormValues: protection.initialFormValues,
            isLocked: locked.isLocked
        )
        #expect(work.isEmpty)
        #expect(!work.formEntries)
        guard work.isEmpty else { return }
        let closeGuard = DocumentCloseGuard()
        closeGuard.unsavedWork = { work }
        #expect(!closeGuard.hasUnsavedWork)
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        closeGuard.install(on: window)
        closeGuard.isEdited = !work.isEmpty
        #expect(!window.isDocumentEdited)
        if work.isEmpty {
            #expect(closeGuard.windowShouldClose(window))
        }
        var quit: Bool?
        TerminationReview.run(
            [closeGuard],
            choose: { _ in
                Issue.record("A locked document must not request quit review")
                return .cancel
            },
            completion: { quit = $0 }
        )
        #expect(quit == true)
    }
}
