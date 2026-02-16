import Foundation

@MainActor
final class SignatureStore: ObservableObject {
    @Published private(set) var profile: SignatureProfile?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("PDFView", isDirectory: true)
        self.fileURL = folder.appendingPathComponent("signature_profile.json", isDirectory: false)

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            // Keep running with in-memory state if folder creation fails.
        }

        self.profile = Self.load(from: fileURL, decoder: decoder)
    }

    func upsert(profile: SignatureProfile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: fileURL, options: [.atomic])
        self.profile = profile
    }

    func deleteProfile() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        self.profile = nil
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> SignatureProfile? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(SignatureProfile.self, from: data)
    }
}
