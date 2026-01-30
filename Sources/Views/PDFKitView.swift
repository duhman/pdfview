import SwiftUI
import Quartz

/// NSViewRepresentable wrapper for PDFKit's PDFView
/// Enables native PDF rendering within SwiftUI
struct PDFKitView: NSViewRepresentable {
    
    /// The PDF document to display
    var document: PDFDocument?
    
    /// Creates and configures the PDFView
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        // Configure for optimal reading experience
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.pageShadowsEnabled = true
        
        return pdfView
    }
    
    /// Updates the view when SwiftUI state changes
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}
