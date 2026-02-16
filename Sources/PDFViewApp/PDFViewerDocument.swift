import SwiftUI
@preconcurrency import Quartz
import UniformTypeIdentifiers
import AppKit

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {
    enum ExportError: LocalizedError, Equatable {
        case missingDocument
        case invalidDestinationURL
        case cannotEncodeDocumentData
        case cannotCreatePDFContext
        case writeFailed(description: String)

        var errorDescription: String? {
            switch self {
            case .missingDocument:
                return "No PDF document is loaded."
            case .invalidDestinationURL:
                return "The destination must be a local file URL."
            case .cannotEncodeDocumentData:
                return "The PDF data could not be encoded."
            case .cannotCreatePDFContext:
                return "Could not create a PDF writing context."
            case .writeFailed(let description):
                return "Failed to write the signed copy: \(description)"
            }
        }
    }

    struct SignaturePlacement: Identifiable, Equatable {
        let id: UUID
        let pageIndex: Int
        var bounds: CGRect
        let signaturePNGData: Data
        let signerName: String

        init(
            id: UUID = UUID(),
            pageIndex: Int,
            bounds: CGRect,
            signaturePNGData: Data,
            signerName: String
        ) {
            self.id = id
            self.pageIndex = pageIndex
            self.bounds = bounds
            self.signaturePNGData = signaturePNGData
            self.signerName = signerName
        }
    }

    /// The underlying PDFKit document
    var pdfDocument: PDFDocument?

    /// Immutable baseline bytes used for deterministic flattened visual signature exports.
    private var originalPDFData: Data?

    /// Signature placements added during this document session.
    var signaturePlacements: [SignaturePlacement] = []

    /// Supported content types (PDF only)
    static var readableContentTypes: [UTType] {
        [.pdf]
    }

    /// Initialize with empty document
    init() {
        self.pdfDocument = nil
        self.originalPDFData = nil
    }

    init(pdfDocument: PDFDocument?, originalPDFData: Data? = nil) {
        self.pdfDocument = pdfDocument
        self.originalPDFData = originalPDFData
    }

    /// Initialize from file configuration
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.pdfDocument = document
        self.originalPDFData = data
    }

    /// Write document to file.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = pdfDocument?.dataRepresentation() else {
            throw ExportError.cannotEncodeDocumentData
        }
        return FileWrapper(regularFileWithContents: data)
    }

    mutating func addSignaturePlacement(_ placement: SignaturePlacement) {
        signaturePlacements.append(placement)
    }

    mutating func removeSignaturePlacement(id: UUID) -> SignaturePlacement? {
        guard let index = signaturePlacements.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return signaturePlacements.remove(at: index)
    }

    /// Writes a flattened visual signature export to disk.
    func writeSignedCopy(to destinationURL: URL) throws {
        guard destinationURL.isFileURL else {
            throw ExportError.invalidDestinationURL
        }

        guard let baselineDocument = baselineDocumentForExport() else {
            throw ExportError.missingDocument
        }

        // Fast path: no placements in this session, so preserve baseline serialization.
        if signaturePlacements.isEmpty {
            let data = try baselineDataForExport()
            do {
                try data.write(to: destinationURL, options: [.atomic])
            } catch {
                throw ExportError.writeFailed(description: error.localizedDescription)
            }
            return
        }

        guard let context = CGContext(destinationURL as CFURL, mediaBox: nil, nil) else {
            throw ExportError.cannotCreatePDFContext
        }

        for index in 0..<baselineDocument.pageCount {
            guard let page = baselineDocument.page(at: index) else {
                continue
            }

            let mediaBox = page.bounds(for: .cropBox)
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            page.draw(with: .cropBox, to: context)

            let placements = signaturePlacements.filter { $0.pageIndex == index }
            for placement in placements {
                guard let image = NSImage(data: placement.signaturePNGData),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    continue
                }

                let clampedRect = CGRect(
                    x: max(mediaBox.minX, min(placement.bounds.origin.x, mediaBox.maxX - placement.bounds.width)),
                    y: max(mediaBox.minY, min(placement.bounds.origin.y, mediaBox.maxY - placement.bounds.height)),
                    width: min(placement.bounds.width, mediaBox.width),
                    height: min(placement.bounds.height, mediaBox.height)
                )
                context.draw(cgImage, in: clampedRect)
            }

            context.endPDFPage()
        }

        context.closePDF()
    }

    private func baselineDocumentForExport() -> PDFDocument? {
        if let originalPDFData, let originalDocument = PDFDocument(data: originalPDFData) {
            return originalDocument
        }
        return pdfDocument
    }

    private func baselineDataForExport() throws -> Data {
        if let originalPDFData {
            return originalPDFData
        }

        guard let encoded = pdfDocument?.dataRepresentation() else {
            throw ExportError.cannotEncodeDocumentData
        }
        return encoded
    }
}
