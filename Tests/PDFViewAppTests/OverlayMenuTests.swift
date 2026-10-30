import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
final class RecordingOverlayDelegate: PageOverlayViewDelegate {
    var stopRequests = 0
    var deleted: [UUID] = []
    var selected: [UUID?] = []
    var changes: [(UUID, CGRect, String)] = []

    func overlay(_: PageOverlayView, didClickToSignAt _: CGPoint) {}
    func overlay(_: PageOverlayView, didSelect id: UUID?) {
        selected.append(id)
    }

    func overlay(_: PageOverlayView, didChange id: UUID, to bounds: CGRect, actionName: String) {
        changes.append((id, bounds, actionName))
    }

    func overlay(_: PageOverlayView, didDelete id: UUID) {
        deleted.append(id)
    }

    func overlayDidRequestStopSigning(_: PageOverlayView) {
        stopRequests += 1
    }
}

@MainActor
private func rightClick(at point: CGPoint) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: .rightMouseDown,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    ))
}

@MainActor
private func perform(_ item: NSMenuItem) {
    if let action = item.action, let target = item.target as? NSObject {
        _ = target.perform(action, with: item)
    }
}

@MainActor
@Test func rightClickWhileSigningOffersStopSigning() throws {
    let delegate = RecordingOverlayDelegate()
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
    overlay.delegate = delegate
    overlay.content = PageOverlayView.Content(cropBox: overlay.frame, signingMode: .freePlacement)

    let menu = try #require(overlay.menu(for: rightClick(at: CGPoint(x: 150, y: 200))))
    #expect(menu.items.map(\.title) == ["Stop Signing"])
    perform(menu.items[0])
    #expect(delegate.stopRequests == 1)
}

@MainActor
@Test func stampContextMenuRemovesTheSignatureFromThePage() throws {
    let delegate = RecordingOverlayDelegate()
    let overlay = PageOverlayView(page: nil)
    overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
    overlay.delegate = delegate
    let stamp = try PageOverlayView.Stamp(
        id: UUID(),
        bounds: CGRect(x: 100, y: 100, width: 60, height: 20),
        image: blackPixel()
    )
    overlay.content = PageOverlayView.Content(cropBox: overlay.frame, stamps: [stamp])

    let menu = try #require(overlay.menu(for: rightClick(at: CGPoint(x: 120, y: 110))))
    #expect(menu.items.map(\.title) == ["Remove Signature from Page"])
    perform(menu.items[0])
    #expect(delegate.deleted == [stamp.id])
}

func blackPixel() throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    return try #require(context.makeImage())
}
