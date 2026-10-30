import Quartz
import Testing
@testable import PDFViewApp

@MainActor
@Test
func sidebarResolvesNestedOutlineSelection() {
    let root = PDFOutline()
    let parent = PDFOutline()
    let child = PDFOutline()
    root.insertChild(parent, at: 0)
    parent.insertChild(child, at: 0)
    let nodes = ReaderOutlineNode.children(of: root) ?? []
    #expect(ReaderSidebar.find(ObjectIdentifier(child), in: nodes) === child)
    #expect(ReaderSidebar.find(ObjectIdentifier(parent), in: nodes) === parent)
    #expect(ReaderSidebar.find(ObjectIdentifier(root), in: nodes) == nil)
    #expect(ReaderSidebar.find(nil, in: nodes) == nil)
}

@MainActor
@Test
func theOutlineTabIsOfferedOnlyWhenThePDFHasAnOutline() {
    #expect(ReaderSidebar.shownTab(.outline, hasOutline: false) == .thumbnails)
    #expect(ReaderSidebar.shownTab(.outline, hasOutline: true) == .outline)
    #expect(ReaderSidebar.shownTab(.thumbnails, hasOutline: false) == .thumbnails)
    #expect(ReaderSidebar.outlineHelp(hasOutline: false) == "This PDF has no outline")
    #expect(ReaderSidebar.outlineHelp(hasOutline: true) == nil)
    // A root with no sections is no outline.
    #expect((ReaderOutlineNode.children(of: PDFOutline()) ?? []).isEmpty)
}
