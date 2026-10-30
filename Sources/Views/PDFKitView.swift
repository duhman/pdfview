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
    /// A new window should accept arrow keys and Page Down at once, so focus starts in the document.
    private var focusPending = true

    func bind(_ pdfView: SigningPDFView, coordinator: PDFKitView.Coordinator) {
        self.pdfView = pdfView
        self.coordinator = coordinator
    }

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

    /// Reads the form widgets now, so a close or quit decision sees an edit PDFKit has not reported yet.
    func currentFormValues() -> [FormFieldValue]? {
        coordinator?.formScan?.values()
    }

    /// Reports any form edit PDFKit has made since the last check.
    func refreshFormValues() {
        coordinator?.checkFormValues()
    }

    /// Focuses the document as soon as it has pages on screen, e.g. once an unlock has opened it.
    func focusDocumentWhenShown() {
        focusPending = true
        focusIfPending()
    }

    /// Runs on the next turn, after a dismissed sheet has handed focus back to the window.
    fileprivate func focusIfPending() {
        guard focusPending, let pdfView, pdfView.window != nil, pdfView.document != nil else { return }
        focusPending = false
        DispatchQueue.main.async { [weak pdfView] in
            guard let pdfView, let window = pdfView.window else { return }
            window.makeFirstResponder(pdfView)
        }
    }

    /// Returns keyboard focus to the document, e.g. after a banner or the Find bar closes.
    func focusDocument() {
        guard let pdfView, let window = pdfView.window else { return }
        window.makeFirstResponder(pdfView)
    }

    /// Opens the share menu from the top of the document, for File > Share Signed Copy….
    func showSharingPicker(for url: URL) {
        guard let pdfView else { return }
        let anchor = CGRect(x: pdfView.bounds.midX, y: pdfView.bounds.maxY - 1, width: 1, height: 1)
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor, of: pdfView, preferredEdge: .minY)
    }

    /// Selects a stamp and gives the PDF view keyboard focus so arrow keys nudge it.
    var selectedPlacementID: UUID? {
        coordinator?.selectedPlacementID
    }

    /// The VoiceOver label of a placement as it is now, e.g. for Select Next Stamp.
    func label(for placement: PDFViewerDocument.SignaturePlacement) -> String? {
        coordinator?.label(for: placement, bounds: placement.bounds)
    }

    func location(of bounds: CGRect, onPageAt pageIndex: Int) -> String? {
        coordinator?.location(of: bounds, onPageAt: pageIndex)
    }

    /// Go > Next/Previous Form Field; nil when the document has no form fields.
    func moveToFormField(forward: Bool) -> String? {
        coordinator?.moveToFormField(forward: forward)
    }

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
        /// Nil until the incremental form scan has finished.
        var formValues: [FormFieldValue]?
    }

    /// Everything the page overlays draw from; overlays are rebuilt only when this changes.
    struct OverlayInputs: Equatable {
        var placements: [PDFViewerDocument.SignaturePlacement]
        var signingMode: SigningMode
        var profilePNGData: Data?
        var stampWidth: CGFloat
        var fields: [SignatureField]
    }

    var document: PDFDocument?
    var signaturePlacements: [PDFViewerDocument.SignaturePlacement]
    @Binding var zoom: ZoomState
    var signingMode: SigningMode
    var stampPNGData: Data?
    /// Width of a stamp placed by clicking anywhere on the page, for the active stamp kind.
    var stampWidth: CGFloat = PlacementGeometry.defaultWidth
    var viewer: PDFViewerProxy
    var reader: ReaderController
    var fileURL: URL?
    var onEscape: () -> Void
    /// Stop Signing from the page's context menu.
    var onStopSigning: () -> Void
    var isExporting: Bool
    /// The saved banner is the next thing Escape closes when nothing nearer is open.
    var isShowingSavedBanner = false

    /// The window hosting the PDF view, reported whenever it is (re)attached.
    var onWindow: (NSWindow) -> Void
    /// A signing click resolved to page-space bounds on a page.
    var onPlaceSignature: (_ pageIndex: Int, _ bounds: CGRect) -> Void
    var onUpdatePlacementBounds: (_ id: UUID, _ bounds: CGRect, _ actionName: String) -> Void
    var onDeletePlacement: (UUID) -> Void
    /// Lock state as soon as a document is shown, then fields and form values once scanned.
    var onDocumentStateChange: (DocumentState) -> Void
    /// The user changed a form widget's value.
    var onFormValuesChange: ([FormFieldValue]) -> Void
    /// Explains why an action did nothing, in the banner and to VoiceOver, instead of beeping.
    var onNotice: (String) -> Void = { _ in }

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
        viewer.bind(nsView, coordinator: coordinator)

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
        coordinator.updateOverlaysIfNeeded()
        if let window = nsView.window {
            onWindow(window)
        }
    }

    static func dismantleNSView(_ nsView: SigningPDFView, coordinator: Coordinator) {
        coordinator.cancelScan()
        coordinator.parent.reader.detach()
        nsView.pageOverlayViewProvider = nil
    }
}

extension PDFKitView {
    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitView
        private(set) weak var pdfView: SigningPDFView?
        private var isApplyingZoom = false
        private var overlays: [ObjectIdentifier: PageOverlayView] = [:]
        private var imageCache: [UUID: CGImage] = [:]
        private var profileImageCache: (data: Data, image: CGImage?)?
        private(set) var signatureFields: [SignatureField] = []
        private var overlayInputs: OverlayInputs?
        private var scanTask: Task<Void, Never>?
        private var reportedFormValues: [FormFieldValue]?
        private(set) var formScan: FormScan?
        /// The widget Next/Previous Form Field last moved to.
        private var lastFormFieldID: ObjectIdentifier?
        /// Counts overlay rebuilds, so tests can check that unrelated updates skip them.
        private(set) var overlayRefreshCount = 0

        var selectedPlacementID: UUID? {
            didSet {
                if selectedPlacementID != oldValue {
                    refreshOverlays()
                }
            }
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
            pdfView.onWindowChange = { [weak self] window in
                self?.parent.onWindow(window)
                self?.parent.viewer.focusIfPending()
            }
            pdfView.onUserInteraction = { [weak self] in self?.scheduleFormValueCheck() }
            pdfView.onStopSigning = { [weak self] in self?.parent.onStopSigning() }
            pdfView.hasSelectedStamp = { [weak self] in self?.selectedPlacementID != nil }

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(handleScaleChanged(_:)),
                name: .PDFViewScaleChanged,
                object: pdfView
            )
            center.addObserver(
                self,
                selector: #selector(handlePossibleFormEdit(_:)),
                name: .PDFViewAnnotationHit,
                object: pdfView
            )
            for name in [NSText.didChangeNotification, NSText.didEndEditingNotification] {
                center.addObserver(self, selector: #selector(handlePossibleFormEdit(_:)), name: name, object: nil)
            }
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
                parent.viewer.focusIfPending()
            }
            rescanDocument()
        }

        @objc
        private func handleDocumentUnlocked(_: Notification) {
            rescanDocument()
        }

        /// Shows the pages first, then walks their annotations a few pages at a time. The task never
        /// runs inside the SwiftUI update that called this, so reporting state from it is safe.
        private func rescanDocument() {
            scanTask?.cancel()
            formScan = nil
            lastFormFieldID = nil
            reportedFormValues = nil
            signatureFields = []
            let document = pdfView?.document
            scanTask = Task { [weak self] in
                guard !Task.isCancelled, let self, pdfView?.document === document else { return }
                let isLocked = document?.isLocked ?? false
                parent.onDocumentStateChange(DocumentState(signatureFields: [], isLocked: isLocked))
                updateOverlaysIfNeeded()
                guard let document, !isLocked else { return }

                let scan = await FormScan.scan(document)
                guard !Task.isCancelled, !scan.isCancelled, pdfView?.document === document else { return }
                formScan = scan
                signatureFields = scan.signatureFields
                let values = scan.values()
                reportedFormValues = values
                parent.onDocumentStateChange(DocumentState(
                    signatureFields: scan.signatureFields,
                    isLocked: false,
                    formValues: values
                ))
                updateOverlaysIfNeeded()
            }
        }

        func cancelScan() {
            scanTask?.cancel()
            scanTask = nil
        }

        // MARK: Form edits

        @objc
        private func handlePossibleFormEdit(_ notification: Notification) {
            if notification.name == .PDFViewAnnotationHit {
                scheduleFormValueCheck()
            } else if let pdfView, let text = notification.object as? NSView, text.isDescendant(of: pdfView) {
                scheduleFormValueCheck()
            }
        }

        /// PDFKit commits a widget's value after the event that changed it, so read it on the next turn.
        private func scheduleFormValueCheck() {
            guard formScan?.widgets.isEmpty == false else { return }
            DispatchQueue.main.async { [weak self] in
                self?.checkFormValues()
            }
        }

        func checkFormValues() {
            guard let values = formScan?.values(), values != reportedFormValues else { return }
            reportedFormValues = values
            parent.onFormValuesChange(values)
        }

        // MARK: Form field navigation

        /// Reveals the next (or previous) editable widget and starts editing it when it is a text field.
        /// Returns what VoiceOver should say, or nil when the document has no form fields.
        func moveToFormField(forward: Bool) -> String? {
            guard let pdfView, let document = pdfView.document, let widgets = formScan?.widgets else { return nil }
            let located = widgets.compactMap { widget -> (PDFAnnotation, PDFPage, Int)? in
                guard let page = widget.page else { return nil }
                let index = document.index(for: page)
                return index == NSNotFound ? nil : (widget, page, index)
            }
            let fields = located.map { widget, _, pageIndex in
                FormFieldNavigation.Field(
                    pageIndex: pageIndex,
                    bounds: widget.bounds,
                    name: FormFieldNavigation.name(of: widget),
                    kind: FormFieldNavigation.kind(of: widget)
                )
            }
            let order = FormFieldNavigation.readingOrder(fields)
            let current = order.firstIndex { ObjectIdentifier(located[$0].0) == lastFormFieldID }
            guard let position = FormFieldNavigation.adjacentPosition(
                after: current,
                count: order.count,
                forward: forward
            ) else { return nil }

            let (widget, page, _) = located[order[position]]
            lastFormFieldID = ObjectIdentifier(widget)
            pdfView.go(to: widget.bounds.insetBy(dx: -40, dy: -40), on: page)
            if fields[order[position]].kind == .text, !widget.isReadOnly {
                // Once it has scrolled into view.
                DispatchQueue.main.async { [weak pdfView] in
                    pdfView?.clickWidget(widget, on: page)
                }
            }
            return FormFieldNavigation.announcement(for: fields[order[position]])
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

        func updateOverlaysIfNeeded() {
            let inputs = OverlayInputs(
                placements: parent.signaturePlacements,
                signingMode: parent.signingMode,
                profilePNGData: parent.stampPNGData,
                stampWidth: parent.stampWidth,
                fields: signatureFields
            )
            guard inputs != overlayInputs else { return }
            overlayInputs = inputs
            refreshOverlays()
        }

        func refreshOverlays() {
            overlayRefreshCount += 1
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
                    return PageOverlayView.Stamp(
                        id: placement.id,
                        bounds: placement.bounds,
                        image: image,
                        accessibilityLabel: label(for: placement, bounds: placement.bounds),
                        kind: placement.kind
                    )
                }
            let isSigning = parent.signingMode != .idle

            return PageOverlayView.Content(
                cropBox: page.bounds(for: .cropBox),
                stamps: stamps,
                selectedID: selectedPlacementID,
                signingMode: parent.signingMode,
                fields: isSigning ? signatureFields.filter { $0.pageIndex == pageIndex }.map(\.bounds) : [],
                ghostImage: isSigning ? profileImage() : nil,
                ghostWidth: parent.stampWidth
            )
        }

        func label(for placement: PDFViewerDocument.SignaturePlacement, bounds: CGRect) -> String {
            let page = pdfView?.document?.page(at: placement.pageIndex)
            return StampAccessibility.label(
                signerName: placement.signerName,
                pageIndex: placement.pageIndex,
                bounds: bounds,
                cropBox: page?.bounds(for: .cropBox) ?? bounds,
                rotation: page?.rotation ?? 0,
                fields: signatureFields,
                kind: placement.kind,
                dateText: placement.dateText
            )
        }

        func location(of bounds: CGRect, onPageAt pageIndex: Int) -> String {
            let page = pdfView?.document?.page(at: pageIndex)
            return StampAccessibility.location(
                of: bounds,
                pageIndex: pageIndex,
                cropBox: page?.bounds(for: .cropBox) ?? bounds,
                rotation: page?.rotation ?? 0,
                fields: signatureFields
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
            guard let data = parent.stampPNGData else { return nil }
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

        deinit {
            scanTask?.cancel()
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
            bounds = PlacementGeometry.defaultRect(
                centeredAt: point,
                imageSize: imageSize,
                pageBounds: cropBox,
                width: parent.stampWidth
            )
        } else {
            parent.onNotice(SigningFlowLogic.clickInsideFieldNotice)
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

    func overlayDidRequestStopSigning(_: PageOverlayView) {
        parent.onStopSigning()
    }

    func overlay(_ overlay: PageOverlayView, didRequestMove id: UUID) {
        self.overlay(overlay, didSelect: id)
        let kind = parent.signaturePlacements.first { $0.id == id }?.kind ?? .signature
        StampAccessibility.announce(StampAccessibility.moveInstructions(for: kind), in: pdfView?.window)
    }
}

@MainActor
final class SigningPDFView: PDFView {
    var isSigning: () -> Bool = { false }
    var onIdleMouseDown: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    var onWindowChange: ((NSWindow) -> Void)?
    /// A click or key press PDFKit handled, which may have changed a form widget.
    var onUserInteraction: (() -> Void)?
    var onStopSigning: (() -> Void)?

    var hasSelectedStamp: () -> Bool = { false }

    /// Menu key equivalents are matched before keyDown, so the arrow chords that move or resize a
    /// selected stamp are claimed here first. Option alone is left to the Go menu's page commands.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let arrows: [NSEvent.SpecialKey] = [.leftArrow, .rightArrow, .upArrow, .downArrow]
        let flags = event.modifierFlags
        let isStampArrow = event.specialKey.map(arrows.contains) == true && !flags.contains(.command)
            && PlacementGeometry.arrowAction(shift: flags.contains(.shift), option: flags.contains(.option)) != nil
        if isStampArrow, window?.firstResponder === self, hasSelectedStamp(), keyHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// While signing, a right-click offers Stop Signing instead of PDFKit's reading menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard isSigning() else { return super.menu(for: event) }
        return StopSigningMenu.make { [weak self] in self?.onStopSigning?() }
    }

    /// Clicks that reach the PDF view itself (outside any page overlay) are consumed while signing
    /// and passed to PDFKit untouched otherwise.
    override func mouseDown(with event: NSEvent) {
        guard !isSigning() else { return }
        onIdleMouseDown?()
        super.mouseDown(with: event)
        onUserInteraction?()
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
        onUserInteraction?()
    }

    /// Where a click would open this widget's text editor, in window coordinates. Nil unless the click
    /// can reach nothing else: not while signing, the widget is the topmost annotation at its centre
    /// (so a link the document stacked over it cannot be triggered), and the point is on screen with
    /// this view, not another control or a stamp overlay, under it.
    func widgetClickPoint(_ widget: PDFAnnotation, on page: PDFPage) -> CGPoint? {
        guard window != nil, !isSigning(), widget.page === page else { return nil }
        let pagePoint = CGPoint(x: widget.bounds.midX, y: widget.bounds.midY)
        guard page.annotation(at: pagePoint) === widget else { return nil }
        let viewPoint = convert(pagePoint, from: page)
        guard visibleRect.contains(viewPoint), let superview else { return nil }
        let hit = superview.hitTest(convert(viewPoint, to: superview))
        guard let hit, hit === self || (hit.isDescendant(of: self) && !(hit is PageOverlayView)) else { return nil }
        return convert(viewPoint, to: nil)
    }

    /// PDFKit has no API to start editing a widget, so this clicks its centre. The press goes straight
    /// to PDFKit rather than through the window; the release is queued for PDFKit's tracking loop.
    func clickWidget(_ widget: PDFAnnotation, on page: PDFPage) {
        guard let window, let point = widgetClickPoint(widget, on: page) else { return }
        let events = [NSEvent.EventType.leftMouseDown, .leftMouseUp].compactMap { type in
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )
        }
        guard events.count == 2 else { return }
        window.postEvent(events[1], atStart: false)
        super.mouseDown(with: events[0])
        onUserInteraction?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
