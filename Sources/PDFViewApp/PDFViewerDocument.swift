import SwiftUI
import Quartz
import UniformTypeIdentifiers

/// Document model for PDF files conforming to FileDocument protocol
struct PDFViewerDocument: FileDocument {
    
    /// The underlying PDFKit document
    var pdfDocument: PDFDocument?
    
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
    
    /// Write document to file (read-only for now)
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Return empty data since we're read-only
        return FileWrapper(regularFileWithContents: Data())
    }
}
