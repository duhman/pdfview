import CoreGraphics
import Foundation
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

    // MARK: Initials on every page

    /// A page's crop box and display rotation, which decides where "bottom right" is on screen.
    struct PageFrame: Equatable {
        var cropBox: CGRect
        var rotation = 0
    }

    /// Gap between a default-placed stamp and the page edges.
    static let pageMargin: CGFloat = 36
    static let everyPageActionName = "Place Initials on Every Page"

    /// The selected initials, or else the most recently added initials, give every page its position.
    static func referenceInitials(
        selectedID: UUID?,
        placements: [PDFViewerDocument.SignaturePlacement]
    ) -> PDFViewerDocument.SignaturePlacement? {
        let initials = placements.filter { $0.kind == .initials }
        return initials.first { $0.id == selectedID } ?? initials.last
    }

    /// One rect per page that has no initials yet: at the reference's position relative to its own
    /// page (same size, kept on the page), or in the on-screen bottom-right margin without one.
    static func initialsOnEveryPage(
        reference: PDFViewerDocument.SignaturePlacement?,
        pages: [PageFrame],
        placements: [PDFViewerDocument.SignaturePlacement],
        defaultSize: CGSize
    ) -> [(pageIndex: Int, bounds: CGRect)] {
        let pagesWithInitials = Set(placements.filter { $0.kind == .initials }.map(\.pageIndex))
        let referenceCrop = reference
            .flatMap { pages.indices.contains($0.pageIndex) ? pages[$0.pageIndex].cropBox : nil }
        return pages.enumerated().compactMap { index, page in
            guard !pagesWithInitials.contains(index), page.cropBox.width > 0,
                  page.cropBox.height > 0 else { return nil }
            let bounds = if let reference, let referenceCrop, referenceCrop.width > 0, referenceCrop.height > 0 {
                relativeRect(reference.bounds, from: referenceCrop, to: page.cropBox)
            } else {
                bottomRightRect(size: defaultSize, on: page)
            }
            return (index, PlacementGeometry.clamped(bounds, to: page.cropBox))
        }
    }

    /// Which new initials to scroll to: the current page's, else the next page's, else the first.
    static func targetToReveal(
        _ targets: [(pageIndex: Int, bounds: CGRect)],
        currentPageIndex: Int?
    ) -> (pageIndex: Int, bounds: CGRect)? {
        guard let current = currentPageIndex else { return targets.first }
        return targets.first { $0.pageIndex >= current } ?? targets.first
    }

    static func everyPageAnnouncement(count: Int) -> String {
        switch count {
        case 0: "Every page already has initials."
        case 1: "Placed initials on 1 page."
        default: "Placed initials on \(count) pages."
        }
    }

    /// Keeps the stamp's size and moves its centre to the same fraction of the other page.
    private static func relativeRect(_ rect: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let center = CGPoint(
            x: target.minX + (rect.midX - source.minX) / source.width * target.width,
            y: target.minY + (rect.midY - source.minY) / source.height * target.height
        )
        return CGRect(
            x: center.x - rect.width / 2,
            y: center.y - rect.height / 2,
            width: rect.width,
            height: rect.height
        )
    }

    /// PDF rotation turns the page clockwise for display, so the on-screen bottom-right corner is a
    /// different page-space corner for each quarter turn.
    private static func bottomRightRect(size: CGSize, on page: PageFrame) -> CGRect {
        let crop = page.cropBox
        let left = crop.minX + pageMargin
        let right = crop.maxX - pageMargin - size.width
        let bottom = crop.minY + pageMargin
        let top = crop.maxY - pageMargin - size.height
        let origin = switch ((page.rotation % 360) + 360) % 360 {
        case 90: CGPoint(x: right, y: top)
        case 180: CGPoint(x: left, y: top)
        case 270: CGPoint(x: left, y: bottom)
        default: CGPoint(x: right, y: bottom)
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: Saved profiles

    static func deleteMenuTitle(_ kind: SignatureKind) -> String {
        "Delete Saved \(kind.title)…"
    }

    static func deleteAlertTitle(_ kind: SignatureKind) -> String {
        "Delete your saved \(kind.title.lowercased())?"
    }

    static func deleteAlertMessage(_ kind: SignatureKind) -> String {
        switch kind {
        case .signature:
            "It will be removed from this Mac. Signatures already placed in documents are not affected."
        case .initials:
            "They will be removed from this Mac. Initials already placed in documents are not affected."
        }
    }

    // MARK: Toolbar

    /// Spoken by VoiceOver for the Sign toolbar menu, so the state is not carried by colour alone.
    static func signToolbarValue(mode: SigningMode) -> String {
        mode == .idle ? "Not signing" : "Signing"
    }

    /// A filled pencil while signing gives the state a second, shape-based cue beside the tint.
    static func signToolbarSymbol(mode: SigningMode) -> String {
        mode == .idle ? "signature" : "pencil.circle.fill"
    }
}
