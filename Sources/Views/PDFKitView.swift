import SwiftUI
import Quartz
import AppKit

/// NSViewRepresentable wrapper for PDFKit's PDFView
/// Enables native PDF rendering within SwiftUI
struct PDFKitView: NSViewRepresentable {

    /// The PDF document to display
    var document: PDFDocument?

    /// Signature placements from the document model.
    var signaturePlacements: [PDFViewerDocument.SignaturePlacement]

    /// Current zoom scale binding from SwiftUI
    @Binding var zoomScale: CGFloat

    /// Current signing mode.
    var signingMode: SigningMode

    /// Current profile used to place signatures.
    var signatureProfile: SignatureProfile?

    /// Callback when a new placement was added in the PDF view.
    var onSignaturePlacement: (PDFViewerDocument.SignaturePlacement) -> Void

    /// Callback when available signature fields are detected.
    var onSignatureFieldAvailability: (Bool) -> Void

    /// Min/max zoom limits
    private let minZoomScale: CGFloat = 0.25
    private let maxZoomScale: CGFloat = 5.0

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: SigningPDFView?
        var isUpdatingFromPDFView = false
        private var isObserving = false

        private var hasReportedFieldAvailabilityForDocument = false
        private var placementAnnotations: [UUID: PDFAnnotation] = [:]

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        func attach(to pdfView: SigningPDFView) {
            self.pdfView = pdfView
            pdfView.signatureTapHandler = { [weak self] page, pagePoint, annotation in
                self?.handleTap(page: page, pagePoint: pagePoint, annotation: annotation)
            }

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

        func updateDocument(_ document: PDFDocument?) {
            if pdfView?.document !== document {
                hasReportedFieldAvailabilityForDocument = false
                placementAnnotations.removeAll()
            }

            guard !hasReportedFieldAvailabilityForDocument else { return }
            let hasFields = document.map(Self.documentHasSignatureFields) ?? false
            parent.onSignatureFieldAvailability(hasFields)
            hasReportedFieldAvailabilityForDocument = true
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

        func syncPlacements() {
            guard let pdfView, let document = pdfView.document else {
                placementAnnotations.removeAll()
                return
            }

            let desiredPlacementsByID = Dictionary(uniqueKeysWithValues: parent.signaturePlacements.map { ($0.id, $0) })
            let currentIDs = Set(placementAnnotations.keys)
            let desiredIDs = Set(desiredPlacementsByID.keys)

            for removedID in currentIDs.subtracting(desiredIDs) {
                guard let annotation = placementAnnotations[removedID],
                      let page = annotation.page
                else {
                    placementAnnotations.removeValue(forKey: removedID)
                    continue
                }

                page.removeAnnotation(annotation)
                placementAnnotations.removeValue(forKey: removedID)
            }

            for addedID in desiredIDs.subtracting(currentIDs) {
                guard let placement = desiredPlacementsByID[addedID],
                      let page = document.page(at: placement.pageIndex),
                      let image = NSImage(data: placement.signaturePNGData)
                else {
                    continue
                }

                let clampedBounds = Self.clamped(rect: placement.bounds, to: page.bounds(for: .cropBox))
                let annotation = SignatureImageAnnotation(
                    bounds: clampedBounds,
                    image: image,
                    signerName: placement.signerName
                )
                page.addAnnotation(annotation)
                placementAnnotations[addedID] = annotation
            }
        }

        private func handleTap(page: PDFPage, pagePoint: CGPoint, annotation: PDFAnnotation?) {
            guard parent.signingMode != .idle,
                  let profile = parent.signatureProfile,
                  let imageData = profile.signaturePNGData,
                  let image = NSImage(data: imageData)
            else {
                return
            }

            let isSignatureFieldTap = annotation.map(Self.isSignatureWidgetAnnotation) ?? false

            if !isSignatureFieldTap && !parent.signingMode.allowsFreePlacement {
                return
            }

            let bounds: CGRect
            if isSignatureFieldTap, let annotationBounds = annotation?.bounds {
                bounds = Self.clamped(rect: annotationBounds, to: page.bounds(for: .cropBox))
            } else {
                bounds = Self.defaultPlacementRect(
                    around: pagePoint,
                    image: image,
                    pageBounds: page.bounds(for: .cropBox)
                )
            }

            guard let pageIndex = parent.document?.index(for: page), pageIndex >= 0 else {
                return
            }

            let placement = PDFViewerDocument.SignaturePlacement(
                pageIndex: pageIndex,
                bounds: bounds,
                signaturePNGData: imageData,
                signerName: profile.fullName
            )

            parent.onSignaturePlacement(placement)
        }

        private static func documentHasSignatureFields(_ document: PDFDocument) -> Bool {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else {
                    continue
                }

                if page.annotations.contains(where: isSignatureWidgetAnnotation) {
                    return true
                }
            }

            return false
        }

        private static func isSignatureWidgetAnnotation(_ annotation: PDFAnnotation) -> Bool {
            if annotation.widgetFieldType == .signature {
                return true
            }

            let fieldName = annotation.fieldName?.lowercased() ?? ""
            let subtypeString = annotation.widgetFieldType.rawValue.lowercased()
            return fieldName.contains("sig") || subtypeString.contains("sig")
        }

        private static func defaultPlacementRect(around point: CGPoint, image: NSImage, pageBounds: CGRect) -> CGRect {
            let defaultWidth: CGFloat = 180
            let imageSize = image.size
            let imageAspect = max(0.2, min(8.0, imageSize.width / max(imageSize.height, 1)))
            let defaultHeight = defaultWidth / imageAspect

            let origin = CGPoint(
                x: point.x - defaultWidth / 2,
                y: point.y - defaultHeight / 2
            )
            return clamped(rect: CGRect(origin: origin, size: CGSize(width: defaultWidth, height: defaultHeight)), to: pageBounds)
        }

        private static func clamped(rect: CGRect, to bounds: CGRect) -> CGRect {
            let width = min(rect.width, bounds.width)
            let height = min(rect.height, bounds.height)
            let x = max(bounds.minX, min(rect.origin.x, bounds.maxX - width))
            let y = max(bounds.minY, min(rect.origin.y, bounds.maxY - height))

            return CGRect(x: x, y: y, width: width, height: height)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Creates and configures the PDFView
    func makeNSView(context: Context) -> SigningPDFView {
        let pdfView = SigningPDFView()

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
    func updateNSView(_ nsView: SigningPDFView, context: Context) {
        context.coordinator.parent = self
        nsView.document = document
        context.coordinator.updateDocument(document)
        context.coordinator.syncPlacements()

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

@MainActor
final class SigningPDFView: PDFView {
    var signatureTapHandler: ((PDFPage, CGPoint, PDFAnnotation?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else {
            super.mouseDown(with: event)
            return
        }

        let pagePoint = convert(viewPoint, to: page)
        let annotation = page.annotation(at: pagePoint)
        signatureTapHandler?(page, pagePoint, annotation)
        super.mouseDown(with: event)
    }
}

final class SignatureImageAnnotation: PDFAnnotation {
    private let signatureImage: NSImage
    private let signerName: String

    init(bounds: CGRect, image: NSImage, signerName: String) {
        self.signatureImage = image
        self.signerName = signerName
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)

        color = .clear
        border = nil
        shouldDisplay = true
        shouldPrint = true
        contents = signerName
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        context.saveGState()
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}
