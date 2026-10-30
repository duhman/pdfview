import AppKit
@preconcurrency import Quartz
import SwiftUI

/// How the document is scaled. Fit follows the window size; manual holds a fixed scale.
/// Keeping these apart stops an auto-fit scale (e.g. 1.6129) from being mistaken for a user zoom.
enum ZoomState: Equatable {
    case fit
    case manual(CGFloat)

    static let minimumScale: CGFloat = 0.25
    static let maximumScale: CGFloat = 5.0
    static let step: CGFloat = 1.25
    static let actualSize = ZoomState.manual(1)

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func zoomedIn(from displayedScale: CGFloat) -> ZoomState {
        .manual(clampedScale(displayedScale * step))
    }

    static func zoomedOut(from displayedScale: CGFloat) -> ZoomState {
        .manual(clampedScale(displayedScale / step))
    }

    /// PDFKit leaves `autoScales` on while it fits the page and turns it off when the user
    /// zooms with a gesture or its own zoom actions, so that flag tells the two apart.
    func observing(scale: CGFloat, autoScales: Bool) -> ZoomState {
        autoScales ? self : .manual(Self.clampedScale(scale))
    }
}

/// Gives the window's SwiftUI content access to the live PDFView for commands that need the
/// current page, scale, or window.
@MainActor
final class PDFViewerProxy {
    fileprivate weak var pdfView: SigningPDFView?
    fileprivate weak var coordinator: PDFKitView.Coordinator?

    var window: NSWindow? {
        pdfView?.window
    }

    var displayedScale: CGFloat {
        pdfView?.scaleFactor ?? 1
    }

    var currentPageIndex: Int? {
        guard let pdfView, let page = pdfView.currentPage, let document = pdfView.document else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }

    func reveal(_ rect: CGRect, onPageAt pageIndex: Int) {
        guard let pdfView, let page = pdfView.document?.page(at: pageIndex) else { return }
        pdfView.go(to: rect.insetBy(dx: -40, dy: -40), on: page)
    }

    /// Selects a stamp and gives the PDF view keyboard focus so arrow keys nudge it.
    func select(placementID: UUID?) {
        coordinator?.selectedPlacementID = placementID
        if let pdfView, placementID != nil {
            pdfView.window?.makeFirstResponder(pdfView)
        }
    }
}

/// NSViewRepresentable wrapper for PDFKit's PDFView.
/// Signature stamps are drawn by per-page overlay views so they scroll, zoom and rotate with the page.
@MainActor
struct PDFKitView: NSViewRepresentable {
    struct DocumentState: Equatable {
        var signatureFields: [SignatureField]
        var isLocked: Bool
    }

    var document: PDFDocument?
    var signaturePlacements: [PDFViewerDocument.SignaturePlacement]
    @Binding var zoom: ZoomState
    var signingMode: SigningMode
    var signatureProfile: SignatureProfile?
    var viewer: PDFViewerProxy
    var reader: ReaderController
    var fileURL: URL?
    var onEscape: () -> Void
    var isExporting: Bool

    /// The window hosting the PDF view, reported whenever it is (re)attached.
    var onWindow: (NSWindow) -> Void
    /// A signing click resolved to page-space bounds on a page.
    var onPlaceSignature: (_ pageIndex: Int, _ bounds: CGRect) -> Void
    var onUpdatePlacementBounds: (_ id: UUID, _ bounds: CGRect, _ actionName: String) -> Void
    var onDeletePlacement: (UUID) -> Void
    /// Fields and lock state, reported when the document changes or unlocks.
    var onDocumentStateChange: (DocumentState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SigningPDFView {
        let pdfView = SigningPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.pageShadowsEnabled = true
        pdfView.minScaleFactor = ZoomState.minimumScale
        pdfView.maxScaleFactor = ZoomState.maximumScale
        context.coordinator.attach(to: pdfView)
        return pdfView
    }

    func updateNSView(_ nsView: SigningPDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        viewer.pdfView = nsView
        viewer.coordinator = coordinator

        // Compare identity before assigning: re-assigning the same document resets PDFKit state.
        if nsView.document !== document {
            nsView.document = document
            coordinator.documentDidChange(document)
        }

        // Publish reader state after SwiftUI has finished this representable update.
        DispatchQueue.main.async { [weak nsView, weak reader] in
            guard let nsView, nsView.document === document else { return }
            reader?.attach(to: nsView, fileURL: fileURL)
        }
        coordinator.apply(zoom, to: nsView)
        coordinator.refreshOverlays()
        if let window = nsView.window {
            onWindow(window)
        }
    }

    static func dismantleNSView(_ nsView: SigningPDFView, coordinator: Coordinator) {
        coordinator.parent.reader.detach()
        nsView.pageOverlayViewProvider = nil
    }
}

extension PDFKitView {
    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitView
        private weak var pdfView: SigningPDFView?
        private var isApplyingZoom = false
        private var overlays: [ObjectIdentifier: PageOverlayView] = [:]
        private var imageCache: [UUID: CGImage] = [:]
        private var profileImageCache: (data: Data, image: CGImage?)?
        private var signatureFields: [SignatureField] = []

        var selectedPlacementID: UUID? {
            didSet { refreshOverlays() }
        }

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        func attach(to pdfView: SigningPDFView) {
            self.pdfView = pdfView
            pdfView.pageOverlayViewProvider = self
            pdfView.isSigning = { [weak self] in self?.parent.signingMode != .idle }
            pdfView.onIdleMouseDown = { [weak self] in self?.selectedPlacementID = nil }
            pdfView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
            pdfView.onWindowChange = { [weak self] window in self?.parent.onWindow(window) }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScaleChanged(_:)),
                name: .PDFViewScaleChanged,
                object: pdfView
            )
        }

        // MARK: Document

        func documentDidChange(_ document: PDFDocument?) {
            NotificationCenter.default.removeObserver(self, name: .PDFDocumentDidUnlock, object: nil)
            selectedPlacementID = nil

            if let document {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleDocumentUnlocked(_:)),
                    name: .PDFDocumentDidUnlock,
                    object: document
                )
            }
            rescanDocument()
        }

        @objc
        private func handleDocumentUnlocked(_: Notification) {
            rescanDocument()
        }

        private func rescanDocument() {
            let document = pdfView?.document
            signatureFields = document.map(SigningFlowLogic.signatureFields) ?? []
            let state = DocumentState(signatureFields: signatureFields, isLocked: document?.isLocked ?? false)
            // Reported asynchronously: this can run inside a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in
                self?.parent.onDocumentStateChange(state)
                self?.refreshOverlays()
            }
        }

        // MARK: Zoom

        func apply(_ zoom: ZoomState, to pdfView: PDFView) {
            isApplyingZoom = true
            defer { isApplyingZoom = false }

            switch zoom {
            case .fit:
                if !pdfView.autoScales {
                    pdfView.autoScales = true
                }
            case let .manual(scale):
                if pdfView.autoScales {
                    pdfView.autoScales = false
                }
                if abs(pdfView.scaleFactor - scale) > 0.0001 {
                    pdfView.scaleFactor = scale
                }
            }
        }

        @objc
        private func handleScaleChanged(_: Notification) {
            guard !isApplyingZoom, let pdfView else { return }
            let observed = parent.zoom.observing(scale: pdfView.scaleFactor, autoScales: pdfView.autoScales)
            if observed != parent.zoom {
                parent.zoom = observed
            }
        }

        // MARK: Overlays

        func refreshOverlays() {
            for overlay in overlays.values {
                overlay.content = content(for: overlay.page)
            }
        }

        private func content(for page: PDFPage?) -> PageOverlayView.Content {
            guard let page, let pageIndex = index(of: page) else { return PageOverlayView.Content() }

            let stamps = parent.signaturePlacements
                .filter { $0.pageIndex == pageIndex }
                .compactMap { placement -> PageOverlayView.Stamp? in
                    guard let image = image(for: placement) else { return nil }
                    return PageOverlayView.Stamp(id: placement.id, bounds: placement.bounds, image: image)
                }
            let isSigning = parent.signingMode != .idle

            return PageOverlayView.Content(
                cropBox: page.bounds(for: .cropBox),
                stamps: stamps,
                selectedID: selectedPlacementID,
                signingMode: parent.signingMode,
                fields: isSigning ? signatureFields.filter { $0.pageIndex == pageIndex }.map(\.bounds) : [],
                ghostImage: isSigning ? profileImage() : nil
            )
        }

        private func index(of page: PDFPage) -> Int? {
            guard let index = pdfView?.document?.index(for: page), index != NSNotFound else { return nil }
            return index
        }

        private func image(for placement: PDFViewerDocument.SignaturePlacement) -> CGImage? {
            if let cached = imageCache[placement.id] {
                return cached
            }
            let image = NSImage(data: placement.signaturePNGData)?.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
            imageCache[placement.id] = image
            return image
        }

        /// Keyed by the PNG bytes, not the profile id: editing a signature keeps its id.
        private func profileImage() -> CGImage? {
            guard let data = parent.signatureProfile?.signaturePNGData else { return nil }
            if let profileImageCache, profileImageCache.data == data {
                return profileImageCache.image
            }
            let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            profileImageCache = (data, image)
            return image
        }

        fileprivate func makeOverlay(for page: PDFPage) -> PageOverlayView {
            let overlay = PageOverlayView(page: page)
            overlay.delegate = self
            overlay.content = content(for: page)
            overlays[ObjectIdentifier(page)] = overlay
            return overlay
        }

        fileprivate func removeOverlay(for page: PDFPage) {
            overlays[ObjectIdentifier(page)] = nil
        }

        // MARK: Keyboard

        private var isHandlingEscape: Bool {
            parent.isExporting || parent.signingMode != .idle || parent.reader.find.isVisible
        }

        private func handleKey(_ event: NSEvent) -> Bool {
            if event.keyCode == 53 {
                if isHandlingEscape {
                    parent.onEscape()
                    return true
                }
                if selectedPlacementID != nil {
                    selectedPlacementID = nil
                    return true
                }
                return false
            }

            guard let selectedID = selectedPlacementID,
                  let placement = parent.signaturePlacements.first(where: { $0.id == selectedID })
            else {
                return false
            }

            switch event.specialKey {
            case .delete?, .deleteForward?:
                selectedPlacementID = nil
                parent.onDeletePlacement(selectedID)
                return true
            case .leftArrow?, .rightArrow?, .upArrow?, .downArrow?:
                nudge(placement, key: event.specialKey, by: event.modifierFlags.contains(.shift) ? 10 : 1)
                return true
            default:
                return false
            }
        }

        /// Moves the stamp in the on-screen direction of the arrow key, whatever the page rotation.
        private func nudge(
            _ placement: PDFViewerDocument.SignaturePlacement,
            key: NSEvent.SpecialKey?,
            by distance: CGFloat
        ) {
            guard let pdfView, let page = pdfView.document?.page(at: placement.pageIndex) else { return }

            let screenUp: CGFloat = pdfView.isFlipped ? -1 : 1
            let screenVector = switch key {
            case .leftArrow?: CGVector(dx: -1, dy: 0)
            case .rightArrow?: CGVector(dx: 1, dy: 0)
            case .upArrow?: CGVector(dx: 0, dy: screenUp)
            default: CGVector(dx: 0, dy: -screenUp)
            }

            let origin = pdfView.convert(CGPoint.zero, to: page)
            let target = pdfView.convert(CGPoint(x: screenVector.dx, y: screenVector.dy), to: page)
            let length = max(hypot(target.x - origin.x, target.y - origin.y), 0.0001)
            let delta = CGVector(
                dx: (target.x - origin.x) / length * distance,
                dy: (target.y - origin.y) / length * distance
            )

            let bounds = PlacementGeometry.moved(placement.bounds, by: delta, within: page.bounds(for: .cropBox))
            parent.onUpdatePlacementBounds(placement.id, bounds, "Move Signature")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

extension PDFKitView.Coordinator: PDFPageOverlayViewProvider {
    nonisolated func pdfView(_: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        MainActor.assumeIsolated {
            makeOverlay(for: page)
        }
    }

    nonisolated func pdfView(_: PDFView, willEndDisplayingOverlayView _: NSView, for page: PDFPage) {
        MainActor.assumeIsolated {
            removeOverlay(for: page)
        }
    }
}

extension PDFKitView.Coordinator: PageOverlayViewDelegate {
    func overlay(_ overlay: PageOverlayView, didClickToSignAt point: CGPoint) {
        guard let page = overlay.page,
              let pageIndex = index(of: page),
              let image = profileImage()
        else {
            return
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        let cropBox = page.bounds(for: .cropBox)
        let bounds: CGRect
        if let field = signatureFields.first(where: { $0.pageIndex == pageIndex && $0.bounds.contains(point) }) {
            bounds = PlacementGeometry.aspectFit(
                imageSize: imageSize,
                in: PlacementGeometry.clamped(field.bounds, to: cropBox)
            )
        } else if parent.signingMode == .freePlacement {
            bounds = PlacementGeometry.defaultRect(centeredAt: point, imageSize: imageSize, pageBounds: cropBox)
        } else {
            NSSound.beep()
            return
        }

        parent.onPlaceSignature(pageIndex, bounds)
    }

    func overlay(_: PageOverlayView, didSelect id: UUID?) {
        selectedPlacementID = id
        if let pdfView {
            pdfView.window?.makeFirstResponder(pdfView)
        }
    }

    func overlay(_: PageOverlayView, didChange id: UUID, to bounds: CGRect, actionName: String) {
        parent.onUpdatePlacementBounds(id, bounds, actionName)
    }

    func overlay(_: PageOverlayView, didDelete id: UUID) {
        selectedPlacementID = nil
        parent.onDeletePlacement(id)
    }
}

@MainActor
final class SigningPDFView: PDFView {
    var isSigning: () -> Bool = { false }
    var onIdleMouseDown: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    var onWindowChange: ((NSWindow) -> Void)?

    /// Clicks that reach the PDF view itself (outside any page overlay) are consumed while signing
    /// and passed to PDFKit untouched otherwise.
    override func mouseDown(with event: NSEvent) {
        guard !isSigning() else { return }
        onIdleMouseDown?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
