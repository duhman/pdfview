import SwiftUI
import Quartz

/// NSViewRepresentable wrapper for PDFKit's PDFView
/// Enables native PDF rendering within SwiftUI
struct PDFKitView: NSViewRepresentable {
    
    /// The PDF document to display
    var document: PDFDocument?
    
    /// Current zoom scale binding from SwiftUI
    @Binding var zoomScale: CGFloat
    
    /// Min/max zoom limits
    private let minZoomScale: CGFloat = 0.25
    private let maxZoomScale: CGFloat = 5.0
    
    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        var isUpdatingFromPDFView = false
        private var isObserving = false
        
        init(_ parent: PDFKitView) {
            self.parent = parent
        }
        
        func attach(to pdfView: PDFView) {
            self.pdfView = pdfView
            if !isObserving {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleScaleChanged(_:)),
                    name: .PDFViewScaleChanged,
                    object: pdfView
                )
                isObserving = true
            }
        }
        
        @objc private func handleScaleChanged(_ notification: Notification) {
            guard let pdfView else { return }
            let scale = max(parent.minZoomScale, min(parent.maxZoomScale, pdfView.scaleFactor))
            
            if abs(scale - parent.zoomScale) < 0.0001 {
                return
            }
            
            isUpdatingFromPDFView = true
            parent.zoomScale = scale
            isUpdatingFromPDFView = false
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    /// Creates and configures the PDFView
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        // Configure for optimal reading experience
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.pageShadowsEnabled = true
        pdfView.minScaleFactor = minZoomScale
        pdfView.maxScaleFactor = maxZoomScale
        
        context.coordinator.attach(to: pdfView)
        
        return pdfView
    }
    
    /// Updates the view when SwiftUI state changes
    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self
        nsView.document = document
        
        if context.coordinator.isUpdatingFromPDFView {
            return
        }
        
        let clampedScale = max(minZoomScale, min(maxZoomScale, zoomScale))
        if abs(clampedScale - zoomScale) > 0.0001 {
            DispatchQueue.main.async {
                self.zoomScale = clampedScale
            }
        }
        
        if abs(clampedScale - 1.0) < 0.0001 {
            if !nsView.autoScales {
                nsView.autoScales = true
            }
            return
        }
        
        nsView.autoScales = false
        if abs(nsView.scaleFactor - clampedScale) > 0.0001 {
            nsView.scaleFactor = clampedScale
        }
    }
}
