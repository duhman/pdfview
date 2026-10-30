import AppKit
@preconcurrency import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {
    enum ExportError: LocalizedError, Equatable {
        case cannotReplaceOriginal
        case missingDocument
        case documentLocked
        case cannotReadPage(index: Int)
        case invalidPlacementPage(index: Int)
        case cannotDecodeSignature(id: UUID)
        case cannotPreservePageGeometry
        case cannotPreserveProtectedPageGeometry(allowsPrinting: Bool)
        case cannotPreserveAccessPermissions
        case cannotPreserveNavigation
        case invalidExportedDocument
        case invalidDestinationURL
        case cannotEncodeDocumentData
        case cannotCreatePDFContext
        case writeFailed(description: String)

        var errorDescription: String? {
            switch self {
            case .cannotReplaceOriginal:
                "Choose a different name: a signed copy can't replace the original."
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
                """
                This PDF uses a page coordinate system that could not be preserved safely. \
                The destination was not changed. \
                Use Print > Save as PDF to create a normalized PDF, then reopen it and place your signatures again.
                """
            case let .cannotPreserveProtectedPageGeometry(allowsPrinting):
                """
                This PDF uses a page coordinate system that could not be preserved with password protection. \
                The destination was not changed. \
                To save a copy without password or access restrictions, turn off Keep password protection.
                """ + (allowsPrinting ? PDFViewerDocument.printRecovery : "")
            case .cannotPreserveAccessPermissions:
                """
                PDFView could not keep this PDF's access permissions with the opening password. \
                The destination was not changed. \
                Ask the document owner for an unrestricted copy, or turn off Keep password protection \
                to save a copy without password or access restrictions.
                """
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

    private static let printRecovery = " Or use Print > Save as PDF to create a normalized PDF, "
        + "then reopen it and place your signatures again."

    struct SignaturePlacement: Identifiable, Equatable, Sendable {
        let id: UUID
        let pageIndex: Int
        var bounds: CGRect
        let signaturePNGData: Data
        let signerName: String
        let kind: StampKind
        let dateText: String?

        init(
            id: UUID = UUID(),
            pageIndex: Int,
            bounds: CGRect,
            signaturePNGData: Data,
            signerName: String,
            kind: StampKind = .signature,
            dateText: String? = nil
        ) {
            self.id = id
            self.pageIndex = pageIndex
            self.bounds = bounds
            self.signaturePNGData = signaturePNGData
            self.signerName = signerName
            self.kind = kind
            self.dateText = dateText
        }
    }

    /// The underlying PDFKit document
    var pdfDocument: PDFDocument?

    /// Captured synchronously while loading, before the reader can edit any widget.
    var formBaseline: FormScan?
    var initialFormValues: [FormFieldValue]?

    /// Signature placements added during this document session.
    var signaturePlacements: [SignaturePlacement] = []

    /// The file's bytes as opened; the only thing this document ever writes back.
    private var originalData: Data?

    /// Supported content types (PDF only)
    static var readableContentTypes: [UTType] {
        [.pdf]
    }

    static var writableContentTypes: [UTType] {
        []
    }

    /// Initialize with empty document
    init() {
        pdfDocument = nil
    }

    init(pdfDocument: PDFDocument?) {
        self.pdfDocument = pdfDocument
        formBaseline = pdfDocument.flatMap(FormScan.capture)
        initialFormValues = formBaseline?.values()
    }

    /// Initialize from file configuration
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        guard let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(pdfDocument: document)
        originalData = data
    }

    /// macOS autosave writes this over the original file, so it is always the bytes the file was
    /// opened with: form entries and stamps only ever reach disk through Save Signed Copy.
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: persistedData())
    }

    func persistedData() throws -> Data {
        guard let originalData else {
            throw ExportError.cannotEncodeDocumentData
        }
        return originalData
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
}

/// The values frozen in a successfully written copy, never values read after an async suspension.
struct ExportedState: Equatable, Sendable {
    let placements: [PDFViewerDocument.SignaturePlacement]
    let formValues: [FormFieldValue]

    func matches(placements: [PDFViewerDocument.SignaturePlacement], formValues: [FormFieldValue]?) -> Bool {
        self.placements == placements && self.formValues == formValues
    }
}
