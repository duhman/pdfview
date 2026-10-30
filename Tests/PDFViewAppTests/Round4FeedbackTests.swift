import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

// MARK: Transient banner messages

@MainActor
@Test func aNoticeShowsThenClearsItself() async throws {
    let notice = TransientNotice(duration: .milliseconds(40))
    notice.show("Every signature field already has a stamp.")
    #expect(notice.text == "Every signature field already has a stamp.")
    for _ in 0 ..< 50 where notice.text != nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(notice.text == nil)
}

@MainActor
@Test func aNewerNoticeRestartsTheTimer() async throws {
    let notice = TransientNotice(duration: .milliseconds(80))
    notice.show("First")
    try await Task.sleep(for: .milliseconds(50))
    notice.show("Second")
    try await Task.sleep(for: .milliseconds(50))
    // The first notice's timer has passed, but it must not clear the second one.
    #expect(notice.text == "Second")
    notice.dismiss()
    #expect(notice.text == nil)
}

@MainActor
@Test func clickingOutsideAFieldInFieldsModeExplainsInsteadOfBeeping() throws {
    let document = try ExportFixture.document()
    var notices: [String] = []
    var placed = 0
    var representable = makeRepresentable(document: document)
    representable.signingMode = .fieldPlacement
    representable.stampPNGData = try ExportFixture.signature()
    representable.onPlaceSignature = { _, _ in placed += 1 }
    representable.onNotice = { notices.append($0) }
    let coordinator = representable.makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    pdfView.document = document
    let page = try #require(document.page(at: 0))

    coordinator.overlay(PageOverlayView(page: page), didClickToSignAt: CGPoint(x: 200, y: 300))

    #expect(placed == 0)
    #expect(notices == [SigningFlowLogic.clickInsideFieldNotice])
    #expect(SigningFlowLogic.clickInsideFieldNotice == "Click inside a signature field, or choose Anywhere.")
}

// MARK: Cancelled saves

@Test func aCancelledSaveIsReportedInTheBannerNotSilently() {
    #expect(ExportPurpose.signedCopy.feedback(for: CancellationError()) == .notice("Save cancelled."))
    #expect(ExportPurpose.print.feedback(for: CancellationError()) == .notice("Printing cancelled."))
}

@Test func aFailedSaveStillRaisesAnAlert() {
    struct DiskFull: LocalizedError {
        var errorDescription: String? {
            "The disk is full."
        }
    }
    #expect(ExportPurpose.signedCopy.feedback(for: DiskFull())
        == .alert(ErrorAlert(title: "Couldn’t Save Signed Copy", error: DiskFull())))
    #expect(ExportPurpose.print.feedback(for: DiskFull())
        == .alert(ErrorAlert(title: "Couldn’t Print PDF", error: DiskFull())))
}

// MARK: Progress banner delay

@MainActor
@Test func theProgressBannerWaitsBeforeAppearing() async throws {
    let visibility = DelayedVisibility(delay: .milliseconds(40))
    visibility.begin()
    #expect(!visibility.isVisible)
    for _ in 0 ..< 50 where !visibility.isVisible {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(visibility.isVisible)
    visibility.end()
    #expect(!visibility.isVisible)
}

@MainActor
@Test func aSaveThatFinishesQuicklyNeverShowsTheProgressBanner() async throws {
    let visibility = DelayedVisibility(delay: .milliseconds(40))
    visibility.begin()
    try await Task.sleep(for: .milliseconds(10))
    visibility.end()
    try await Task.sleep(for: .milliseconds(80))
    #expect(!visibility.isVisible)
}

@MainActor
@Test func progressAppearsAfterAboutThreeHundredMilliseconds() {
    #expect(DelayedVisibility.progressDelay == .milliseconds(300))
}
