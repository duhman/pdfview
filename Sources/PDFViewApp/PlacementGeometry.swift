import CoreGraphics

/// Pure page-space geometry for signature stamps. All rects are in unrotated PDF page space,
/// the same space as `PDFPage.bounds(for: .cropBox)` and the exported page.
enum PlacementGeometry {
    enum Corner: CaseIterable {
        case bottomLeft
        case bottomRight
        case topLeft
        case topRight

        var opposite: Corner {
            switch self {
            case .bottomLeft: .topRight
            case .bottomRight: .topLeft
            case .topLeft: .bottomRight
            case .topRight: .bottomLeft
            }
        }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
            case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
            case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
            case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }

    /// Width of a signature placed by clicking or with "Place on Current Page"; see `StampKind.defaultWidth`.
    static let defaultWidth: CGFloat = 180
    /// Gap kept between a signature field's border and the stamp inside it.
    static let fieldInset: CGFloat = 2
    /// Smallest stamp width a resize can produce.
    static let minimumWidth: CGFloat = 24
    /// Pointer travel, in window points, below which a press counts as a click rather than a drag.
    static let clickThreshold: CGFloat = 4

    /// Fits the image inside the field without distortion, aligned to the field's bottom-left
    /// so the ink sits on the signature line.
    static func aspectFit(imageSize: CGSize, in field: CGRect, inset: CGFloat = fieldInset) -> CGRect {
        let available = field.insetBy(dx: inset, dy: inset)
        guard imageSize.width > 0, imageSize.height > 0, available.width > 0, available.height > 0 else {
            return available
        }

        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        return CGRect(
            x: available.minX,
            y: available.minY,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    static func defaultRect(
        centeredAt point: CGPoint,
        imageSize: CGSize,
        pageBounds: CGRect,
        width: CGFloat = defaultWidth
    ) -> CGRect {
        let size = defaultSize(imageSize: imageSize, width: width)
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        return clamped(CGRect(origin: origin, size: size), to: pageBounds)
    }

    /// A stamp `width` wide with the image's aspect ratio, kept within sane limits for odd images.
    static func defaultSize(imageSize: CGSize, width: CGFloat) -> CGSize {
        let aspect = max(0.2, min(8.0, imageSize.width / max(imageSize.height, 1)))
        return CGSize(width: width, height: width / aspect)
    }

    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = max(bounds.minX, min(rect.origin.x, bounds.maxX - width))
        let y = max(bounds.minY, min(rect.origin.y, bounds.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func moved(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        clamped(rect.offsetBy(dx: delta.dx, dy: delta.dy), to: bounds)
    }

    /// Resizes by dragging one corner while the opposite corner stays put; the aspect ratio is locked.
    static func resized(_ rect: CGRect, dragging corner: Corner, to point: CGPoint, within bounds: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }

        let anchor = corner.opposite.point(in: rect)
        let growsRight = corner == .bottomRight || corner == .topRight
        let growsUp = corner == .topLeft || corner == .topRight

        let room = CGSize(
            width: growsRight ? bounds.maxX - anchor.x : anchor.x - bounds.minX,
            height: growsUp ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        )
        let requested = max(abs(point.x - anchor.x) / rect.width, abs(point.y - anchor.y) / rect.height)
        let largest = min(room.width / rect.width, room.height / rect.height)
        let smallest = minimumWidth / rect.width
        let scale = min(max(requested, smallest), max(largest, smallest))

        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let origin = CGPoint(
            x: growsRight ? anchor.x : anchor.x - size.width,
            y: growsUp ? anchor.y : anchor.y - size.height
        )
        return CGRect(origin: origin, size: size)
    }

    /// Arrow-key step: 1 pt, Shift 10 pt, Option 50 pt. Option-Shift resizes instead, so it has no step.
    static func nudgeDistance(shift: Bool, option: Bool) -> CGFloat? {
        switch (shift, option) {
        case (false, false): 1
        case (true, false): 10
        case (false, true): 50
        case (true, true): nil
        }
    }

    /// Keyboard resize: changes the width by `delta` with the aspect ratio locked and the bottom-left
    /// corner (the end of the signature line) fixed, within the same limits as a corner drag.
    static func scaled(_ rect: CGRect, byWidth delta: CGFloat, within bounds: CGRect) -> CGRect {
        guard rect.width > 0 else { return rect }
        let scale = max(rect.width + delta, minimumWidth) / rect.width
        let corner = CGPoint(x: rect.minX + rect.width * scale, y: rect.minY + rect.height * scale)
        return resized(rect, dragging: .topRight, to: corner, within: bounds)
    }

    static func corner(of rect: CGRect, near point: CGPoint, tolerance: CGFloat) -> Corner? {
        Corner.allCases.first { corner in
            let cornerPoint = corner.point(in: rect)
            return hypot(cornerPoint.x - point.x, cornerPoint.y - point.y) <= tolerance
        }
    }

    static func isClick(from start: CGPoint, to end: CGPoint, threshold: CGFloat = clickThreshold) -> Bool {
        hypot(end.x - start.x, end.y - start.y) <= threshold
    }
}
