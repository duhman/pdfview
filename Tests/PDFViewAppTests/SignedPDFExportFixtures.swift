import AppKit
import CoreText
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
enum ExportFixture {
    static let marker = CGRect(x: 100, y: 120, width: 40, height: 20)

    static func document(mediaBoxes: [CGRect] = [CGRect(x: 0, y: 0, width: 400, height: 600)]) throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for var box in mediaBoxes {
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(marker)
            let text = NSAttributedString(
                string: "Original page content",
                attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black]
            )
            context.textPosition = CGPoint(x: 50, y: 500)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    static func signature() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 40,
            pixelsHigh: 20,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    static func model(_ pdf: PDFDocument, baseline: Data? = nil, signed: Bool = true) throws -> PDFViewerDocument {
        var model = PDFViewerDocument(pdfDocument: pdf, originalPDFData: baseline)
        if signed {
            try model.addSignaturePlacement(.init(
                pageIndex: 0, bounds: marker, signaturePNGData: signature(), signerName: "Tester"
            ))
        }
        return model
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static func textField(on page: PDFPage) -> PDFAnnotation {
        let field = PDFAnnotation(
            bounds: CGRect(x: 40, y: 350, width: 300, height: 40), forType: .widget, withProperties: nil
        )
        field.widgetFieldType = .text
        field.fieldName = "Contact"
        field.font = NSFont.systemFont(ofSize: 16)
        field.fontColor = .black
        field.widgetStringValue = "Baseline value"
        page.addAnnotation(field)
        return field
    }

    /// Render raw output content with /Rotate reset, so annotation appearances cannot satisfy the assertion.
    static func colorBounds(on page: PDFPage, red: Bool) throws -> CGRect? {
        let rotation = page.rotation
        page.rotation = 0
        defer { page.rotation = rotation }
        let media = page.bounds(for: .mediaBox)
        let width = Int(media.width), height = Int(media.height)
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: -media.minX, y: -media.minY)
        try context.drawPDFPage(#require(page.pageRef))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0 ..< height {
            for column in 0 ..< width {
                let offset = (row * width + column) * 4
                let matches = red
                    ? pixels[offset] > 200 && pixels[offset + 1] < 50 && pixels[offset + 2] < 50
                    : pixels[offset + 2] > 200 && pixels[offset] < 50 && pixels[offset + 1] < 50
                if matches {
                    let y = height - 1 - row
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: CGFloat(minX) + media.minX,
            y: CGFloat(minY) + media.minY,
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }
}
