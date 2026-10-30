import Foundation

enum SignatureKind: String, CaseIterable, Identifiable {
    case signature
    case initials

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .signature: "Signature"
        case .initials: "Initials"
        }
    }

    func defaultText(for fullName: String) -> String {
        switch self {
        case .signature: fullName
        case .initials:
            fullName.split { $0.isWhitespace }
                .compactMap(\.first)
                .map(String.init)
                .joined()
                .uppercased()
        }
    }
}

/// Persistent signature profile for the current macOS user.
struct SignatureProfile: Codable, Identifiable, Equatable {
    enum SourceKind: String, Codable, CaseIterable {
        case draw
        case type
        case `import`
    }

    let id: UUID
    var fullName: String
    var createdAt: Date
    var signaturePNGBase64: String
    var sourceKind: SourceKind
    /// For typed signatures, the text and font used, so editing can reopen them. Absent in older profiles.
    var typedText: String?
    var fontName: String?

    var signaturePNGData: Data? {
        Data(base64Encoded: signaturePNGBase64)
    }

    init(
        id: UUID = UUID(),
        fullName: String,
        createdAt: Date = Date(),
        signaturePNGData: Data,
        sourceKind: SourceKind,
        typedText: String? = nil,
        fontName: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.createdAt = createdAt
        signaturePNGBase64 = signaturePNGData.base64EncodedString()
        self.sourceKind = sourceKind
        self.typedText = typedText
        self.fontName = fontName
    }
}
