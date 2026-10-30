import AppKit
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct ReaderPerformanceTests {
    @Test func observesOnlyThePDFScrollViewAndReleasesOnDetach() async throws {
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        view.document = try ExportFixture.document()
        let reader = ReaderController()
        reader.attach(to: view, fileURL: nil)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let clip = try #require(view.documentView?.enclosingScrollView?.contentView)
        #expect(reader.observedClipView === clip)
        #expect(clip.postsBoundsChangedNotifications)
        reader.detach()
        #expect(reader.observedClipView == nil)
    }

    @Test func outlineLookupIsCachedWhenRevisitingAPage() async throws {
        let fixture = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 2
        ))
        let document = try #require(OutlineLookupDocument(data: requireData(fixture)))
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        view.document = document
        let reader = ReaderController()
        reader.attach(to: view, fileURL: nil)
        defer { reader.detach() }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        reader.go(to: 1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let count = document.lookups
        reader.go(to: 0)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        reader.go(to: 1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(count > 0)
        #expect(document.lookups == count)
    }

    private func requireData(_ document: PDFDocument) throws -> Data {
        try #require(document.dataRepresentation())
    }
}

private final class OutlineLookupDocument: PDFDocument {
    private(set) var lookups = 0

    override func outlineItem(for selection: PDFSelection) -> PDFOutline? {
        MainActor.preconditionIsolated()
        lookups += 1
        return super.outlineItem(for: selection)
    }
}
