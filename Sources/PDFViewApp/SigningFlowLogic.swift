import Foundation
@preconcurrency import Quartz

/// A detected `/Sig` form field, in page space.
struct SignatureField: Equatable {
    let pageIndex: Int
    let bounds: CGRect
    /// The field's `/T` name, used to tell VoiceOver users which field holds a stamp.
    var name: String?
}

/// Alert copy for a failed action: the title names what failed, the message gives the reason
/// and, when the error offers one, what to do about it.
struct ErrorAlert: Equatable {
    let title: String
    let message: String

    init(title: String, error: Error) {
        self.title = title
        let reason = error.localizedDescription
        let recovery = (error as? LocalizedError)?.recoverySuggestion
        message = [reason, recovery].compactMap(\.self).joined(separator: " ")
    }
}

/// What a window would lose if it closed now.
struct UnsavedWork: Equatable {
    var signatures = false
    var formEntries = false

    var isEmpty: Bool {
        !signatures && !formEntries
    }

    var lossWarning: String {
        let subject = switch (signatures, formEntries) {
        case (true, true): "Your signatures and form entries"
        case (false, true): "Your form entries"
        default: "Your signatures"
        }
        return "\(subject) will be lost if you don’t save."
    }
}

/// What Escape does in the document, most recent activity first. The Find field handles its own
/// Escape (it closes Find) because that is where the user's attention is.
enum EscapeAction: Equatable {
    case cancelExport
    case stopSigning
    case closeFind
    case deselect
    case closeSavedBanner
    case none
}

/// What to do once the signature setup sheet saves, when signing was asked for before a signature existed.
enum PendingSigningAction: Equatable {
    case enter(SigningMode)
    case placeInNextField
    case placeOnCurrentPage
    case placeInitialsOnEveryPage
}

/// The stamp kind and placement mode a window is in.
struct SigningState: Equatable {
    var kind: StampKind
    var mode: SigningMode
}

/// A setup sheet opened on the way to a stamp: what to run once it saves, and the state to return to
/// if it is cancelled, so a kind with no artwork never stays active.
struct SetupRequest: Equatable {
    var pending: PendingSigningAction?
    var restoring: SigningState

    var stateAfterCancel: SigningState {
        restoring.mode == .idle
            ? SigningState(kind: StampWorkflow.kindAfterPlacementOrExit(restoring.kind), mode: .idle)
            : restoring
    }
}

/// Sign menu chords as the signing banner and announcements show them, taken from `MenuShortcuts`.
enum SigningShortcut {
    static let placeInNextField = MenuShortcuts.display(MenuShortcuts.placeInNextField)
    static let placeOnCurrentPage = MenuShortcuts.display(MenuShortcuts.placeOnCurrentPage)
    static let selectNextStamp = MenuShortcuts.display(MenuShortcuts.selectNextStamp)
    static let placeInitialsOnEveryPage = MenuShortcuts.display(MenuShortcuts.placeInitialsOnEveryPage)
}

/// The Fields/Anywhere choice per stamp kind, remembered for one window. Signatures default to the
/// PDF's signature fields; initials and dates usually go elsewhere on the page, so they start in Anywhere.
struct PlacementChoices: Equatable {
    private var anywhere: [StampKind: Bool] = [:]

    func entryMode(for kind: StampKind, hasSignatureFields: Bool) -> SigningMode {
        SigningFlowLogic.mode(anywhere: anywhere[kind] ?? (kind != .signature), hasSignatureFields: hasSignatureFields)
    }

    mutating func remember(anywhere: Bool, for kind: StampKind) {
        self.anywhere[kind] = anywhere
    }
}

enum SigningFlowLogic {
    /// Done, Escape, or Stop Signing.
    static func exited(_: SigningMode) -> SigningMode {
        .idle
    }

    /// One stamp per use: placing a signature ends signing, as in Preview.
    static func afterPlacement(_: SigningMode) -> SigningMode {
        .idle
    }

    static func mode(anywhere: Bool, hasSignatureFields: Bool) -> SigningMode {
        anywhere || !hasSignatureFields ? .freePlacement : .fieldPlacement
    }

    /// Keeps the mode valid when the detected fields change (unlock, document swap).
    static func refreshed(_ mode: SigningMode, hasSignatureFields: Bool) -> SigningMode {
        mode == .fieldPlacement && !hasSignatureFields ? .freePlacement : mode
    }

    static func statusText(mode: SigningMode, kind: StampKind = .signature) -> String {
        let instruction = kind == .signature ? "sign" : "place your \(kind.title.lowercased())"
        let text = switch (mode, kind) {
        case (.fieldPlacement, .signature):
            "Click a signature field, choose Anywhere, or use Sign > "
                + "\(StampWorkflow.placeInNextFieldTitle(kind: kind)) (\(SigningShortcut.placeInNextField))."
        case (.fieldPlacement, _):
            "Click a signature field, or choose Anywhere to \(instruction) elsewhere on the page."
        default:
            "Click where you want to \(instruction), or use Sign > "
                + "\(StampWorkflow.placeOnCurrentPageTitle(kind: kind)) (\(SigningShortcut.placeOnCurrentPage))."
        }
        guard kind == .initials else { return text }
        return text + " Sign > \(StampWorkflow.everyPageActionName) (\(SigningShortcut.placeInitialsOnEveryPage)) "
            + "initials every page at once."
    }

    /// Why Sign > Place Signature in Next Field is unavailable, or nil when it can be used. It fills
    /// signature fields, so it never places initials or a date.
    static func nextFieldUnavailableReason(kind: StampKind, hasSignatureFields: Bool) -> String? {
        switch kind {
        case _ where !hasSignatureFields: "This PDF has no signature fields."
        case .signature: nil
        case .initials: "Place in Next Field places signatures. Click a field or the page to place initials."
        case .date: "Place in Next Field places signatures. Click a field or the page to place the date."
        }
    }

    static func enteredAnnouncement(mode: SigningMode, kind: StampKind = .signature) -> String {
        "Placing \(kind.title.lowercased()). \(statusText(mode: mode, kind: kind)) Press Escape to stop."
    }

    static let exitedAnnouncement = "Stopped signing."

    /// Shown in the signing banner when a click in Fields mode misses every signature field.
    static let clickInsideFieldNotice = "Click inside a signature field, or choose Anywhere."

    static func escapeAction(
        isExporting: Bool,
        isSigning: Bool,
        isFindVisible: Bool,
        hasSelection: Bool,
        isSavedBannerVisible: Bool = false
    ) -> EscapeAction {
        if isExporting {
            .cancelExport
        } else if isSigning {
            .stopSigning
        } else if isFindVisible {
            .closeFind
        } else if hasSelection {
            .deselect
        } else if isSavedBannerVisible {
            .closeSavedBanner
        } else {
            .none
        }
    }

    /// The saved banner names the folder too, so the copy can be found after the banner is closed.
    static func savedText(for url: URL) -> String {
        "Saved “\(url.lastPathComponent)” to \(url.deletingLastPathComponent().lastPathComponent)"
    }

    static func savedAnnouncement(for url: URL) -> String {
        "Saved \(url.lastPathComponent) to \(url.deletingLastPathComponent().lastPathComponent)"
    }

    /// Select Next/Previous Stamp: reading order (page, then top to bottom, then left to right), wrapping.
    static func adjacentPlacement(
        after currentID: UUID?,
        in placements: [PDFViewerDocument.SignaturePlacement],
        forward: Bool
    ) -> UUID? {
        let ordered = placements.sorted {
            ($0.pageIndex, -$0.bounds.maxY, $0.bounds.minX) < ($1.pageIndex, -$1.bounds.maxY, $1.bounds.minX)
        }
        guard !ordered.isEmpty else { return nil }
        guard let currentID, let index = ordered.firstIndex(where: { $0.id == currentID }) else {
            return forward ? ordered.first?.id : ordered.last?.id
        }
        let next = (index + (forward ? 1 : -1) + ordered.count) % ordered.count
        return ordered[next].id
    }

    /// Select Next/Previous Stamp. A stamp that is selected but does not own the arrow keys yet (it was
    /// just placed) is taken first, so the command never skips the stamp the user is looking at.
    static func stampToSelect(
        after currentID: UUID?,
        ownsArrowKeys: Bool,
        in placements: [PDFViewerDocument.SignaturePlacement],
        forward: Bool
    ) -> UUID? {
        if let currentID, !ownsArrowKeys, placements.contains(where: { $0.id == currentID }) {
            return currentID
        }
        return adjacentPlacement(after: currentID, in: placements, forward: forward)
    }

    /// True while the window holds placements that differ from the last saved signed copy.
    static func hasUnexportedPlacements(
        _ placements: [PDFViewerDocument.SignaturePlacement],
        exported: [PDFViewerDocument.SignaturePlacement]?
    ) -> Bool {
        placements != (exported ?? [])
    }

    /// Placements not yet in a saved copy, and form values that differ from the last saved copy
    /// (or from the file as opened). Unavailable form values conservatively require review.
    static func unsavedWork(
        placements: [PDFViewerDocument.SignaturePlacement],
        exported: [PDFViewerDocument.SignaturePlacement]?,
        formValues: [FormFieldValue]?,
        savedFormValues: [FormFieldValue]?
    ) -> UnsavedWork {
        UnsavedWork(
            signatures: hasUnexportedPlacements(placements, exported: exported),
            formEntries: formValues == nil || savedFormValues == nil || formValues != savedFormValues
        )
    }

    /// A signed copy is worth saving once it holds a stamp or a form entry the original lacks.
    static func hasSignedCopyContent(
        placements: [PDFViewerDocument.SignaturePlacement],
        formValues: [FormFieldValue]?,
        originalFormValues: [FormFieldValue]?
    ) -> Bool {
        !placements.isEmpty || (formValues != nil && formValues != originalFormValues)
    }

    static func signedFileName(for sourceURL: URL?) -> String {
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "document"
        return "\(baseName)-signed.pdf"
    }

    /// Only `/FT /Sig` widgets count; a text field named "DesignatedContact" is not a signature field.
    static func isSignatureField(_ annotation: PDFAnnotation) -> Bool {
        annotation.widgetFieldType == .signature
    }
}
