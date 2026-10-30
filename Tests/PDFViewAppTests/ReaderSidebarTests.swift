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
