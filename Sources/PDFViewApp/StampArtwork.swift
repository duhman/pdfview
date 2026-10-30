import AppKit

enum StampKind: String, CaseIterable, Identifiable {
    case signature
    case initials
    case date

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .signature: "Signature"
        case .initials: "Initials"
        case .date: "Date"
        }
    }

    var profileKind: SignatureKind? {
        switch self {
        case .signature: .signature
        case .initials: .initials
        case .date: nil
        }
    }
}

/// The chosen stamp's bytes and words are frozen into each placement, independent of later profile edits.
@MainActor
struct StampArtwork {
    let kind: StampKind
    let pngData: Data
    let signerName: String
    var dateText: String?

    var imageSize: CGSize? {
        NSImage(data: pngData)?.size
    }

    static func make(
        kind: StampKind,
        signature: SignatureProfile?,
        initials: SignatureProfile?,
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> StampArtwork? {
        if kind == .date {
            guard let rendering = SignatureRenderer.renderDate(date, locale: locale, timeZone: timeZone) else {
                return nil
            }
            return StampArtwork(
                kind: .date,
                pngData: rendering.pngData,
                signerName: "",
                dateText: SignatureRenderer.dateText(date, locale: locale, timeZone: timeZone)
            )
        }
        guard let profile = kind == .initials ? initials : signature, let data = profile.signaturePNGData else {
            return nil
        }
        return StampArtwork(kind: kind, pngData: data, signerName: profile.fullName)
    }

    func placement(pageIndex: Int, bounds: CGRect) -> PDFViewerDocument.SignaturePlacement {
        PDFViewerDocument.SignaturePlacement(
            pageIndex: pageIndex,
            bounds: bounds,
            signaturePNGData: pngData,
            signerName: signerName,
            kind: kind,
            dateText: dateText
        )
    }
}
