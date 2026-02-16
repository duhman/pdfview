import Foundation

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

    var signaturePNGData: Data? {
        Data(base64Encoded: signaturePNGBase64)
    }

    init(
        id: UUID = UUID(),
        fullName: String,
        createdAt: Date = Date(),
        signaturePNGData: Data,
        sourceKind: SourceKind
    ) {
        self.id = id
        self.fullName = fullName
        self.createdAt = createdAt
        self.signaturePNGBase64 = signaturePNGData.base64EncodedString()
        self.sourceKind = sourceKind
    }
}
