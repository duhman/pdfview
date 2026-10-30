import Foundation
import ImageIO
import os

@MainActor
final class SignatureStore: ObservableObject {
    @Published private(set) var profile: SignatureProfile?

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let logger = Logger(subsystem: "com.bigmac.pdfview", category: "SignatureStore")

    enum SignatureError: LocalizedError {
        case noProfileFound
        case cannotEncodeProfile
        case cannotCreateStorageDirectory(underlying: Error)
        case cannotWriteProfile(underlying: Error)
        case cannotReadProfile(underlying: Error)
        case invalidProfileData
        case storageCorrupted
        case insufficientDiskSpace
        case permissionDenied(path: String)

        var errorDescription: String? {
            switch self {
            case .noProfileFound:
                "No signature profile found."
            case .cannotEncodeProfile:
                "Cannot encode the signature profile."
            case let .cannotCreateStorageDirectory(underlying):
                "Cannot create signature storage directory: \(underlying.localizedDescription)"
            case let .cannotWriteProfile(underlying):
                "Cannot save signature profile: \(underlying.localizedDescription)"
            case let .cannotReadProfile(underlying):
                "Cannot load signature profile: \(underlying.localizedDescription)"
            case .invalidProfileData:
                "The signature profile data is invalid or corrupted."
            case .storageCorrupted:
                "Signature storage is corrupted."
            case .insufficientDiskSpace:
                "Insufficient disk space to save signature profile."
            case let .permissionDenied(path):
                "Permission denied accessing signature storage at \(path)."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .noProfileFound:
                "Create a new signature by clicking the signature button."
            case .cannotEncodeProfile, .invalidProfileData, .storageCorrupted:
                "Delete the corrupted signature and create a new one."
            case .cannotCreateStorageDirectory, .permissionDenied:
                "Check that the app has permission to access its container directory."
            case .cannotWriteProfile, .insufficientDiskSpace:
                "Free up disk space and try again."
            case .cannotReadProfile:
                "Try restarting the app. If the problem persists, recreate your signature."
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
        profile = Self.load(from: fileURL, decoder: decoder)
    }

    func saveProfile(_ profile: SignatureProfile) throws {
        // Validate profile data
        guard !profile.fullName.isEmpty, let pngData = profile.signaturePNGData, Self.isDecodableImage(pngData) else {
            throw SignatureError.invalidProfileData
        }

        // Check available disk space
        let resourceValues = try fileURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let requiredSpace = Int64(pngData.count + 1024)
        if let available = resourceValues.volumeAvailableCapacityForImportantUsage, available < requiredSpace {
            throw SignatureError.insufficientDiskSpace
        }

        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: [.atomic])
            self.profile = profile
        } catch _ as EncodingError {
            throw SignatureError.cannotEncodeProfile
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw SignatureError.permissionDenied(path: fileURL.path)
        } catch {
            throw SignatureError.cannotWriteProfile(underlying: error)
        }
    }

    func loadProfile() throws -> SignatureProfile {
        guard let existingProfile = profile else {
            throw SignatureError.noProfileFound
        }
        return existingProfile
    }

    var hasProfile: Bool {
        profile != nil
    }

    func deleteProfile() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        profile = nil
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> SignatureProfile? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Could not read signature profile: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            let profile = try decoder.decode(SignatureProfile.self, from: data)
            guard !profile.fullName.isEmpty,
                  let pngData = profile.signaturePNGData,
                  isDecodableImage(pngData)
            else {
                logger.error("Ignoring signature profile whose name is empty or whose image cannot be decoded")
                return nil
            }
            return profile
        } catch {
            logger.error("Could not decode signature profile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The stamp is drawn from these bytes later; reject anything that isn't a real image now.
    private static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
