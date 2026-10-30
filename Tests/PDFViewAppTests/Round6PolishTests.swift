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

// MARK: Place Initials on Every Page shows where they went

@Test func everyPageRevealsTheNewInitialsOnTheCurrentPage() {
    let targets: [(pageIndex: Int, bounds: CGRect)] = [
        (0, CGRect(x: 1, y: 1, width: 60, height: 20)),
        (1, CGRect(x: 2, y: 2, width: 60, height: 20)),
        (2, CGRect(x: 3, y: 3, width: 60, height: 20)),
    ]
    #expect(StampWorkflow.targetToReveal(targets, currentPageIndex: 1)?.pageIndex == 1)
    #expect(StampWorkflow.targetToReveal(targets, currentPageIndex: 1)?.bounds == targets[1].bounds)
}

@Test func everyPageRevealsTheNextNewInitialsWhenTheCurrentPageHadSome() {
    let targets: [(pageIndex: Int, bounds: CGRect)] = [
        (0, CGRect(x: 1, y: 1, width: 60, height: 20)),
        (3, CGRect(x: 3, y: 3, width: 60, height: 20)),
    ]
    #expect(StampWorkflow.targetToReveal(targets, currentPageIndex: 1)?.pageIndex == 3)
    #expect(StampWorkflow.targetToReveal(targets, currentPageIndex: 5)?.pageIndex == 0)
    #expect(StampWorkflow.targetToReveal(targets, currentPageIndex: nil)?.pageIndex == 0)
    #expect(StampWorkflow.targetToReveal([], currentPageIndex: 0) == nil)
}

// MARK: The signing banner says where the fields are

private func field(page: Int, x: CGFloat = 100) -> SignatureField {
    SignatureField(pageIndex: page, bounds: CGRect(x: x, y: 100, width: 200, height: 50))
}

private func stamp(page: Int, in field: SignatureField) -> PDFViewerDocument.SignaturePlacement {
    PDFViewerDocument.SignaturePlacement(
        pageIndex: page,
        bounds: field.bounds.insetBy(dx: 10, dy: 10),
        signaturePNGData: Data([1]),
        signerName: "Tester"
    )
}

@Test func theBannerPointsToTheFieldWhenItIsOnAnotherPage() {
    #expect(SigningFlowLogic.fieldLocationText(
        fields: [field(page: 2)], placements: [], currentPageIndex: 0
    ) == "Next field: page 3.")
}

@Test func theBannerSaysNothingExtraWhenAnEmptyFieldIsOnThisPage() {
    #expect(SigningFlowLogic.fieldLocationText(
        fields: [field(page: 0), field(page: 2)], placements: [], currentPageIndex: 0
    ) == nil)
}

@Test func theBannerPointsPastFilledFieldsAndWrapsAround() {
    let filled = field(page: 1)
    let fields = [field(page: 0), filled, field(page: 1, x: 300)]
    // Past the last empty field (page 2's second one), it wraps to page 1.
    #expect(SigningFlowLogic.fieldLocationText(
        fields: fields, placements: [stamp(page: 1, in: filled)], currentPageIndex: 2
    ) == "Next field: page 1.")
    #expect(SigningFlowLogic.fieldLocationText(
        fields: [filled], placements: [stamp(page: 1, in: filled)], currentPageIndex: 0
    ) == nil)
    #expect(SigningFlowLogic.fieldLocationText(fields: [], placements: [], currentPageIndex: 0) == nil)
    #expect(SigningFlowLogic.fieldLocationText(
        fields: [field(page: 0), field(page: 3)], placements: [], currentPageIndex: 1
    ) == "Next field: page 4.")
}

@Test func enteringSigningAlsoSaysWhereTheFieldIs() {
    let text = SigningFlowLogic.enteredAnnouncement(
        mode: .fieldPlacement, kind: .signature, fieldLocation: "Next field: page 3."
    )
    #expect(text.contains("Next field: page 3."))
    #expect(text.hasSuffix("Press Escape to stop."))
}

// MARK: The initials banner fits on one line

@MainActor
@Test func everySigningBannerInstructionFitsOneLineAtA1000PointWindow() {
    let font = NSFont.preferredFont(forTextStyle: .callout)
    for kind in StampKind.allCases {
        for mode in [SigningMode.freePlacement, .fieldPlacement] {
            let text = SigningFlowLogic.statusText(mode: mode, kind: kind) + " Next field: page 10."
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            // 1000 pt less the icon, Fields/Anywhere picker, Done button, spacing and padding.
            #expect(width < 680, "\(kind) \(mode): \(width) pt")
        }
    }
}

@Test func theInitialsBannerLeavesEveryPageToHelpAndVoiceOver() {
    for mode in [SigningMode.freePlacement, .fieldPlacement] {
        #expect(!SigningFlowLogic.statusText(mode: mode, kind: .initials).contains("Every Page"))
        #expect(SigningFlowLogic.statusHelp(kind: .initials)?
            .contains("Sign > Place Initials on Every Page (⌥⌘I)") == true)
        #expect(SigningFlowLogic.enteredAnnouncement(mode: mode, kind: .initials)
            .contains("Sign > Place Initials on Every Page (⌥⌘I) initials every page at once."))
    }
    #expect(SigningFlowLogic.statusHelp(kind: .signature) == nil)
}

// MARK: Edit > Undo names stamp edits

/// Stamp editing on a real window's undo manager, the one the Edit menu follows.
@MainActor
private final class WindowEditingFixture {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: true
    )
    let closeGuard = DocumentCloseGuard()
    let editor = SignaturePlacementEditor()
    var document = PDFViewerDocument()
    let undoManager: UndoManager

    init() throws {
        window.isReleasedWhenClosed = false
        closeGuard.install(on: window)
        undoManager = try #require(closeGuard.undoManager)
        // One explicit group per user action stands in for AppKit's group per event.
        undoManager.groupsByEvent = false
        editor.document = Binding(get: { self.document }, set: { self.document = $0 })
        editor.undoManager = undoManager
    }

    func step(_ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    static func placement(_ kind: StampKind, page: Int) -> PDFViewerDocument.SignaturePlacement {
        PDFViewerDocument.SignaturePlacement(
            pageIndex: page,
            bounds: CGRect(x: 10, y: 10, width: 100, height: 20),
            signaturePNGData: Data([1]),
            signerName: "Tester",
            kind: kind
        )
    }
}

@MainActor
@Test func stampEditsNameTheirUndoOnTheWindowsUndoManager() throws {
    let fixture = try WindowEditingFixture()
    #expect(fixture.undoManager === fixture.window.undoManager)
    let signature = WindowEditingFixture.placement(.signature, page: 0)
    fixture.step { fixture.editor.add(signature) }
    #expect(fixture.undoManager.undoMenuItemTitle == "Undo Add Signature")

    let moved = signature.bounds.offsetBy(dx: 5, dy: 0)
    fixture.step { fixture.editor.setBounds(id: signature.id, to: moved, actionName: "Move Signature") }
    #expect(fixture.undoManager.undoMenuItemTitle == "Undo Move Signature")

    let batch = [WindowEditingFixture.placement(.initials, page: 0), WindowEditingFixture.placement(.initials, page: 1)]
    fixture.step { fixture.editor.add(batch, actionName: StampWorkflow.everyPageActionName) }
    #expect(fixture.undoManager.undoMenuItemTitle == "Undo Place Initials on Every Page")
}

@MainActor
@Test func theEditMenuNamesTheNextUndoAndRedo() throws {
    let fixture = try WindowEditingFixture()
    let initials = WindowEditingFixture.placement(.initials, page: 2)
    fixture.step { fixture.editor.add(initials) }
    #expect(fixture.undoManager.undoMenuItemTitle == "Undo Add Initials")
    fixture.step { fixture.editor.delete(id: initials.id) }
    #expect(fixture.undoManager.undoMenuItemTitle == "Undo Remove Initials from Page")

    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements.contains { $0.id == initials.id })
    let menu = UndoMenuState(fixture.undoManager)
    #expect(menu.undoTitle == "Undo Add Initials")
    #expect(menu.redoTitle == "Redo Remove Initials from Page")
    #expect(menu.canUndo && menu.canRedo)
}

@MainActor
@Test func theEditMenuFindsTheWindowsUndoManagerFromThePDFView() {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: true
    )
    window.isReleasedWhenClosed = false
    let pdfView = SigningPDFView(frame: window.contentLayoutRect)
    window.contentView = pdfView
    window.makeFirstResponder(pdfView)
    // `undo:` and the menu title both resolve through the first responder.
    #expect(window.firstResponder?.undoManager === window.undoManager)
    #expect(NSWindow.instancesRespond(to: Selector(("undo:"))))
}

@MainActor
@Test func anEmptyUndoMenuSaysUndoAndRedo() {
    let state = UndoMenuState(nil)
    #expect(state.undoTitle == "Undo")
    #expect(state.redoTitle == "Redo")
    #expect(!state.canUndo && !state.canRedo)
    #expect(UndoMenuState(UndoManager()) == state)
}

// MARK: Selection handles sit outside small stamps

@MainActor
@Test func theSelectionFrameIsOutsetByHalfAHandle() {
    #expect(PlacementGeometry.selectionOutset == PageOverlayView.handleSize / 2)
    let stamp = CGRect(x: 100, y: 100, width: 110, height: 20)
    #expect(PlacementGeometry.selectionFrame(around: stamp, onePoint: 1)
        == CGRect(x: 94.5, y: 94.5, width: 121, height: 31))
    // At 200% zoom one screen point is half a page unit.
    #expect(PlacementGeometry.selectionFrame(around: stamp, onePoint: 0.5)
        == CGRect(x: 97.25, y: 97.25, width: 115.5, height: 25.5))
}

@MainActor
@Test func handlesOnADateStampDoNotCoverItsInk() {
    let stamp = CGRect(x: 100, y: 100, width: 110, height: 20)
    let frame = PlacementGeometry.selectionFrame(around: stamp, onePoint: 1)
    let handle = PageOverlayView.handleSize
    for corner in PlacementGeometry.Corner.allCases {
        let center = corner.point(in: frame)
        let square = CGRect(x: center.x - handle / 2, y: center.y - handle / 2, width: handle, height: handle)
        #expect(!square.intersects(stamp.insetBy(dx: 0.01, dy: 0.01)), "\(corner)")
    }
}

@Test func aResizeDragMovesTheCornerByThePointerTravelWithoutJumping() {
    let stamp = CGRect(x: 100, y: 100, width: 110, height: 20)
    let page = CGRect(x: 0, y: 0, width: 600, height: 800)
    #expect(PlacementGeometry.resized(stamp, dragging: .topRight, by: .zero, within: page) == stamp)
    let wider = PlacementGeometry.resized(stamp, dragging: .topRight, by: CGVector(dx: 110, dy: 0), within: page)
    #expect(wider == CGRect(x: 100, y: 100, width: 220, height: 40))
}
