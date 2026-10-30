import SwiftUI
@preconcurrency import Quartz
import UniformTypeIdentifiers
import AppKit

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {
    enum ExportError: LocalizedError, Equatable {
        case missingDocument
        case documentLocked
        case cannotReadPage(index: Int)
        case invalidPlacementPage(index: Int)
        case cannotDecodeSignature(id: UUID)
        case cannotPreservePageGeometry
        case cannotPreserveNavigation
        case invalidExportedDocument
        case invalidDestinationURL
        case cannotEncodeDocumentData
        case cannotCreatePDFContext
        case writeFailed(description: String)

        var errorDescription: String? {
            switch self {
            case .missingDocument:
                "No PDF document is loaded."
            case .documentLocked:
                "Unlock the PDF document before exporting a signed copy."
            case let .cannotReadPage(index):
                "Could not read PDF page \(index + 1)."
            case let .invalidPlacementPage(index):
                "A signature refers to missing PDF page \(index + 1)."
            case let .cannotDecodeSignature(id):
                "Could not decode the signature image (\(id))."
            case .cannotPreservePageGeometry:
                "Could not preserve the PDF page coordinate system."
            case .cannotPreserveNavigation:
                "Could not preserve the PDF's links or bookmarks."
            case .invalidExportedDocument:
                "The exported PDF could not be validated. The destination was not changed."
            case .invalidDestinationURL:
                "The destination must be a local file URL."
            case .cannotEncodeDocumentData:
                "The PDF data could not be encoded."
            case .cannotCreatePDFContext:
                "Could not create a PDF writing context."
            case let .writeFailed(description):
                "Failed to write the signed copy: \(description)"
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

    /// Writes the live document with form values and visual signatures flattened into page content.
    @MainActor
    func writeSignedCopy(to destinationURL: URL) throws {
        guard destinationURL.isFileURL else {
            throw ExportError.invalidDestinationURL
        }
        guard let pdfDocument else {
            throw ExportError.missingDocument
        }
        try SignedPDFExporter.write(pdfDocument, placements: signaturePlacements, to: destinationURL)
    }
}
