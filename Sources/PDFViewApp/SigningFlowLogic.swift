import Foundation
@preconcurrency import Quartz

/// A detected `/Sig` form field, in page space.
struct SignatureField: Equatable {
    let pageIndex: Int
    let bounds: CGRect
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

    static func statusText(mode: SigningMode) -> String {
        mode == .fieldPlacement
            ? "Click a signature field to sign, or choose Anywhere."
            : "Click where you want to sign."
    }

    static func enteredAnnouncement(mode: SigningMode) -> String {
        "Signing. \(statusText(mode: mode)) Press Escape to stop."
    }

    static func placedAnnouncement(pageIndex: Int) -> String {
        "Signature placed on page \(pageIndex + 1)"
    }

    static func savedAnnouncement(fileName: String) -> String {
        "Saved \(fileName)"
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

    static func signedFileName(for sourceURL: URL?) -> String {
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "document"
        return "\(baseName)-signed.pdf"
    }

    /// Only `/FT /Sig` widgets count; a text field named "DesignatedContact" is not a signature field.
    static func isSignatureField(_ annotation: PDFAnnotation) -> Bool {
        annotation.widgetFieldType == .signature
    }

    static func signatureFields(in document: PDFDocument) -> [SignatureField] {
        (0 ..< document.pageCount).flatMap { pageIndex -> [SignatureField] in
            guard let page = document.page(at: pageIndex) else { return [] }
            return page.annotations
                .filter(isSignatureField)
                .map { SignatureField(pageIndex: pageIndex, bounds: $0.bounds) }
        }
    }
}
