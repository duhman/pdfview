import AppKit
@testable import PDFViewApp
import Quartz
import Testing

@MainActor
struct SignedPDFNavigationTests {
    @Test(arguments: [false, true], [CGPoint.zero, CGPoint(x: 20, y: 30), CGPoint(x: -20, y: -30)])
    func preservesURLAndGoToLinks(signed: Bool, origin: CGPoint) throws {
        let fixture = try navigationDocument(origin: origin)
        let source = fixture.document
        defer { withExtendedLifetime(fixture.pages) {} }
        let first = try #require(source.page(at: 0))
        let second = try #require(source.page(at: 1))
        let sourceURL = try #require(first.annotations.first { $0.url != nil })
        #expect(source.outlineRoot?.numberOfChildren == 1)
        #expect(source.outlineRoot?.child(at: 0)?.destination?.page === source.page(at: 1))
        let model = try ExportFixture.model(source, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let outputPages = (0 ..< output.pageCount).compactMap { output.page(at: $0) }
            defer { withExtendedLifetime(outputPages) {} }
            let links = try #require(output.page(at: 0)).annotations
            #expect(links.count == 2)
            let exportedURL = try #require(links.first { $0.url != nil })
            #expect(exportedURL !== sourceURL)
            #expect(exportedURL.url == sourceURL.url)
            #expect(exportedURL.bounds == sourceURL.bounds)
            #expect(exportedURL.contents == sourceURL.contents)
            let action = try #require(links.compactMap { $0.action as? PDFActionGoTo }.first)
            #expect(action.destination.page === output.page(at: 1))
            #expect(action.destination.point == CGPoint(x: 30, y: 400))
            #expect(action.destination.zoom == 1.5)
            let direct = try #require(output.page(at: 1)?.annotations.first?.destination)
            #expect(direct.page === output.page(at: 0))
            #expect(direct.point == CGPoint(x: 40, y: 300))
            #expect(output.page(at: 1)?.annotations.first?.contents == "räksmörgås café")
            #expect(first.annotations.count == 2)
            let sourceAction = first.annotations.compactMap { $0.action as? PDFActionGoTo }.first
            #expect(sourceAction?.destination.page === second)
        }
    }

    @Test(arguments: [false, true], [CGPoint.zero, CGPoint(x: 20, y: 30), CGPoint(x: -20, y: -30)])
    func preservesNestedOutline(signed: Bool, origin: CGPoint) throws {
        let fixture = try navigationDocument(origin: origin)
        let source = fixture.document
        defer { withExtendedLifetime(fixture.pages) {} }
        #expect(source.outlineRoot?.numberOfChildren == 1)
        #expect(source.outlineRoot?.child(at: 0)?.destination?.page === source.page(at: 1))
        let model = try ExportFixture.model(source, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let outputPages = (0 ..< output.pageCount).compactMap { output.page(at: $0) }
            defer { withExtendedLifetime(outputPages) {} }
            let outline = try #require(output.outlineRoot?.child(at: 0))
            #expect(outline.label == "Second page")
            #expect(outline.isOpen)
            #expect(outline.destination?.page === output.page(at: 1))
            #expect(outline.destination?.point == CGPoint(x: 30, y: 400))
            #expect(outline.destination?.zoom == 1.5)
            #expect(outline.child(at: 0)?.label == "First page")
            let childAction = outline.child(at: 0)?.action as? PDFActionGoTo
            #expect(childAction?.destination.page === output.page(at: 0))
            #expect(source.outlineRoot?.child(at: 0)?.destination?.page === source.page(at: 1))
        }
    }

    @Test(arguments: [false, true])
    func preservesDocumentAttributes(signed: Bool) throws {
        let source = try ExportFixture.document()
        let baseline = try #require(source.dataRepresentation())
        source.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Signed agreement",
            PDFDocumentAttribute.authorAttribute: "Tester",
            PDFDocumentAttribute.subjectAttribute: "Export regression",
            PDFDocumentAttribute.keywordsAttribute: ["offline", "signing"]
        ]
        let model = try ExportFixture.model(source, baseline: baseline, signed: signed)
        try ExportFixture.withDirectory { directory in
            let url = directory.appendingPathComponent("signed.pdf")
            try model.writeSignedCopy(to: url)
            let output = try #require(PDFDocument(url: url))
            let outputPages = (0 ..< output.pageCount).compactMap { output.page(at: $0) }
            defer { withExtendedLifetime(outputPages) {} }
            let attributes = try #require(output.documentAttributes)
            #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Signed agreement")
            #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String == "Tester")
            #expect(attributes[PDFDocumentAttribute.subjectAttribute] as? String == "Export regression")
            #expect(attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] == ["offline", "signing"])
        }
    }

    private func navigationDocument(origin: CGPoint) throws -> (document: PDFDocument, pages: [PDFPage]) {
        let source = try ExportFixture.document(mediaBoxes: [
            CGRect(origin: origin, size: CGSize(width: 400, height: 600)),
            CGRect(origin: origin, size: CGSize(width: 595, height: 842))
        ])
        let first = try #require(source.page(at: 0))
        let second = try #require(source.page(at: 1))
        let urlLink = link(at: 20)
        urlLink.url = URL(string: "https://example.com/signing")
        urlLink.contents = "A literal /Rect [9 9 9 9] with (nested) text"
        first.addAnnotation(urlLink)
        let destination = PDFDestination(page: second, at: CGPoint(x: 30, y: 400))
        destination.zoom = 1.5
        let goTo = link(at: 70)
        goTo.action = PDFActionGoTo(destination: destination)
        first.addAnnotation(goTo)
        let directLink = link(at: 110)
        directLink.destination = PDFDestination(page: first, at: CGPoint(x: 40, y: 300))
        directLink.contents = "räksmörgås café"
        second.addAnnotation(directLink)
        source.outlineRoot = makeOutline(destination: destination, first: first)
        return (source, [first, second])
    }

    private func link(at y: CGFloat) -> PDFAnnotation {
        PDFAnnotation(bounds: CGRect(x: 10, y: y, width: 80, height: 30), forType: .link, withProperties: nil)
    }

    private func makeOutline(destination: PDFDestination, first: PDFPage) -> PDFOutline {
        let root = PDFOutline()
        let parent = PDFOutline()
        parent.label = "Second page"
        parent.destination = destination
        let child = PDFOutline()
        child.label = "First page"
        child.action = PDFActionGoTo(destination: PDFDestination(page: first, at: CGPoint(x: 20, y: 200)))
        parent.insertChild(child, at: 0)
        root.insertChild(parent, at: 0)
        parent.isOpen = true
        return root
    }
}
