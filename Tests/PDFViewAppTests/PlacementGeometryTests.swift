import AppKit
import CoreGraphics
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

private func isClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance
        && abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance
}

@Test func aspectFitInWideFieldIsHeightLimitedAndBottomLeftAligned() {
    let field = CGRect(x: 100, y: 200, width: 220, height: 50)
    let fitted = PlacementGeometry.aspectFit(imageSize: CGSize(width: 700, height: 220), in: field)

    // 46pt of usable height (2pt inset) at the image's 3.18 aspect ratio.
    let expectedWidth = 46 * 700 / 220.0
    #expect(isClose(fitted, CGRect(x: 102, y: 202, width: expectedWidth, height: 46)))
    #expect(abs(fitted.width / fitted.height - 700 / 220.0) < 0.0001)
    #expect(field.contains(fitted))
}

@Test func aspectFitInTallFieldIsWidthLimited() {
    let field = CGRect(x: 0, y: 0, width: 104, height: 300)
    let fitted = PlacementGeometry.aspectFit(imageSize: CGSize(width: 400, height: 100), in: field)

    #expect(isClose(fitted, CGRect(x: 2, y: 2, width: 100, height: 25)))
}

@Test func aspectFitFallsBackToFieldForDegenerateImage() {
    let field = CGRect(x: 10, y: 10, width: 220, height: 50)
    let fitted = PlacementGeometry.aspectFit(imageSize: .zero, in: field)

    #expect(isClose(fitted, field.insetBy(dx: 2, dy: 2)))
}

@Test func defaultRectIsCentredOnPointWithImageAspect() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = PlacementGeometry.defaultRect(
        centeredAt: CGPoint(x: 300, y: 400),
        imageSize: CGSize(width: 360, height: 120),
        pageBounds: page
    )

    #expect(isClose(rect, CGRect(x: 210, y: 370, width: 180, height: 60)))
}

@Test func defaultRectIsClampedInsidePageNearCorner() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = PlacementGeometry.defaultRect(
        centeredAt: CGPoint(x: 5, y: 790),
        imageSize: CGSize(width: 360, height: 120),
        pageBounds: page
    )

    #expect(isClose(rect, CGRect(x: 0, y: 732, width: 180, height: 60)))
}

@Test func clampingRespectsOffsetCropBox() {
    let crop = CGRect(x: 50, y: 70, width: 300, height: 400)
    let clamped = PlacementGeometry.clamped(CGRect(x: 0, y: 0, width: 100, height: 40), to: crop)

    #expect(isClose(clamped, CGRect(x: 50, y: 70, width: 100, height: 40)))
}

@Test func clampingShrinksOversizedRectToBounds() {
    let crop = CGRect(x: 0, y: 0, width: 200, height: 100)
    let clamped = PlacementGeometry.clamped(CGRect(x: -50, y: 20, width: 400, height: 40), to: crop)

    #expect(isClose(clamped, CGRect(x: 0, y: 20, width: 200, height: 40)))
}

@Test func clampingOnRotatedPageUsesUnrotatedPageSpace() throws {
    let image = NSImage(size: NSSize(width: 400, height: 600))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 600).fill()
    image.unlockFocus()
    let page = try #require(PDFPage(image: image))
    page.rotation = 90
    page.setBounds(CGRect(x: 50, y: 70, width: 300, height: 400), for: .cropBox)

    // PDFKit reports the crop box in unrotated page space; placements live in the same space.
    let crop = page.bounds(for: .cropBox)
    #expect(isClose(crop, CGRect(x: 50, y: 70, width: 300, height: 400)))

    let clamped = PlacementGeometry.clamped(CGRect(x: 300, y: 450, width: 180, height: 60), to: crop)
    #expect(isClose(clamped, CGRect(x: 170, y: 410, width: 180, height: 60)))
    #expect(crop.contains(clamped))
}

@Test func moveKeepsSizeAndStaysInsideBounds() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = CGRect(x: 10, y: 10, width: 180, height: 60)

    let moved = PlacementGeometry.moved(rect, by: CGVector(dx: 100, dy: 50), within: page)
    #expect(isClose(moved, CGRect(x: 110, y: 60, width: 180, height: 60)))

    let pushedOff = PlacementGeometry.moved(rect, by: CGVector(dx: -100, dy: 900), within: page)
    #expect(isClose(pushedOff, CGRect(x: 0, y: 732, width: 180, height: 60)))
}

@Test func resizeFromTopRightKeepsAspectAndAnchorsBottomLeft() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = CGRect(x: 100, y: 100, width: 180, height: 60)

    let resized = PlacementGeometry.resized(rect, dragging: .topRight, to: CGPoint(x: 460, y: 130), within: page)

    #expect(isClose(resized, CGRect(x: 100, y: 100, width: 360, height: 120)))
}

@Test func resizeFromBottomLeftAnchorsTopRight() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = CGRect(x: 100, y: 100, width: 180, height: 60)

    let resized = PlacementGeometry.resized(rect, dragging: .bottomLeft, to: CGPoint(x: 190, y: 150), within: page)

    #expect(isClose(resized, CGRect(x: 190, y: 130, width: 90, height: 30)))
}

@Test func resizeNeverGoesBelowMinimumWidthOrOutsidePage() {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let rect = CGRect(x: 100, y: 100, width: 180, height: 60)

    let tiny = PlacementGeometry.resized(rect, dragging: .topRight, to: CGPoint(x: 101, y: 101), within: page)
    #expect(abs(tiny.width - PlacementGeometry.minimumWidth) < 0.001)
    #expect(abs(tiny.width / tiny.height - 3) < 0.001)

    let huge = PlacementGeometry.resized(rect, dragging: .topRight, to: CGPoint(x: 900, y: 900), within: page)
    #expect(page.contains(huge))
    #expect(abs(huge.width / huge.height - 3) < 0.001)
    #expect(abs(huge.minX - 100) < 0.001 && abs(huge.minY - 100) < 0.001)
}

@Test func clickThresholdSeparatesClicksFromDrags() {
    let start = CGPoint(x: 100, y: 100)

    #expect(PlacementGeometry.isClick(from: start, to: start))
    #expect(PlacementGeometry.isClick(from: start, to: CGPoint(x: 103, y: 102)))
    #expect(!PlacementGeometry.isClick(from: start, to: CGPoint(x: 104, y: 103)))
    #expect(!PlacementGeometry.isClick(from: start, to: CGPoint(x: 100, y: 140)))
}

@Test func cornerHitTestFindsHandleNearestCorner() {
    let rect = CGRect(x: 100, y: 100, width: 180, height: 60)

    #expect(PlacementGeometry.corner(of: rect, near: CGPoint(x: 281, y: 159), tolerance: 6) == .topRight)
    #expect(PlacementGeometry.corner(of: rect, near: CGPoint(x: 99, y: 101), tolerance: 6) == .bottomLeft)
    #expect(PlacementGeometry.corner(of: rect, near: CGPoint(x: 190, y: 130), tolerance: 6) == nil)
}
