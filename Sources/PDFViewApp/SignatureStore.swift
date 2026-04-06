import Foundation

@MainActor
final class SignatureStore: ObservableObject {
    @Published private(set) var profile: SignatureProfile?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
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
                return "No signature profile found."
            case .cannotEncodeProfile:
                return "Cannot encode the signature profile."
            case .cannotCreateStorageDirectory(let underlying):
                return "Cannot create signature storage directory: \(underlying.localizedDescription)"
            case .cannotWriteProfile(let underlying):
                return "Cannot save signature profile: \(underlying.localizedDescription)"
            case .cannotReadProfile(let underlying):
                return "Cannot load signature profile: \(underlying.localizedDescription)"
            case .invalidProfileData:
                return "The signature profile data is invalid or corrupted."
            case .storageCorrupted:
                return "Signature storage is corrupted."
            case .insufficientDiskSpace:
                return "Insufficient disk space to save signature profile."
            case .permissionDenied(let path):
                return "Permission denied accessing signature storage at \(path)."
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .noProfileFound:
                return "Create a new signature by clicking the signature button."
            case .cannotEncodeProfile, .invalidProfileData, .storageCorrupted:
                return "Delete the corrupted signature and create a new one."
            case .cannotCreateStorageDirectory, .permissionDenied:
                return "Check that the app has permission to access its container directory."
            case .cannotWriteProfile, .insufficientDiskSpace:
                return "Free up disk space and try again."
            case .cannotReadProfile:
                return "Try restarting the app. If the problem persists, recreate your signature."
            }
        }
    }

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        if let storageURL {
            self.fileURL = storageURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let folder = appSupport.appendingPathComponent("PDFView", isDirectory: true)
            self.fileURL = folder.appendingPathComponent("signature_profile.json", isDirectory: false)
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Create storage directory with proper error handling
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            print("Warning: Could not create signature storage directory: \(error.localizedDescription)")
            // Continue with in-memory state
        }

        // Load existing profile with error handling
        self.profile = Self.load(from: fileURL, decoder: decoder)
    }

    func saveProfile(_ profile: SignatureProfile) throws {
        // Validate profile data
        guard !profile.fullName.isEmpty else {
            throw SignatureError.invalidProfileData
        }
        
        guard let pngData = profile.signaturePNGData, !pngData.isEmpty else {
            throw SignatureError.invalidProfileData
        }
        
        // Check available disk space
        let resourceValues = try fileURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let availableSpace = resourceValues.volumeAvailableCapacityForImportantUsage, 
           availableSpace < Int64(pngData.count + 1024) {
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
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        self.profile = nil
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> SignatureProfile? {
        do {
            let data = try Data(contentsOf: url)
            let profile = try decoder.decode(SignatureProfile.self, from: data)
            
            // Validate loaded profile
            guard !profile.fullName.isEmpty, 
                  let pngData = profile.signaturePNGData, 
                  !pngData.isEmpty else {
                print("Warning: Loaded signature profile has invalid data, ignoring")
                return nil
            }
            
            return profile
        } catch {
            print("Warning: Could not load signature profile: \(error.localizedDescription)")
            return nil
        }
    }
}
