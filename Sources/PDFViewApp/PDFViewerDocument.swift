import SwiftUI
@preconcurrency import Quartz
import UniformTypeIdentifiers

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {
    
    /// The underlying PDFKit document
    var pdfDocument: PDFDocument?
    
    /// Original data when no file URL is provided
    private var sourceData: Data?
    
    /// Supported content types (PDF only)
    static var readableContentTypes: [UTType] {
        [.pdf]
    }
    
    /// Initialize with empty document
    init() {
        self.pdfDocument = nil
        self.sourceData = nil
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
        self.sourceData = data
    }
    
    /// Write document to file (read-only for now)
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Explicitly disallow writes to enforce read-only behavior
        throw CocoaError(.fileWriteNoPermission)
    }
}
