import SwiftUI
@preconcurrency import Quartz
import UniformTypeIdentifiers
import AppKit

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {

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

    /// Signature placements added during this document session.
    var signaturePlacements: [SignaturePlacement] = []

    /// Supported content types (PDF only)
    static var readableContentTypes: [UTType] {
        [.pdf]
    }

    /// Initialize with empty document
    init() {
        self.pdfDocument = nil
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
    }

    /// Write document to file.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = pdfDocument?.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
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

    func writeSignedCopy(to destinationURL: URL) throws {
        guard let pdfDocument else {
            throw CocoaError(.fileWriteUnknown)
        }

        // Fast path: no placements in this session, so preserve original PDF serialization.
        if signaturePlacements.isEmpty {
            guard let data = pdfDocument.dataRepresentation() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: destinationURL, options: [.atomic])
            return
        }

        guard let context = CGContext(destinationURL as CFURL, mediaBox: nil, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for index in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) else {
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
}
