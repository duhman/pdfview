import CoreGraphics
import Testing
@testable import PDFViewApp

@Test func autoFitScaleChangesKeepFitState() {
    // PDFKit reports 1.6129 while auto-scaling; that must not turn fit into a manual zoom.
    #expect(ZoomState.fit.observing(scale: 1.6129, autoScales: true) == .fit)
}

@Test func userZoomWhileFittingSwitchesToManual() {
    #expect(ZoomState.fit.observing(scale: 2.4, autoScales: false) == .manual(2.4))
}

@Test func manualZoomFollowsUserGestures() {
    #expect(ZoomState.manual(1.5).observing(scale: 1.8, autoScales: false) == .manual(1.8))
}

@Test func observedScaleIsClamped() {
    #expect(ZoomState.fit.observing(scale: 9, autoScales: false) == .manual(ZoomState.maximumScale))
}

@Test func actualSizeIsDistinctFromFit() {
    #expect(ZoomState.actualSize == .manual(1))
    #expect(ZoomState.actualSize != .fit)
}

@Test func zoomStepsAreRelativeToDisplayedScale() {
    #expect(ZoomState.zoomedIn(from: 1.6) == .manual(2.0))
    #expect(ZoomState.zoomedOut(from: 2.0) == .manual(1.6))
}

@Test func zoomStepsStopAtLimits() {
    #expect(ZoomState.zoomedIn(from: 4.8) == .manual(ZoomState.maximumScale))
    #expect(ZoomState.zoomedOut(from: 0.26) == .manual(ZoomState.minimumScale))
}
