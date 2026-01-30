import SwiftUI

/// Main application entry point
/// Uses DocumentGroup for native document-based app architecture
@main
struct PDFViewApp: App {
    
    var body: some Scene {
        DocumentGroup(viewing: PDFViewerDocument.self) { file in
            PDFContentView(document: file.$document)
        }
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.titleBar)
    }
}
