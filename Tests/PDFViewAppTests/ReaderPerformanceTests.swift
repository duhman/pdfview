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

    @Test(arguments: [false, true])
    func outlineUsesDestinationPagesWithoutTextSelection(imageOnly: Bool) async throws {
        let document = try outlineDocument(imageOnly: imageOnly)
        let root = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Chapter"
        chapter.destination = try PDFDestination(page: #require(document.page(at: 1)), at: .zero)
        let section = PDFOutline()
        section.label = "Section"
        section.action = try PDFActionGoTo(destination: PDFDestination(page: #require(document.page(at: 3)), at: .zero))
        chapter.insertChild(section, at: 0)
        let next = PDFOutline()
        next.label = "Next"
        next.destination = try PDFDestination(page: #require(document.page(at: 5)), at: .zero)
        root.insertChild(chapter, at: 0)
        root.insertChild(next, at: 1)
        document.outlineRoot = root
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        view.document = document
        let reader = ReaderController()
        reader.attach(to: view, fileURL: nil)
        defer { reader.detach() }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        for index in [0, 1, 2, 3, 4, 5, 1, 4] {
            reader.go(to: index)
            for _ in 0 ..< 20 {
                await Task.yield()
            }
            let expected = switch index {
            case 0: nil as ObjectIdentifier?
            case 1, 2: ObjectIdentifier(chapter)
            case 3, 4: ObjectIdentifier(section)
            default: ObjectIdentifier(next)
            }
            #expect(reader.currentOutlineID == expected, "Page \(index)")
        }
        #expect(document.lookups == 0)
    }

    private func outlineDocument(imageOnly: Bool) throws -> OutlineLookupDocument {
        let fixture = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 6
        ))
        if imageOnly {
            let page = try #require(fixture.page(at: 0))
            let image = page.thumbnail(of: CGSize(width: 100, height: 150), for: .mediaBox)
            for index in 0 ..< fixture.pageCount {
                fixture.removePage(at: index)
                try fixture.insert(#require(PDFPage(image: image)), at: index)
            }
        }
        let document = try #require(OutlineLookupDocument(data: requireData(fixture)))
        if imageOnly {
            #expect(document.page(at: 0)?.string?.isEmpty != false)
        }
        return document
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
