import AppKit
@preconcurrency import Quartz

extension PDFKitView.Coordinator {
    func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return handleEscape()
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
        case let key? where [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(key):
            let flags = event.modifierFlags
            switch PlacementGeometry.arrowAction(shift: flags.contains(.shift), option: flags.contains(.option)) {
            case let .move(distance)?:
                nudge(placement, key: key, by: distance)
            case .resize?:
                resize(placement, growing: key == .rightArrow || key == .upArrow)
            case nil:
                return false
            }
            return true
        default:
            return false
        }
    }

    private func handleEscape() -> Bool {
        let action = SigningFlowLogic.escapeAction(
            isExporting: parent.isExporting,
            isSigning: parent.signingMode != .idle,
            isFindVisible: parent.reader.find.isVisible,
            hasSelection: selectedPlacementID != nil,
            isSavedBannerVisible: parent.isShowingSavedBanner
        )
        switch action {
        case .cancelExport, .stopSigning, .closeFind, .closeSavedBanner:
            parent.onEscape()
        case .deselect:
            selectedPlacementID = nil
        case .none:
            return false
        }
        return true
    }

    /// Moves the stamp in the on-screen direction of the arrow key, whatever the page rotation.
    private func nudge(
        _ placement: PDFViewerDocument.SignaturePlacement,
        key: NSEvent.SpecialKey,
        by distance: CGFloat
    ) {
        guard let pdfView, let page = pdfView.document?.page(at: placement.pageIndex) else { return }

        let screenUp: CGFloat = pdfView.isFlipped ? -1 : 1
        let screenVector = switch key {
        case .leftArrow: CGVector(dx: -1, dy: 0)
        case .rightArrow: CGVector(dx: 1, dy: 0)
        case .upArrow: CGVector(dx: 0, dy: screenUp)
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
        apply(bounds, to: placement, edit: .move)
    }

    /// Option-Shift-arrows: right or up grows the stamp by 10 pt of width, left or down shrinks it.
    private func resize(_ placement: PDFViewerDocument.SignaturePlacement, growing: Bool) {
        guard let page = pdfView?.document?.page(at: placement.pageIndex) else { return }
        let bounds = PlacementGeometry.scaled(
            placement.bounds,
            byWidth: growing ? 10 : -10,
            within: page.bounds(for: .cropBox)
        )
        apply(bounds, to: placement, edit: .resize)
    }

    private func apply(_ bounds: CGRect, to placement: PDFViewerDocument.SignaturePlacement, edit: StampEdit) {
        guard bounds != placement.bounds else {
            parent.onNotice(StampAccessibility.limitNotice(for: edit))
            return
        }
        parent.onUpdatePlacementBounds(placement.id, bounds, placement.kind.actionName(edit))
        let message = StampAccessibility.movedAnnouncement(
            pageIndex: placement.pageIndex,
            location: location(of: bounds, onPageAt: placement.pageIndex)
        )
        StampAccessibility.announce(message, in: pdfView?.window, priority: .medium)
    }
}
