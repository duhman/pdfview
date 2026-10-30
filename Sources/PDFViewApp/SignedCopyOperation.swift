import Foundation
import Observation
@preconcurrency import Quartz

/// Owns one export per window, including the save panel reservation and cancellation lifetime.
@MainActor
@Observable
final class SignedCopyOperation {
    private(set) var isBusy = false
    private(set) var progress: ExportProgress?
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
    }

    func updateProgress(_ progress: ExportProgress) {
        self.progress = progress
    }

    func cancel() {
        task?.cancel()
    }

    func write(
        _ source: PDFDocument,
        placements: [PDFViewerDocument.SignaturePlacement],
        to url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
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
                try await SignedPDFExporter.writeAsync(source, placements: placements, to: url) { progress = $0 }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
