import Foundation
import ImageIO
import os

@MainActor
final class SignatureStore: ObservableObject {
    @Published private var profiles = StoredProfiles()

    /// Compatibility access for the existing signature placement path.
    var profile: SignatureProfile? {
        profile(for: .signature)
    }

    func profile(for kind: SignatureKind) -> SignatureProfile? {
        profiles[kind]
    }

    private struct StoredProfiles: Codable {
        var signature: SignatureProfile?
        var initials: SignatureProfile?

        subscript(kind: SignatureKind) -> SignatureProfile? {
            get {
                switch kind {
                case .signature: signature
                case .initials: initials
                }
            }
            set {
                switch kind {
                case .signature: signature = newValue
                case .initials: initials = newValue
                }
            }
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let logger = Logger(subsystem: "com.bigmac.pdfview", category: "SignatureStore")

    enum SignatureError: LocalizedError {
        case cannotEncodeProfile
        case cannotWriteProfile(underlying: Error)
        case invalidProfileData
        case insufficientDiskSpace
        case permissionDenied(path: String)

        var errorDescription: String? {
            switch self {
            case .cannotEncodeProfile:
                "Cannot encode the signature profile."
            case let .cannotWriteProfile(underlying):
                "Cannot save signature profile: \(underlying.localizedDescription)"
            case .invalidProfileData:
                "The signature profile data is invalid or corrupted."
            case .insufficientDiskSpace:
                "Insufficient disk space to save signature profile."
            case let .permissionDenied(path):
                "Permission denied accessing signature storage at \(path)."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .cannotEncodeProfile, .invalidProfileData:
                "Delete the corrupted signature and create a new one."
            case .permissionDenied:
                "Check that the app has permission to access its container directory."
            case .cannotWriteProfile, .insufficientDiskSpace:
                "Free up disk space and try again."
            }
        }
    }

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager
        if let storageURL {
            fileURL = storageURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let folder = appSupport.appendingPathComponent("PDFView", isDirectory: true)
            fileURL = folder.appendingPathComponent("signature_profile.json", isDirectory: false)
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Create storage directory with proper error handling
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            Self.logger.error(
                "Could not create signature storage directory: \(error.localizedDescription, privacy: .public)"
            )
        }

        // Load existing profile with error handling
        profiles = Self.load(from: fileURL, decoder: decoder)
    }

    func saveProfile(_ profile: SignatureProfile, for kind: SignatureKind = .signature) throws {
        guard Self.isValid(profile) else {
            throw SignatureError.invalidProfileData
        }
        var updated = profiles
        updated[kind] = profile
        try persist(updated)
        profiles = updated
    }

    private func persist(_ updated: StoredProfiles) throws {
        do {
            let data = try encoder.encode(updated)
            let resourceValues = try fileURL.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = resourceValues.volumeAvailableCapacityForImportantUsage ?? Int64.max
            if available < Int64(data.count + 1024) {
                throw SignatureError.insufficientDiskSpace
            }
            try data.write(to: fileURL, options: [.atomic])
        } catch let error as SignatureError {
            throw error
        } catch _ as EncodingError {
            throw SignatureError.cannotEncodeProfile
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw SignatureError.permissionDenied(path: fileURL.path)
        } catch {
            throw SignatureError.cannotWriteProfile(underlying: error)
        }
    }

    func deleteProfile(for kind: SignatureKind = .signature) throws {
        var updated = profiles
        updated[kind] = nil
        if updated.signature == nil, updated.initials == nil {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } else {
            try persist(updated)
        }
        profiles = updated
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> StoredProfiles {
        do {
            let data = try Data(contentsOf: url)
            // The original file was a bare profile, without a collection envelope.
            var profiles: StoredProfiles = if let legacy = try? decoder.decode(SignatureProfile.self, from: data) {
                StoredProfiles(signature: legacy)
            } else {
                try decoder.decode(StoredProfiles.self, from: data)
            }
            for kind in SignatureKind.allCases {
                if let profile = profiles[kind], !isValid(profile) {
                    logger.error("Ignoring profile whose name is empty or whose image cannot be decoded")
                    profiles[kind] = nil
                }
            }
            return profiles
        } catch CocoaError.fileReadNoSuchFile {
            return StoredProfiles()
        } catch {
            logger.error("Could not load signature profiles: \(error.localizedDescription, privacy: .public)")
            return StoredProfiles()
        }
    }

    private static func isValid(_ profile: SignatureProfile) -> Bool {
        guard !profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = profile.signaturePNGData else { return false }
        return isDecodableImage(data)
    }

    /// The stamp is drawn from these bytes later; reject anything that isn't a real image now.
    private static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
