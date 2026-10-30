import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Turns drawn strokes, typed text and imported images into the stamp PNG stored in a `SignatureProfile`.
///
/// Every path draws black ink with Core Graphics colours onto a transparent bitmap, so the output never
/// depends on the window's light or dark appearance, and every output is cropped to its ink plus `padding`.
@MainActor
enum SignatureRenderer {
    struct Rendering {
        let image: CGImage
        /// Size in points; the bitmap is `pixelScale` times larger.
        let pointSize: CGSize
        let pngData: Data
    }

    /// Where drawn strokes land in the output, in points with a bottom-left origin.
    struct DrawingLayout {
        let scale: CGFloat
        let lineWidth: CGFloat
        let outputSize: CGSize
        let canvasInkRect: CGRect

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - canvasInkRect.minX) * scale + SignatureRenderer.padding,
                y: outputSize.height - ((point.y - canvasInkRect.minY) * scale + SignatureRenderer.padding)
            )
        }
    }

    static let maximumSize = CGSize(width: 600, height: 200)
    nonisolated static let padding: CGFloat = 8
    static let pixelScale: CGFloat = 2
    /// Pen width as a share of the drawing canvas height. On the 180pt-tall canvas this is a 4pt pen,
    /// which prints at roughly 1.6-2pt when a typical signature is placed 180pt wide.
    static let inkWidthRatio: CGFloat = 0.022

    static let scriptFontNames = ["SnellRoundhand", "SavoyeLetPlain", "SignPainter-HouseScript"]
    static var availableScriptFonts: [String] {
        scriptFontNames.filter { NSFont(name: $0, size: 12) != nil }
    }

    private static let typedFontSize: CGFloat = 64
    private static let inkColor = CGColor(gray: 0, alpha: 1)

    // MARK: Drawn

    static func inkWidth(forCanvasHeight height: CGFloat) -> CGFloat {
        height * inkWidthRatio
    }

    /// One uniform scale for both axes, so the signature keeps its shape. The drawing is never enlarged
    /// beyond what the canvas itself would map to, so a lone dot or a flat line stays small.
    static func drawingLayout(strokes: [[CGPoint]], canvasSize: CGSize) -> DrawingLayout? {
        // Bounds of the smoothed curves, not the raw samples: the curves cut inside sharp turns.
        let strokeBounds = strokes.compactMap { stroke -> CGRect? in
            guard let first = stroke.first else {
                return nil
            }
            if stroke.allSatisfy({ $0 == first }) {
                return CGRect(origin: first, size: .zero)
            }
            return smoothedPath(for: stroke).boundingBoxOfPath
        }
        guard let firstBounds = strokeBounds.first, canvasSize.height > 0 else {
            return nil
        }

        let canvasLineWidth = inkWidth(forCanvasHeight: canvasSize.height)
        let curveBounds = strokeBounds.dropFirst().reduce(firstBounds) { $0.union($1) }
        let inkRect = curveBounds.insetBy(dx: -canvasLineWidth / 2, dy: -canvasLineWidth / 2)
        let scale = min(
            (maximumSize.width - 2 * padding) / inkRect.width,
            (maximumSize.height - 2 * padding) / inkRect.height,
            maximumSize.height / canvasSize.height
        )
        let outputSize = CGSize(
            width: inkRect.width * scale + 2 * padding,
            height: inkRect.height * scale + 2 * padding
        )
        return DrawingLayout(
            scale: scale,
            lineWidth: canvasLineWidth * scale,
            outputSize: outputSize,
            canvasInkRect: inkRect
        )
    }

    static func renderDrawing(strokes: [[CGPoint]], canvasSize: CGSize) -> Rendering? {
        guard let layout = drawingLayout(strokes: strokes, canvasSize: canvasSize) else {
            return nil
        }

        return render(pointSize: layout.outputSize) { context in
            context.setStrokeColor(inkColor)
            context.setFillColor(inkColor)
            context.setLineWidth(layout.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for stroke in strokes where !stroke.isEmpty {
                let mapped = stroke.map(layout.map)
                if let dot = dotRect(for: mapped, lineWidth: layout.lineWidth) {
                    context.fillEllipse(in: dot)
                } else {
                    context.addPath(smoothedPath(for: mapped))
                    context.strokePath()
                }
            }
        }
    }

    /// A filled circle for strokes that never moved (a tap, an i-dot or a full stop).
    static func dotRect(for stroke: [CGPoint], lineWidth: CGFloat) -> CGRect? {
        guard let first = stroke.first, stroke.allSatisfy({ $0 == first }) else {
            return nil
        }
        return CGRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2, width: lineWidth, height: lineWidth)
    }

    /// Quadratic curves through the midpoints of consecutive samples, so fast curves don't show corners.
    static func smoothedPath(for stroke: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = stroke.first else {
            return path
        }
        path.move(to: first)
        guard stroke.count > 2 else {
            stroke.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1 ..< (stroke.count - 1) {
            let control = stroke[index]
            let next = stroke[index + 1]
            path.addQuadCurve(to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2), control: control)
        }
        if let last = stroke.last {
            path.addLine(to: last)
        }
        return path
    }

    // MARK: Typed

    /// Measures the glyph ink first and shrinks the font until the name fits, so long names never clip.
    static func renderText(_ text: String, fontName: String) -> Rendering? {
        renderText(text) { size in
            NSFont(name: fontName, size: size)
                ?? NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
        }
    }

    static func renderText(_ text: String, font: (CGFloat) -> NSFont) -> Rendering? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var size = typedFontSize
        var line = typedLine(trimmed, font: font(size))
        var inkBounds = CTLineGetImageBounds(line, nil)
        // Optically sized fonts (the system font) get wider as they shrink, so one pass can still overflow.
        for _ in 0 ..< 4 {
            let fit = min(
                (maximumSize.width - 2 * padding) / max(inkBounds.width, 1),
                (maximumSize.height - 2 * padding) / max(inkBounds.height, 1)
            )
            // The first pass alone fits a script face, so its rendering is unchanged by the extra passes.
            guard fit < (size == typedFontSize ? 1 : 0.999) else { break }
            size *= fit
            line = typedLine(trimmed, font: font(size))
            inkBounds = CTLineGetImageBounds(line, nil)
        }
        guard inkBounds.width > 0, inkBounds.height > 0 else {
            return nil
        }

        let pointSize = CGSize(width: inkBounds.width + 2 * padding, height: inkBounds.height + 2 * padding)
        return render(pointSize: pointSize) { context in
            context.setFillColor(inkColor)
            context.textPosition = CGPoint(x: padding - inkBounds.minX, y: padding - inkBounds.minY)
            CTLineDraw(line, context)
        }
    }

    private static func typedLine(_ text: String, font: NSFont) -> CTLine {
        let inkFromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, inkFromContext: true]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    // MARK: Date stamps

    static func dateText(
        _ date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// A date is read rather than signed, so it is set in the system font instead of a script face.
    static func dateFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    /// Uses the same fixed black ink, transparent backing and fit rules as typed signatures.
    static func renderDate(
        _ date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Rendering? {
        renderText(
            dateText(date, locale: locale, timeZone: timeZone),
            font: dateFont(size:)
        )
    }

    // MARK: Imported

    static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Optionally makes near-white paper transparent, then crops to the remaining ink and fits the stamp size.
    static func renderImport(_ image: CGImage, removingWhiteBackground: Bool) -> Rendering? {
        // Work at up to twice the largest stamp's pixel width so a photographed page keeps enough detail.
        let processingLongSide = Int(maximumSize.width * pixelScale * 2)
        guard var bitmap = Bitmap(image: image, fittingLongSide: processingLongSide) else {
            return nil
        }
        if removingWhiteBackground {
            bitmap.removeWhiteBackground()
        }
        guard let inkRect = bitmap.inkBounds(),
              let ink = bitmap.makeImage()?.cropping(to: inkRect)
        else {
            return nil
        }

        let inkPointSize = CGSize(width: inkRect.width / pixelScale, height: inkRect.height / pixelScale)
        let scale = min(
            1,
            (maximumSize.width - 2 * padding) / inkPointSize.width,
            (maximumSize.height - 2 * padding) / inkPointSize.height
        )
        let drawSize = CGSize(width: inkPointSize.width * scale, height: inkPointSize.height * scale)
        let pointSize = CGSize(width: drawSize.width + 2 * padding, height: drawSize.height + 2 * padding)
        return render(pointSize: pointSize) { context in
            context.interpolationQuality = .high
            context.draw(ink, in: CGRect(origin: CGPoint(x: padding, y: padding), size: drawSize))
        }
    }

    /// How much of a pixel's alpha survives background removal, from its darkest RGB channel (0-255).
    /// Paper (215 and lighter) fades out over a short ramp so antialiased ink edges don't leave a halo.
    nonisolated static func backgroundAlphaFactor(minimumChannel: UInt8) -> CGFloat {
        let opaqueBelow: CGFloat = 215
        let transparentFrom: CGFloat = 245
        let value = CGFloat(minimumChannel)
        return min(1, max(0, (transparentFrom - value) / (transparentFrom - opaqueBelow)))
    }

    // MARK: Output

    private static func render(pointSize: CGSize, draw: (CGContext) -> Void) -> Rendering? {
        let width = Int((pointSize.width * pixelScale).rounded(.up))
        let height = Int((pointSize.height * pixelScale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: Bitmap.colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: pixelScale, y: pixelScale)
        draw(context)

        guard let image = context.makeImage(), let pngData = pngData(for: image) else {
            return nil
        }
        return Rendering(image: image, pointSize: pointSize, pngData: pngData)
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * pixelScale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

/// An 8-bit premultiplied RGBA copy of an image that can be edited pixel by pixel.
private struct Bitmap {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let width: Int
    let height: Int
    private var pixels: [UInt8]

    init?(image: CGImage, fittingLongSide maximumLongSide: Int) {
        let scale = min(1, CGFloat(maximumLongSide) / CGFloat(max(image.width, image.height)))
        width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        pixels = [UInt8](repeating: 0, count: width * height * 4)

        let (width, height) = (width, height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: Self.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            return nil
        }
    }

    mutating func removeWhiteBackground() {
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            guard alpha > 0 else {
                continue
            }
            // Un-premultiply to judge the colour itself, not how transparent it already is.
            let darkest = min(pixels[offset], pixels[offset + 1], pixels[offset + 2])
            let unpremultiplied = UInt8(min(255, Int(darkest) * 255 / Int(alpha)))
            let factor = SignatureRenderer.backgroundAlphaFactor(minimumChannel: unpremultiplied)
            guard factor < 1 else {
                continue
            }
            for channel in 0 ..< 4 {
                pixels[offset + channel] = UInt8((CGFloat(pixels[offset + channel]) * factor).rounded())
            }
        }
    }

    /// Bounding box of visible pixels, in pixels with a top-left origin (the layout `CGImage.cropping` expects).
    func inkBounds() -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0 ..< height {
            for column in 0 ..< width where pixels[(row * width + column) * 4 + 3] > 8 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
