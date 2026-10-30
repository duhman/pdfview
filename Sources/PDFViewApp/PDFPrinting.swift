import AppKit
@preconcurrency import Quartz

/// Retains the staged signed PDF until AppKit's modal print operation has finished.
@MainActor
final class PDFPrinting {
    private(set) var document: PDFDocument?
    private(set) var temporaryURL: URL?

    func prepare(
        source: PDFDocument,
        placements: [PDFViewerDocument.SignaturePlacement],
        password: String? = nil,
        progress: @escaping @MainActor @Sendable (ExportProgress) -> Void
    ) async throws {
        guard !source.isLocked, source.allowsPrinting else { throw CocoaError(.fileReadNoPermission) }
        if placements.isEmpty {
            document = source
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            temporaryURL = url
            do {
                try await SignedPDFExporter.writeAsync(
                    source, placements: placements, to: url, password: password, progress: progress
                )
                guard let signed = PDFDocument(url: url)
                else { throw PDFViewerDocument.ExportError.invalidExportedDocument }
                if signed.isLocked {
                    guard let password, signed.unlock(withPassword: password) else {
                        throw PDFViewerDocument.ExportError.documentLocked
                    }
                }
                document = signed
            } catch {
                cleanup()
                throw error
            }
        }
    }

    func run() throws {
        defer { cleanup() }
        guard let operation = document?.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleToFit,
            autoRotate: true
        ) else {
            throw CocoaError(.featureUnsupported)
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    func cleanup() {
        document = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        temporaryURL = nil
    }
}
