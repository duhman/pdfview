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

/// A change to a placed stamp, named in Undo and in the stamp's menus.
enum StampEdit {
    case add, move, resize, remove
}

extension StampKind {
    /// "Move Initials", "Remove Date from Page": undo names and menus say which stamp they touch.
    func actionName(_ edit: StampEdit) -> String {
        switch edit {
        case .add: "Add \(title)"
        case .move: "Move \(title)"
        case .resize: "Resize \(title)"
        case .remove: "Remove \(title) from Page"
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
