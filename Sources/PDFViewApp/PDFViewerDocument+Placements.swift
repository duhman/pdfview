import Foundation

extension PDFViewerDocument {
    /// Replaces a placement's bounds and returns the previous bounds, or nil if the id is unknown.
    @discardableResult
    mutating func updatePlacementBounds(id: UUID, to bounds: CGRect) -> CGRect? {
        guard let index = signaturePlacements.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let previous = signaturePlacements[index].bounds
        signaturePlacements[index].bounds = bounds
        return previous
    }

    /// Re-inserts a placement where it was, so undoing a delete restores the original stacking order.
    mutating func insertSignaturePlacement(_ placement: SignaturePlacement, at index: Int) {
        signaturePlacements.insert(placement, at: min(max(index, 0), signaturePlacements.count))
    }
}
