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
    case none
}

/// What to do once the signature setup sheet saves, when signing was asked for before a signature existed.
enum PendingSigningAction: Equatable {
    case enter(SigningMode)
    case placeInNextField
    case placeOnCurrentPage
}

/// Key equivalents for the Sign menu, shown in the banner so the keyboard path is discoverable.
/// Chosen to avoid the standard File, Edit (including Find), View, Window and Go menu chords.
enum SigningShortcut {
    static let placeInNextField = "⌥⌘N"
    static let placeOnCurrentPage = "⌥⌘P"
}

enum SigningFlowLogic {
    static func entryMode(hasSignatureFields: Bool) -> SigningMode {
        hasSignatureFields ? .fieldPlacement : .freePlacement
    }

    /// The Sign toolbar toggle and Start/Stop Signing menu item.
    static func toggled(_ mode: SigningMode, hasSignatureFields: Bool) -> SigningMode {
        mode == .idle ? entryMode(hasSignatureFields: hasSignatureFields) : .idle
    }

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
        return mode == .fieldPlacement
            ? "Click a signature field, choose Anywhere, or use Sign > Place in Next Field "
            + "(\(SigningShortcut.placeInNextField))."
            : "Click where you want to \(instruction), or use Sign > Place on Current Page "
            + "(\(SigningShortcut.placeOnCurrentPage))."
    }

    static func enteredAnnouncement(mode: SigningMode, kind: StampKind = .signature) -> String {
        "Placing \(kind.title.lowercased()). \(statusText(mode: mode, kind: kind)) Press Escape to stop."
    }

    static let exitedAnnouncement = "Stopped signing."

    static func signatureMenuTitle(hasProfile: Bool) -> String {
        hasProfile ? "Edit Signature…" : "Create Signature…"
    }

    static func escapeAction(
        isExporting: Bool,
        isSigning: Bool,
        isFindVisible: Bool,
        hasSelection: Bool
    ) -> EscapeAction {
        if isExporting {
            .cancelExport
        } else if isSigning {
            .stopSigning
        } else if isFindVisible {
            .closeFind
        } else if hasSelection {
            .deselect
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

    /// Select Next/Previous Signature: reading order (page, then top to bottom, then left to right), wrapping.
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

    static func nextFieldIndex(after lastIndex: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let lastIndex, lastIndex + 1 < count else { return 0 }
        return lastIndex + 1
    }

    /// True while the window holds placements that differ from the last saved signed copy.
    static func hasUnexportedPlacements(
        _ placements: [PDFViewerDocument.SignaturePlacement],
        exported: [PDFViewerDocument.SignaturePlacement]?
    ) -> Bool {
        !placements.isEmpty && placements != exported
    }

    /// Placements not yet in a saved copy, and form values that differ from the last saved copy
    /// (or from the file as opened). Nil form values mean the form scan has not finished.
    static func unsavedWork(
        placements: [PDFViewerDocument.SignaturePlacement],
        exported: [PDFViewerDocument.SignaturePlacement]?,
        formValues: [FormFieldValue]?,
        savedFormValues: [FormFieldValue]?
    ) -> UnsavedWork {
        UnsavedWork(
            signatures: hasUnexportedPlacements(placements, exported: exported),
            formEntries: formValues != nil && formValues != savedFormValues
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
