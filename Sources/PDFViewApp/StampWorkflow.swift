import CoreGraphics
import Observation

extension StampKind {
    /// Width of a stamp placed by clicking or with Place on Current Page, before the user resizes one.
    var defaultWidth: CGFloat {
        switch self {
        case .signature: PlacementGeometry.defaultWidth
        case .initials: 60
        case .date: 110
        }
    }
}

/// The last width the user resized each stamp kind to, so the next stamp of that kind matches it.
/// Lives for the app session only.
@MainActor
@Observable
final class StampSizeMemory {
    private var widths: [StampKind: CGFloat] = [:]

    func width(for kind: StampKind) -> CGFloat {
        widths[kind] ?? kind.defaultWidth
    }

    func remember(width: CGFloat, for kind: StampKind) {
        widths[kind] = max(width, PlacementGeometry.minimumWidth)
    }
}
