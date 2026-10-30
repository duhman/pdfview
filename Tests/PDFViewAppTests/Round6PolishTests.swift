import AppKit
@preconcurrency import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

// MARK: Zoom to Fit shows the whole page

@Test func fitPageScaleIsLimitedByTheTighterSide() {
    let noMargins = NSEdgeInsets()
    // A portrait page in a wide window is limited by height.
    #expect(ZoomState.fitPageScale(
        viewSize: CGSize(width: 1000, height: 600), pageSize: CGSize(width: 400, height: 600), margins: noMargins
    ) == 1)
    // A landscape page in a tall window is limited by width.
    #expect(ZoomState.fitPageScale(
        viewSize: CGSize(width: 400, height: 1000), pageSize: CGSize(width: 800, height: 400), margins: noMargins
    ) == 0.5)
}

@Test func fitPageScaleLeavesRoomForThePageMargins() {
    let margins = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
    #expect(ZoomState.fitPageScale(
        viewSize: CGSize(width: 1000, height: 620), pageSize: CGSize(width: 400, height: 600), margins: margins
    ) == 1)
}

@Test func fitPageScaleStaysWithinTheZoomLimits() {
    #expect(ZoomState.fitPageScale(
        viewSize: CGSize(width: 10, height: 10), pageSize: CGSize(width: 400, height: 600), margins: NSEdgeInsets()
    ) == ZoomState.minimumScale)
    #expect(ZoomState.fitPageScale(
        viewSize: CGSize(width: 1000, height: 1000), pageSize: CGSize(width: 0, height: 0), margins: NSEdgeInsets()
    ) == nil)
}

@MainActor
@Test func zoomToFitShowsTheWholeCurrentPageInContinuousMode() throws {
    let document = try ExportFixture.document(mediaBoxes: Array(
        repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 3
    ))
    let view = PDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 500))
    view.displayMode = .singlePageContinuous
    view.document = document
    view.autoScales = true
    view.layoutDocumentView()
    let page = try #require(document.page(at: 1))
    view.go(to: page)

    let scale = try #require(view.zoomToFitCurrentPage())

    #expect(!view.autoScales)
    #expect(abs(view.scaleFactor - scale) < 0.0001)
    #expect(view.currentPage === page)
    let pageRect = view.convert(page.bounds(for: view.displayBox), from: page)
    #expect(pageRect.height <= view.bounds.height + 0.5)
    #expect(pageRect.width <= view.bounds.width + 0.5)
    // Fills the height rather than the width of this wide window.
    #expect(pageRect.height > view.bounds.height * 0.9)
}

@Test func fitWidthHasItsOwnChordAndBothAreListed() {
    #expect(MenuShortcuts.display(MenuShortcuts.zoomToFit) == "⌘9")
    #expect(MenuShortcuts.display(MenuShortcuts.fitWidth) == "⌥⌘9")
    let titles = MenuShortcuts.entries.filter { $0.menu == "View" }.map(\.title)
    #expect(titles.contains("Zoom to Fit"))
    #expect(titles.contains("Fit Width"))
}
