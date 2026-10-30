import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct ReaderIntegrationTests {
    @Test func asynchronousFindHighlightsWrapsAndClears() async throws {
        let document = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 3
        ))
        let view = PDFView()
        view.document = document
        let find = FindController()
        find.attach(to: view)
        defer { find.close() }
        find.show()
        find.search("Original")
        try await waitUntil { !find.state.isSearching }
        #expect(find.state.count == 3)
        #expect(view.highlightedSelections?.count == 3)
        find.advance(backwards: true)
        #expect(find.state.matchText == "3 of 3")
        #expect(view.currentSelection?.string == "Original")
        find.search("page")
        find.search("absent")
        try await waitUntil { !find.state.isSearching }
        #expect(find.state.isEmpty)
        find.close()
        #expect(view.highlightedSelections?.isEmpty != false)
        #expect(view.currentSelection == nil)
        #expect(!find.isVisible)
    }

    @Test func restoresPagePointAndManualZoomAndFollowsOutline() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let document = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 5
        ))
        let root = PDFOutline()
        let section = PDFOutline()
        section.label = "Chapter"
        section.destination = try PDFDestination(page: #require(document.page(at: 3)), at: CGPoint(x: 0, y: 500))
        root.insertChild(section, at: 0)
        document.outlineRoot = root
        let url = URL(fileURLWithPath: "/example/reader.pdf")
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        view.document = document
        let reader = ReaderController(defaults: defaults)
        reader.attach(to: view, fileURL: url)
        try await waitUntil { reader.pageCount == 5 }
        #expect(reader.outline.count == 1)
        reader.follow(section)
        try await waitUntil { reader.pageIndex == 3 }
        view.autoScales = false
        view.scaleFactor = 1.5
        reader.persist()
        let point = try #require(view.currentDestination).point
        reader.detach()
        let reopened = PDFView(frame: view.frame)
        reopened.document = document
        let restored = ReaderController(defaults: defaults)
        restored.attach(to: reopened, fileURL: url)
        defer { restored.detach() }
        try await waitUntil { restored.pageCount == 5 }
        #expect(restored.pageIndex == 3)
        #expect(abs(reopened.scaleFactor - 1.5) < 0.001)
        #expect(!reopened.autoScales)
        #expect(try abs(#require(reopened.currentDestination).point.y - point.y) < 1)
        #expect(restored.pageIndicator == "4 of 5")
    }

    @Test func reattachmentKeepsLayoutAndFitZoom() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let document = try ExportFixture.document()
        let url = URL(fileURLWithPath: "/example/fit.pdf")
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        view.document = document
        view.autoScales = true
        let reader = ReaderController(defaults: defaults)
        reader.attach(to: view, fileURL: url)
        try await waitUntil { reader.pageCount == 1 }
        reader.persist()
        reader.displayMode = .two
        reader.displaysAsBook = true
        reader.detach()
        let replacement = PDFView(frame: view.frame)
        replacement.document = document
        reader.attach(to: replacement, fileURL: url)
        defer { reader.detach() }
        try await waitUntil { replacement.autoScales }
        #expect(replacement.displayMode == .twoUp)
        #expect(replacement.displaysAsBook)
        #expect(replacement.autoScales)
    }

    @Test func printPreparationIncludesStampsAndCleansTemporaryFile() async throws {
        let source = try ExportFixture.document()
        let model = try ExportFixture.model(source)
        let printing = PDFPrinting()
        defer { printing.cleanup() }
        try await printing.prepare(source: source, placements: model.signaturePlacements) { _ in }
        let url = try #require(printing.temporaryURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let page = try #require(printing.document?.page(at: 0))
        #expect(try ExportFixture.colorBounds(on: page, red: true) == ExportFixture.marker)
        printing.cleanup()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try await printing.prepare(source: source, placements: []) { _ in }
        #expect(printing.document === source)
        #expect(printing.temporaryURL == nil)
    }

    @Test func printPreparationRejectsDeniedPermissions() async throws {
        let source = try ExportFixture.document()
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "test-owner", .userPasswordOption: "test-reader", .accessPermissionsOption: 0,
        ]
        let bytes = try #require(source.dataRepresentation(options: options))
        let restricted = try #require(PDFDocument(data: bytes))
        #expect(restricted.unlock(withPassword: "test-reader"))
        #expect(!restricted.allowsPrinting)
        let printing = PDFPrinting()
        do {
            try await printing.prepare(source: restricted, placements: []) { _ in }
            Issue.record("Printing a restricted PDF should fail")
        } catch {
            #expect((error as NSError).code == CocoaError.fileReadNoPermission.rawValue)
        }
        #expect(printing.temporaryURL == nil)
    }

    @Test func duplicateExportsArePrevented() {
        let operation = SignedCopyOperation()
        #expect(operation.reserve())
        #expect(!operation.reserve())
        operation.release()
        #expect(operation.reserve())
        operation.release()
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0 ..< 300 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("PDFKit condition did not become true")
    }
}
