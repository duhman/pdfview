import SwiftUI
import Quartz

/// Main content view for PDF documents
/// Provides the SwiftUI interface wrapping the PDFKit view
struct PDFContentView: View {
    
    /// The document binding from DocumentGroup
    @Binding var document: PDFViewerDocument
    
    /// Current zoom scale
    @State private var zoomScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // PDF Viewer takes full available space
                PDFKitView(document: document.pdfDocument)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Zoom controls
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom Out")
                
                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)
                .help("Zoom In")
                
                Button(action: resetZoom) {
                    Image(systemName: "arrow.uturn.left.circle")
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Reset Zoom")
            }
        }
    }
    
    /// Zoom in by 25%
    private func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 5.0)
    }
    
    /// Zoom out by 25%
    private func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 0.25)
    }
    
    /// Reset zoom to default
    private func resetZoom() {
        zoomScale = 1.0
    }
}

#Preview {
    PDFContentView(document: .constant(PDFViewerDocument()))
}
