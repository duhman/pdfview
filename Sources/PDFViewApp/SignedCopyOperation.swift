import AppKit
import Observation
@preconcurrency import Quartz
import SwiftUI

/// Owns one export per window, including the save panel reservation and cancellation lifetime.
@MainActor
@Observable
final class SignedCopyOperation {
    private(set) var isBusy = false
    private(set) var progress: ExportProgress?
    private var originalURL: URL?
    private var protection: DocumentProtection?
    private var task: Task<Void, Never>?

    func reserve() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    func release() {
        isBusy = false
        progress = nil
        task = nil
        originalURL = nil
        protection = nil
    }

    func updateProgress(_ progress: ExportProgress) {
        self.progress = progress
    }

    func cancel() {
        task?.cancel()
    }

    /// Installs the accessory before the window presents its reserved save panel.
    func configure(_ panel: NSSavePanel, originalURL: URL?, protection: DocumentProtection) {
        self.originalURL = originalURL
        self.protection = protection
        panel.accessoryView = protection.isEncrypted ?
            NSHostingView(rootView: SignedCopyProtectionAccessory(protection: protection)) : nil
    }

    nonisolated static func validateDestination(_ destination: URL, originalURL: URL?) throws {
        guard destination.isFileURL else { throw PDFViewerDocument.ExportError.invalidDestinationURL }
        guard let originalURL else { return }
        let source = originalURL.standardizedFileURL.resolvingSymlinksInPath()
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        if source == target {
            throw PDFViewerDocument.ExportError.cannotReplaceOriginal
        }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let left = try? source.resourceValues(forKeys: keys),
              let right = try? target.resourceValues(forKeys: keys),
              let leftID = left.fileResourceIdentifier as? NSObject,
              let rightID = right.fileResourceIdentifier as? NSObject,
              let leftVolume = left.volumeIdentifier as? NSObject,
              let rightVolume = right.volumeIdentifier as? NSObject else { return }
        if leftVolume.isEqual(rightVolume), leftID.isEqual(rightID) {
            throw PDFViewerDocument.ExportError.cannotReplaceOriginal
        }
    }

    func write(
        _ source: PDFDocument,
        placements: [PDFViewerDocument.SignaturePlacement],
        to url: URL,
        completion: @escaping (Result<ExportedState, Error>) -> Void
    ) {
        task = Task { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
                release()
            }
            do {
                let original = originalURL ?? source.documentURL
                try Self.validateDestination(url, originalURL: original)
                let password = protection?.exportPassword
                let state = try await SignedPDFExporter.writeAsync(
                    source, placements: placements, to: url, password: password, originalURL: original
                ) { self.progress = $0 }
                completion(.success(state))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
