import AppKit
@preconcurrency import Quartz

@MainActor
protocol PageOverlayViewDelegate: AnyObject {
    func overlay(_ overlay: PageOverlayView, didClickToSignAt point: CGPoint)
    func overlay(_ overlay: PageOverlayView, didSelect id: UUID?)
    func overlay(_ overlay: PageOverlayView, didChange id: UUID, to bounds: CGRect, actionName: String)
    func overlay(_ overlay: PageOverlayView, didDelete id: UUID)
    func overlayDidRequestStopSigning(_ overlay: PageOverlayView)
    /// VoiceOver's Move action: select the stamp and explain the arrow keys.
    func overlay(_ overlay: PageOverlayView, didRequestMove id: UUID)
}

/// The one-item context menu shown on the document while signing.
@MainActor
enum StopSigningMenu {
    private final class Target: NSObject {
        let action: () -> Void

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        @objc
        func run(_: Any?) {
            action()
        }
    }

    static func make(_ action: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        let target = Target(action)
        let item = NSMenuItem(title: "Stop Signing", action: #selector(Target.run(_:)), keyEquivalent: "")
        item.target = target
        // NSMenuItem holds its target weakly; the represented object keeps it alive with the menu.
        item.representedObject = target
        menu.addItem(item)
        return menu
    }
}

/// Draws one page's signature stamps, detected signature fields and the hover ghost, and handles
/// selecting, moving and resizing stamps. PDFKit sizes and rotates this view with its page, so
/// drawing in page space keeps everything aligned at any zoom or rotation.
///
/// Hit-testing decides who gets the mouse: while signing the whole page belongs to this view; when
/// idle only stamps do, and every other event goes to PDFKit untouched.
@MainActor
final class PageOverlayView: NSView {
    struct Stamp {
        let id: UUID
        let bounds: CGRect
        let image: CGImage
        /// What VoiceOver reads for this stamp, e.g. "Signature by Jane Doe, page 2, in field Buyer".
        var accessibilityLabel = ""
    }

    struct Content {
        var cropBox: CGRect = .zero
        var stamps: [Stamp] = []
        var selectedID: UUID?
        var signingMode: SigningMode = .idle
        /// Signature fields to outline; empty unless signing.
        var fields: [CGRect] = []
        var ghostImage: CGImage?
    }

    private enum DragTarget {
        case move(Stamp)
        case resize(Stamp, PlacementGeometry.Corner)

        var stamp: Stamp {
            switch self {
            case let .move(stamp), let .resize(stamp, _): stamp
            }
        }
    }

    /// Handle edge length in screen points.
    static let handleSize: CGFloat = 7

    private(set) weak var page: PDFPage?
    weak var delegate: PageOverlayViewDelegate?

    var content = Content() {
        didSet {
            if content.signingMode == .idle {
                ghostRect = nil
            }
            needsDisplay = true
            let summary = content.stamps.map { "\($0.id) \($0.accessibilityLabel)" }
            if summary != oldValue.stamps.map({ "\($0.id) \($0.accessibilityLabel)" }) {
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }
    }

    private var ghostRect: CGRect?
    private var stampElements: [UUID: StampAccessibilityElement] = [:]
    private var liveBounds: (id: UUID, bounds: CGRect)?

    init(page: PDFPage?) {
        self.page = page
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Geometry

    /// Overlay-local coordinates are the crop box, shifted to the origin and scaled to the view.
    private var pageToLocal: CGAffineTransform {
        let crop = content.cropBox
        guard crop.width > 0, crop.height > 0 else { return .identity }
        return CGAffineTransform(scaleX: bounds.width / crop.width, y: bounds.height / crop.height)
            .translatedBy(x: -crop.minX, y: -crop.minY)
    }

    /// Length of one screen point in page units, so outlines and handles keep their size when zoomed.
    private var onePoint: CGFloat {
        guard window != nil else { return 1 }
        let origin = convert(CGPoint.zero, to: nil)
        let unit = convert(CGPoint(x: 1, y: 0), to: nil)
        let screenPerLocal = hypot(unit.x - origin.x, unit.y - origin.y)
        let localPerPage = content.cropBox.width > 0 ? bounds.width / content.cropBox.width : 1
        return 1 / max(screenPerLocal * localPerPage, 0.0001)
    }

    private func pagePoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil).applying(pageToLocal.inverted())
    }

    private func currentBounds(of stamp: Stamp) -> CGRect {
        if let liveBounds, liveBounds.id == stamp.id {
            return liveBounds.bounds
        }
        return stamp.bounds
    }

    private func target(at point: CGPoint) -> DragTarget? {
        let tolerance = Self.handleSize * onePoint
        let selected = content.stamps.first { $0.id == content.selectedID }
        if let selected, let corner = PlacementGeometry.corner(of: selected.bounds, near: point, tolerance: tolerance) {
            return .resize(selected, corner)
        }
        return content.stamps.last { $0.bounds.contains(point) }.map(DragTarget.move)
    }

    private func ghostRect(at point: CGPoint) -> CGRect? {
        guard let image = content.ghostImage else { return nil }
        let imageSize = CGSize(width: image.width, height: image.height)
        if let field = content.fields.first(where: { $0.contains(point) }) {
            return PlacementGeometry.aspectFit(
                imageSize: imageSize,
                in: PlacementGeometry.clamped(field, to: content.cropBox)
            )
        }
        guard content.signingMode == .freePlacement else { return nil }
        return PlacementGeometry.defaultRect(centeredAt: point, imageSize: imageSize, pageBounds: content.cropBox)
    }

    // MARK: Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.concatenate(pageToLocal)
        let point = onePoint

        for field in content.fields {
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor)
            context.fill(field)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2 * point)
            context.stroke(field.insetBy(dx: point, dy: point))
        }

        for stamp in content.stamps {
            context.draw(stamp.image, in: currentBounds(of: stamp))
        }

        if let ghostRect, let ghostImage = content.ghostImage {
            context.setAlpha(0.5)
            context.draw(ghostImage, in: ghostRect)
            context.setAlpha(1)
        }

        if let selected = content.stamps.first(where: { $0.id == content.selectedID }) {
            drawSelection(around: currentBounds(of: selected), in: context, onePoint: point)
        }

        context.restoreGState()
    }

    private func drawSelection(around rect: CGRect, in context: CGContext, onePoint point: CGFloat) {
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(point)
        context.stroke(rect)

        let handle = Self.handleSize * point
        for corner in PlacementGeometry.Corner.allCases {
            let center = corner.point(in: rect)
            let square = CGRect(x: center.x - handle / 2, y: center.y - handle / 2, width: handle, height: handle)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(square)
            context.stroke(square)
        }
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if content.signingMode != .idle {
            return self
        }
        return target(at: local.applying(pageToLocal.inverted())) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        if content.signingMode != .idle {
            trackSigningClick(startingWith: event)
        } else if let target = target(at: pagePoint(for: event)) {
            trackDrag(of: target, startingWith: event)
        }
    }

    /// Places a stamp only for a click; a press that moves past the threshold is consumed.
    private func trackSigningClick(startingWith event: NSEvent) {
        let start = event.locationInWindow
        let pagePoint = pagePoint(for: event)
        var isClick = true
        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { next, stop in
            guard let next else {
                stop.pointee = true
                return
            }
            isClick = isClick && PlacementGeometry.isClick(from: start, to: next.locationInWindow)
            if next.type == .leftMouseUp {
                stop.pointee = true
            }
        }
        if isClick {
            delegate?.overlay(self, didClickToSignAt: pagePoint)
        }
    }

    private func trackDrag(of target: DragTarget, startingWith event: NSEvent) {
        let stamp = target.stamp
        let start = event.locationInWindow
        let startPage = pagePoint(for: event)
        var hasMoved = false
        var latest = stamp.bounds
        delegate?.overlay(self, didSelect: stamp.id)

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { next, stop in
            guard let next else {
                stop.pointee = true
                return
            }
            hasMoved = hasMoved || !PlacementGeometry.isClick(from: start, to: next.locationInWindow)
            if hasMoved {
                latest = draggedBounds(of: target, from: startPage, to: pagePoint(for: next))
                liveBounds = (stamp.id, latest)
                needsDisplay = true
            }
            if next.type == .leftMouseUp {
                stop.pointee = true
            }
        }

        liveBounds = nil
        needsDisplay = true
        guard latest != stamp.bounds else { return }
        let actionName = if case .resize = target {
            "Resize Signature"
        } else {
            "Move Signature"
        }
        delegate?.overlay(self, didChange: stamp.id, to: latest, actionName: actionName)
    }

    private func draggedBounds(of target: DragTarget, from start: CGPoint, to point: CGPoint) -> CGRect {
        switch target {
        case let .move(stamp):
            PlacementGeometry.moved(
                stamp.bounds,
                by: CGVector(dx: point.x - start.x, dy: point.y - start.y),
                within: content.cropBox
            )
        case let .resize(stamp, corner):
            PlacementGeometry.resized(stamp.bounds, dragging: corner, to: point, within: content.cropBox)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if content.signingMode != .idle {
            return StopSigningMenu.make { [weak self] in
                guard let self else { return }
                delegate?.overlayDidRequestStopSigning(self)
            }
        }
        guard let stamp = target(at: pagePoint(for: event))?.stamp else {
            return nil
        }
        delegate?.overlay(self, didSelect: stamp.id)

        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Remove Signature from Page",
            action: #selector(deleteFromMenu(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = stamp.id
        menu.addItem(item)
        return menu
    }

    @objc
    private func deleteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        delegate?.overlay(self, didDelete: id)
    }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        let ids = Set(content.stamps.map(\.id))
        stampElements = stampElements.filter { ids.contains($0.key) }
        return content.stamps.map { stamp in
            let element = stampElements[stamp.id] ?? StampAccessibilityElement(stampID: stamp.id, overlay: self)
            element.setAccessibilityLabel(stamp.accessibilityLabel)
            stampElements[stamp.id] = element
            return element
        }
    }

    func screenFrame(ofStamp id: UUID) -> NSRect {
        guard let stamp = content.stamps.first(where: { $0.id == id }), let window else { return .zero }
        let local = currentBounds(of: stamp).applying(pageToLocal)
        return window.convertToScreen(convert(local, to: nil))
    }

    func selectStampFromAccessibility(_ id: UUID) {
        delegate?.overlay(self, didSelect: id)
    }

    func removeStampFromAccessibility(_ id: UUID) {
        delegate?.overlay(self, didDelete: id)
    }

    func moveStampFromAccessibility(_ id: UUID) {
        delegate?.overlay(self, didRequestMove: id)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard content.signingMode != .idle else { return }
        NSCursor.crosshair.set()
        ghostRect = ghostRect(at: pagePoint(for: event))
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        guard ghostRect != nil else { return }
        ghostRect = nil
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        if content.signingMode != .idle {
            NSCursor.crosshair.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}
