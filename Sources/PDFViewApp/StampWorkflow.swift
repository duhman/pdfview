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

/// Stamp-kind rules and titles for the Sign menu, the toolbar and the signing banner.
enum StampWorkflow {
    /// One stamp per use: initials or a date never become the default for the next placement.
    static func kindAfterPlacementOrExit(_: StampKind) -> StampKind {
        .signature
    }

    static func signingToggleTitle(mode: SigningMode, kind: StampKind) -> String {
        guard mode != .idle else { return "Start Signing" }
        return kind == .signature ? "Stop Signing" : "Stop Placing \(kind.title)"
    }

    static func placeInNextFieldTitle(kind: StampKind) -> String {
        "Place \(kind.title) in Next Field"
    }

    static func placeOnCurrentPageTitle(kind: StampKind) -> String {
        "Place \(kind.title) on Current Page"
    }

    static let allFieldsFilledAnnouncement = "Every signature field already has a stamp."

    /// The next field after `lastIndex`, wrapping, that has no stamp centred inside it yet.
    static func nextEmptyFieldIndex(
        after lastIndex: Int?,
        fields: [SignatureField],
        placements: [PDFViewerDocument.SignaturePlacement]
    ) -> Int? {
        guard !fields.isEmpty else { return nil }
        let start = lastIndex.map { $0 + 1 } ?? 0
        return (0 ..< fields.count).lazy
            .map { (start + $0) % fields.count }
            .first { index in
                let field = fields[index]
                return !placements.contains {
                    $0.pageIndex == field.pageIndex && field.bounds.contains(CGPoint(
                        x: $0.bounds.midX,
                        y: $0.bounds.midY
                    ))
                }
            }
    }
}
