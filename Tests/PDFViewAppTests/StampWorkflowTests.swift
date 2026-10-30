import AppKit
@preconcurrency import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

private enum Page {
    static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)
}

// MARK: Stamp sizes

@Test func eachStampKindHasItsOwnDefaultWidth() {
    #expect(StampKind.signature.defaultWidth == 180)
    #expect(StampKind.initials.defaultWidth == 60)
    #expect(StampKind.date.defaultWidth == 110)
}

@MainActor
@Test func stampSizesRememberTheLastWidthPerKindForTheSession() {
    let sizes = StampSizeMemory()
    #expect(sizes.width(for: .initials) == 60)

    sizes.remember(width: 90, for: .initials)
    #expect(sizes.width(for: .initials) == 90)
    #expect(sizes.width(for: .signature) == 180)
    #expect(sizes.width(for: .date) == 110)

    // A width below the resize floor is never remembered as the next default.
    sizes.remember(width: 3, for: .date)
    #expect(sizes.width(for: .date) == PlacementGeometry.minimumWidth)
}

@Test func defaultRectUsesTheRequestedWidth() {
    let rect = PlacementGeometry.defaultRect(
        centeredAt: CGPoint(x: 300, y: 400),
        imageSize: CGSize(width: 200, height: 100),
        pageBounds: Page.letter,
        width: 60
    )
    #expect(rect.width == 60)
    #expect(rect.height == 30)
    #expect(rect.midX == 300)
    #expect(rect.midY == 400)
}

@MainActor
@Test func clickPlacementUsesTheActiveKindsWidth() throws {
    let document = try #require(PDFDocument(data: makeBlankPDF(pages: 1)))
    var placed: [CGRect] = []
    var representable = makeRepresentable(document: document)
    representable.signingMode = .freePlacement
    representable.stampPNGData = try makeStampPNG(width: 120, height: 40)
    representable.stampWidth = 60
    representable.onPlaceSignature = { _, bounds in placed.append(bounds) }
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
    coordinator.attach(to: pdfView)
    pdfView.document = document

    let overlay = PageOverlayView(page: document.page(at: 0))
    coordinator.overlay(overlay, didClickToSignAt: CGPoint(x: 200, y: 200))

    #expect(placed.map(\.width) == [60])
    #expect(placed.first?.height == 20)
}

// MARK: Fixtures

func makeBlankPDF(pages: Int, size: CGSize = CGSize(width: 612, height: 792)) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    let document = PDFDocument()
    for index in 0 ..< pages {
        try document.insert(#require(PDFPage(image: image)), at: index)
    }
    return try #require(document.dataRepresentation())
}

func makeStampPNG(width: Int, height: Int) throws -> Data {
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    return try #require(rep.representation(using: .png, properties: [:]))
}

// MARK: Kind-aware wording

@Test func editNamesSayWhichKindOfStampChanged() {
    #expect(StampKind.signature.actionName(.add) == "Add Signature")
    #expect(StampKind.initials.actionName(.move) == "Move Initials")
    #expect(StampKind.date.actionName(.resize) == "Resize Date")
    #expect(StampKind.initials.actionName(.remove) == "Remove Initials from Page")
}

@MainActor
@Test func undoNamesFollowThePlacementsKind() {
    var document = PDFViewerDocument()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = SignaturePlacementEditor()
    editor.document = Binding(get: { document }, set: { document = $0 })
    editor.undoManager = undoManager
    let initials = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 10, y: 10, width: 60, height: 20),
        signaturePNGData: Data([1]),
        signerName: "Tester",
        kind: .initials
    )

    undoManager.beginUndoGrouping()
    editor.add(initials)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName == "Add Initials")

    undoManager.beginUndoGrouping()
    editor.delete(id: initials.id)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName == "Remove Initials from Page")
}

@MainActor
@Test func contextMenuAndVoiceOverActionsNameTheStampKind() throws {
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
    let stamp = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: blackPixel(),
        kind: .date
    )
    overlay.content = PageOverlayView.Content(cropBox: overlay.frame, stamps: [stamp])

    let menu = try #require(overlay.menu(for: rightClick(at: CGPoint(x: 120, y: 110))))
    #expect(menu.items.map(\.title) == ["Remove Date from Page"])

    let element = try #require(overlay.accessibilityChildren()?.first as? NSAccessibilityElement)
    #expect(element.accessibilityCustomActions()?.map(\.name) == ["Remove Date from Page", "Move"])
}

@Test func moveInstructionsNameTheStampKind() {
    #expect(StampAccessibility.moveInstructions(for: .initials).hasPrefix("Use the arrow keys to move the initials"))
    #expect(StampAccessibility.moveInstructions(for: .signature).contains("the signature"))
}

// MARK: Active kind and shortcuts

@Test func placingOrStoppingReturnsToTheSignatureKind() {
    for kind in StampKind.allCases {
        #expect(StampWorkflow.kindAfterPlacementOrExit(kind) == .signature)
    }
}

@Test func signMenuTitlesNameTheActiveKind() {
    #expect(StampWorkflow.signingToggleTitle(mode: .idle, kind: .signature) == "Start Signing")
    #expect(StampWorkflow.signingToggleTitle(mode: .freePlacement, kind: .signature) == "Stop Signing")
    #expect(StampWorkflow.signingToggleTitle(mode: .freePlacement, kind: .initials) == "Stop Placing Initials")
    #expect(StampWorkflow.placeInNextFieldTitle(kind: .signature) == "Place Signature in Next Field")
    #expect(StampWorkflow.placeOnCurrentPageTitle(kind: .date) == "Place Date on Current Page")
}

@Test func signingBannerNamesTheMenuItemsForTheActiveKind() {
    let text = SigningFlowLogic.statusText(mode: .freePlacement, kind: .initials)
    #expect(text.contains(StampWorkflow.placeOnCurrentPageTitle(kind: .initials)))
    let fieldText = SigningFlowLogic.statusText(mode: .fieldPlacement, kind: .signature)
    #expect(fieldText.contains(StampWorkflow.placeInNextFieldTitle(kind: .signature)))
}

@Test func menuShortcutsAreUniqueAndAvoidStandardMenuChords() {
    let all = MenuShortcuts.all
    #expect(Set(all.map(MenuShortcuts.Chord.init)).count == all.count)
    let standard = Set(MenuShortcuts.standardChords)
    for shortcut in MenuShortcuts.appSpecific {
        #expect(!standard.contains(MenuShortcuts.Chord(shortcut)), "\(shortcut) collides with a standard chord")
    }
    #expect(MenuShortcuts.appSpecific
        .contains { MenuShortcuts.Chord($0) == MenuShortcuts.Chord(MenuShortcuts.placeSignature) })
}

// MARK: Next empty field

private func field(_ page: Int, x: CGFloat) -> SignatureField {
    SignatureField(pageIndex: page, bounds: CGRect(x: x, y: 100, width: 150, height: 40))
}

private func stamp(in field: SignatureField) -> PDFViewerDocument.SignaturePlacement {
    PDFViewerDocument.SignaturePlacement(
        pageIndex: field.pageIndex,
        bounds: field.bounds.insetBy(dx: 4, dy: 4),
        signaturePNGData: Data([1]),
        signerName: "Tester"
    )
}

@Test func nextFieldSkipsFieldsThatAlreadyHoldAStamp() {
    let fields = [field(0, x: 50), field(0, x: 300), field(1, x: 50)]
    let placements = [stamp(in: fields[1])]
    #expect(StampWorkflow.nextEmptyFieldIndex(after: nil, fields: fields, placements: placements) == 0)
    #expect(StampWorkflow.nextEmptyFieldIndex(after: 0, fields: fields, placements: placements) == 2)
    // Wraps past the end to the first empty field.
    #expect(StampWorkflow.nextEmptyFieldIndex(after: 2, fields: fields, placements: [stamp(in: fields[0])]) == 1)
}

@Test func nextFieldIsNilOnceEveryFieldHoldsAStamp() {
    let fields = [field(0, x: 50), field(1, x: 50)]
    #expect(StampWorkflow.nextEmptyFieldIndex(after: nil, fields: fields, placements: fields.map(stamp)) == nil)
    #expect(StampWorkflow.nextEmptyFieldIndex(after: nil, fields: [], placements: []) == nil)
    // A stamp on another page at the same spot does not fill the field.
    let elsewhere = PDFViewerDocument.SignaturePlacement(
        pageIndex: 5, bounds: fields[0].bounds, signaturePNGData: Data([1]), signerName: "Tester"
    )
    #expect(StampWorkflow.nextEmptyFieldIndex(after: nil, fields: fields, placements: [elsewhere]) == 0)
    #expect(StampWorkflow.allFieldsFilledAnnouncement == "Every signature field already has a stamp.")
}

// MARK: Initials on every page

private func initials(page: Int, bounds: CGRect) -> PDFViewerDocument.SignaturePlacement {
    PDFViewerDocument.SignaturePlacement(
        pageIndex: page, bounds: bounds, signaturePNGData: Data([1]), signerName: "Tester", kind: .initials
    )
}

@Test func initialsGoToTheBottomRightMarginWithoutAReference() {
    let pages = [StampWorkflow.PageFrame(cropBox: Page.letter), StampWorkflow.PageFrame(cropBox: Page.letter)]
    let targets = StampWorkflow.initialsOnEveryPage(
        reference: nil, pages: pages, placements: [], defaultSize: CGSize(width: 60, height: 20)
    )
    #expect(targets.map(\.pageIndex) == [0, 1])
    let rect = targets[0].bounds
    #expect(rect.size == CGSize(width: 60, height: 20))
    #expect(rect.maxX == Page.letter.maxX - StampWorkflow.pageMargin)
    #expect(rect.minY == Page.letter.minY + StampWorkflow.pageMargin)
}

@Test func bottomRightFollowsThePageRotationOnScreen() {
    let rotated = StampWorkflow.PageFrame(cropBox: Page.letter, rotation: 90)
    let targets = StampWorkflow.initialsOnEveryPage(
        reference: nil, pages: [rotated], placements: [], defaultSize: CGSize(width: 60, height: 20)
    )
    let rect = targets[0].bounds
    // A page turned 90° clockwise shows its top-right page-space corner at the bottom right.
    #expect(rect.maxX == Page.letter.maxX - StampWorkflow.pageMargin)
    #expect(rect.maxY == Page.letter.maxY - StampWorkflow.pageMargin)
}

@Test func initialsCopyTheReferencePositionRelativeToEachPage() {
    let small = CGRect(x: 0, y: 0, width: 306, height: 396)
    let pages = [
        StampWorkflow.PageFrame(cropBox: Page.letter),
        StampWorkflow.PageFrame(cropBox: Page.letter),
        StampWorkflow.PageFrame(cropBox: small),
    ]
    let reference = initials(page: 0, bounds: CGRect(x: 520, y: 40, width: 60, height: 20))
    let signature = PDFViewerDocument.SignaturePlacement(
        pageIndex: 1, bounds: CGRect(x: 10, y: 10, width: 180, height: 60), signaturePNGData: Data([1]), signerName: "T"
    )
    let targets = StampWorkflow.initialsOnEveryPage(
        reference: reference, pages: pages, placements: [reference, signature], defaultSize: CGSize(width: 1, height: 1)
    )
    // The reference page already has initials; a signature does not count.
    #expect(targets.map(\.pageIndex) == [1, 2])
    #expect(targets[0].bounds == reference.bounds)
    let scaled = targets[1].bounds
    #expect(scaled.size == reference.bounds.size)
    #expect(abs(scaled.midX - reference.bounds.midX / 2) < 0.001)
    #expect(abs(scaled.midY - reference.bounds.midY / 2) < 0.001)
    #expect(small.contains(scaled))
}

@Test func everyPageReferenceIsTheSelectedOrLastInitials() {
    let first = initials(page: 0, bounds: CGRect(x: 1, y: 1, width: 60, height: 20))
    let last = initials(page: 2, bounds: CGRect(x: 2, y: 2, width: 60, height: 20))
    let signature = PDFViewerDocument.SignaturePlacement(
        pageIndex: 1, bounds: .zero, signaturePNGData: Data([1]), signerName: "T"
    )
    let placements = [first, last, signature]
    #expect(StampWorkflow.referenceInitials(selectedID: first.id, placements: placements) == first)
    #expect(StampWorkflow.referenceInitials(selectedID: signature.id, placements: placements) == last)
    #expect(StampWorkflow.referenceInitials(selectedID: nil, placements: [signature]) == nil)
}

@Test func everyPageAnnouncementCountsThePages() {
    #expect(StampWorkflow.everyPageAnnouncement(count: 1) == "Placed initials on 1 page.")
    #expect(StampWorkflow.everyPageAnnouncement(count: 12) == "Placed initials on 12 pages.")
    #expect(StampWorkflow.everyPageAnnouncement(count: 0) == "Every page already has initials.")
}

@MainActor
@Test func initialsOnEveryPageUndoAsOneStep() {
    var document = PDFViewerDocument()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = SignaturePlacementEditor()
    editor.document = Binding(get: { document }, set: { document = $0 })
    editor.undoManager = undoManager
    let batch = (0 ..< 3).map { initials(page: $0, bounds: CGRect(x: 10, y: 10, width: 60, height: 20)) }

    undoManager.beginUndoGrouping()
    editor.add(batch, actionName: StampWorkflow.everyPageActionName)
    undoManager.endUndoGrouping()
    #expect(document.signaturePlacements == batch)
    #expect(undoManager.undoActionName == "Place Initials on Every Page")

    undoManager.undo()
    #expect(document.signaturePlacements.isEmpty)
    undoManager.redo()
    #expect(document.signaturePlacements.count == 3)
}

// MARK: Deleting saved profiles

@Test func deleteConfirmationNamesTheProfileKind() {
    #expect(StampWorkflow.deleteMenuTitle(.initials) == "Delete Saved Initials…")
    #expect(StampWorkflow.deleteMenuTitle(.signature) == "Delete Saved Signature…")
    #expect(StampWorkflow.deleteAlertTitle(.initials) == "Delete your saved initials?")
    #expect(StampWorkflow.deleteAlertMessage(.initials)
        == "They will be removed from this Mac. Initials already placed in documents are not affected.")
    #expect(StampWorkflow.deleteAlertMessage(.signature)
        == "It will be removed from this Mac. Signatures already placed in documents are not affected.")
}

// MARK: Progress banner purpose

@Test func printProgressSaysPreparingToPrint() {
    let rendering = ExportProgress(completedPages: 2, totalPages: 5)
    let writing = ExportProgress(completedPages: 5, totalPages: 5, stage: .writing)
    #expect(ExportPurpose.print.text(for: rendering) == "Preparing to print… 2 of 5 pages")
    #expect(ExportPurpose.print.text(for: writing) == "Preparing to print…")
    #expect(ExportPurpose.print.title == "Preparing to print")
    #expect(ExportPurpose.signedCopy.text(for: rendering) == rendering.text)
    #expect(ExportPurpose.signedCopy.title == "Saving signed copy")
}

// MARK: One unlock surface

@MainActor
@Test func lockedDocumentIsNeverHandedToPDFKit() throws {
    let source = try #require(PDFDocument(data: makeBlankPDF(pages: 1)))
    let data = try #require(source.dataRepresentation(options: [
        PDFDocumentWriteOption.userPasswordOption: "reader", PDFDocumentWriteOption.ownerPasswordOption: "owner",
    ]))
    let locked = try #require(PDFDocument(data: data))
    #expect(locked.isLocked)
    // Before the window has attached protection, the document's own lock state decides.
    #expect(PDFContentView.documentForPageView(locked, protection: nil) == nil)

    let protection = DocumentProtection(document: locked)
    #expect(PDFContentView.documentForPageView(locked, protection: protection) == nil)
    #expect(protection.unlock(withPassword: "reader"))
    #expect(PDFContentView.documentForPageView(locked, protection: protection) === locked)
}

@MainActor
@Test func unlockSheetReportsAWrongPasswordAndAcceptsTheRightOne() throws {
    let source = try #require(PDFDocument(data: makeBlankPDF(pages: 1)))
    let data = try #require(source.dataRepresentation(options: [
        PDFDocumentWriteOption.userPasswordOption: "reader", PDFDocumentWriteOption.ownerPasswordOption: "owner",
    ]))
    let protection = try DocumentProtection(document: #require(PDFDocument(data: data)))

    #expect(UnlockDocumentSheet.attempt("wrong", with: protection) == "Incorrect password. Try again.")
    #expect(protection.isLocked)
    #expect(UnlockDocumentSheet.attempt("reader", with: protection) == nil)
    #expect(!protection.isLocked)
}

// MARK: Focus on open

@MainActor
@Test func documentTakesKeyboardFocusOnceItIsShown() async throws {
    let document = try #require(PDFDocument(data: makeBlankPDF(pages: 2)))
    let viewer = PDFViewerProxy()
    var representable = makeRepresentable()
    representable.viewer = viewer
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    viewer.bind(pdfView, coordinator: coordinator)

    let field = NSTextField(frame: CGRect(x: 0, y: 600, width: 100, height: 20))
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 620))
    container.addSubview(pdfView)
    container.addSubview(field)
    let window = NSWindow(contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = container
    window.makeFirstResponder(field)

    // Locked or not yet loaded: nothing to focus, so the request waits.
    try await Task.sleep(for: .milliseconds(20))
    #expect(window.firstResponder !== pdfView)

    pdfView.document = document
    coordinator.documentDidChange(document)
    for _ in 0 ..< 50 where window.firstResponder !== pdfView {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(window.firstResponder === pdfView)

    // Only once: later document updates leave focus where the user put it.
    window.makeFirstResponder(field)
    coordinator.documentDidChange(document)
    try await Task.sleep(for: .milliseconds(30))
    #expect(window.firstResponder !== pdfView)
}

// MARK: Selected stamp keys

@MainActor
private func arrowEvent(_ key: Int, modifiers: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
    let character = try String(#require(UnicodeScalar(key)).description)
    return try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers.union([.numericPad, .function]),
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: key == NSDownArrowFunctionKey ? 125 : 126
    ))
}

@MainActor
@Test func selectedStampLeavesOptionArrowsToPageNavigation() throws {
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    let window = NSWindow(contentRect: pdfView.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = pdfView
    window.makeFirstResponder(pdfView)
    var handled: [NSEvent.ModifierFlags] = []
    pdfView.hasSelectedStamp = { true }
    pdfView.keyHandler = { event in
        handled.append(event.modifierFlags.intersection([.shift, .option]))
        return true
    }
    let move = try arrowEvent(NSDownArrowFunctionKey, modifiers: [], in: window)
    let bigMove = try arrowEvent(NSUpArrowFunctionKey, modifiers: [.shift], in: window)
    let resize = try arrowEvent(NSUpArrowFunctionKey, modifiers: [.shift, .option], in: window)
    let nextPage = try arrowEvent(NSDownArrowFunctionKey, modifiers: [.option], in: window)

    #expect(pdfView.performKeyEquivalent(with: move))
    #expect(pdfView.performKeyEquivalent(with: bigMove))
    #expect(pdfView.performKeyEquivalent(with: resize))
    _ = pdfView.performKeyEquivalent(with: nextPage)
    #expect(handled == [[], [.shift], [.shift, .option]])

    // With nothing selected the arrows are never claimed.
    pdfView.hasSelectedStamp = { false }
    #expect(!pdfView.performKeyEquivalent(with: move))
    #expect(handled.count == 3)
}

@Test func placementAnnouncementSaysHowToMoveAndFinish() {
    let text = StampAccessibility.placedAnnouncement(pageIndex: 1, location: "at center", kind: .initials)
    #expect(text == "Initials placed on page 2, at center. Arrow keys move it, Escape when done.")
    #expect(!StampAccessibility.moveInstructions(for: .signature).contains("Option moves"))
    #expect(StampAccessibility.moveInstructions(for: .signature).contains("Option-Shift"))
}

// MARK: Saved banner

@Test func escapeClosesTheSavedBannerWhenNothingNewerIsOpen() {
    #expect(SigningFlowLogic.escapeAction(
        isExporting: false, isSigning: false, isFindVisible: false, hasSelection: false, isSavedBannerVisible: true
    ) == .closeSavedBanner)
    // A selected stamp or the Find bar is closer at hand, so it goes first.
    #expect(SigningFlowLogic.escapeAction(
        isExporting: false, isSigning: false, isFindVisible: false, hasSelection: true, isSavedBannerVisible: true
    ) == .deselect)
    #expect(SigningFlowLogic.escapeAction(
        isExporting: false, isSigning: false, isFindVisible: true, hasSelection: false, isSavedBannerVisible: true
    ) == .closeFind)
}

@MainActor
@Test func escapeInTheDocumentReachesTheSavedBanner() throws {
    var escapes = 0
    var representable = makeRepresentable()
    representable.isShowingSavedBanner = true
    representable.onEscape = { escapes += 1 }
    let coordinator = representable.makeCoordinator()
    let escape = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1B}",
        charactersIgnoringModifiers: "\u{1B}",
        isARepeat: false,
        keyCode: 53
    ))
    #expect(coordinator.handleKey(escape))
    #expect(escapes == 1)
}

@Test func shareAndShowInFinderHaveTheirOwnShortcuts() {
    let chords = MenuShortcuts.appSpecific.map(MenuShortcuts.Chord.init)
    #expect(chords.contains(MenuShortcuts.Chord(MenuShortcuts.shareSignedCopy)))
    #expect(chords.contains(MenuShortcuts.Chord(MenuShortcuts.showSignedCopyInFinder)))
}

// MARK: Low vision

/// WCAG contrast ratio of an opaque colour against a white page.
private func contrastOnWhite(_ color: NSColor) throws -> CGFloat {
    let rgb = try #require(color.usingColorSpace(.sRGB))
    func linear(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
        + 0.0722 * linear(rgb.blueComponent)
    return 1.05 / (luminance + 0.05)
}

@Test func increaseContrastThickensAndDarkensOverlayMarks() throws {
    let standard = OverlayStyle(increaseContrast: false)
    let increased = OverlayStyle(increaseContrast: true)
    #expect(increased.fieldLineWidth > standard.fieldLineWidth)
    #expect(increased.selectionLineWidth > standard.selectionLineWidth)
    #expect(increased.handleLineWidth > standard.handleLineWidth)
    // Even with the lightest accent, outlines keep 3:1 normally and 4.5:1 with Increase Contrast.
    #expect(try contrastOnWhite(standard.strokeColor(accent: .systemYellow)) >= 3)
    #expect(try contrastOnWhite(increased.strokeColor(accent: .systemYellow)) >= 4.5)
}

@Test func signToolbarStateIsSpokenAndNotOnlyColoured() {
    #expect(StampWorkflow.signToolbarValue(mode: .idle) == "Not signing")
    #expect(StampWorkflow.signToolbarValue(mode: .freePlacement) == "Signing")
    let idle = StampWorkflow.signToolbarSymbol(mode: .idle)
    let signing = StampWorkflow.signToolbarSymbol(mode: .fieldPlacement)
    #expect(idle != signing)
    #expect(NSImage(systemSymbolName: idle, accessibilityDescription: nil) != nil)
    #expect(NSImage(systemSymbolName: signing, accessibilityDescription: nil) != nil)
}
