import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import PDFViewApp

private enum Fixture {
    static let canvasSize = CGSize(width: 520, height: 180)
}

/// A wavy line spanning `width` x `height` canvas points, sampled densely like a real drag gesture.
private func scrawl(width: CGFloat, height: CGFloat, origin: CGPoint = CGPoint(x: 60, y: 60)) -> [[CGPoint]] {
    let samples = 400
    let points = (0 ... samples).map { index -> CGPoint in
        let progress = CGFloat(index) / CGFloat(samples)
        let wave = (1 - cos(progress * 8 * .pi)) / 2
        return CGPoint(x: origin.x + width * progress, y: origin.y + height * wave)
    }
    return [points]
}

/// Ink bounding box in pixels (top-left origin), measured independently of the renderer.
private func measuredInkBounds(_ image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drewImage else { return nil }

    var minX = width, minY = height, maxX = -1, maxY = -1
    for row in 0 ..< height {
        for column in 0 ..< width where pixels[(row * width + column) * 4 + 3] > 16 {
            minX = min(minX, column)
            maxX = max(maxX, column)
            minY = min(minY, row)
            maxY = max(maxY, row)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

private func alpha(atX x: Int, y: Int, in image: CGImage) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    }
    return pixel[3]
}

// MARK: - Drawn signatures

@MainActor
@Test
func drawnScrawlKeepsItsAspectRatio() throws {
    let strokes = scrawl(width: 400, height: 60)
    let layout = try #require(SignatureRenderer.drawingLayout(strokes: strokes, canvasSize: Fixture.canvasSize))

    let mappedPoints = strokes.flatMap(\.self).map(layout.map)
    let mappedWidth = try #require(mappedPoints.map(\.x).max()) - (mappedPoints.map(\.x).min() ?? 0)
    let mappedHeight = try #require(mappedPoints.map(\.y).max()) - (mappedPoints.map(\.y).min() ?? 0)
    #expect(abs((mappedWidth / mappedHeight) / (400.0 / 60.0) - 1) < 0.02)

    // The rendered ink (curves plus pen width) must match the same uniform scale.
    let rendering = try #require(SignatureRenderer.renderDrawing(strokes: strokes, canvasSize: Fixture.canvasSize))
    let ink = try #require(measuredInkBounds(rendering.image))
    let lineWidth = SignatureRenderer.inkWidth(forCanvasHeight: Fixture.canvasSize.height)
    #expect(abs((ink.width / ink.height) / ((400 + lineWidth) / (60 + lineWidth)) - 1) < 0.02)
}

@MainActor
@Test
func nearlyFlatStrokeIsNotBlownUpVertically() throws {
    let stroke = [CGPoint(x: 20, y: 90), CGPoint(x: 260, y: 91), CGPoint(x: 500, y: 90)]
    let layout = try #require(SignatureRenderer.drawingLayout(strokes: [stroke], canvasSize: Fixture.canvasSize))

    #expect(layout.outputSize.height < 40)
    let rendering = try #require(SignatureRenderer.renderDrawing(strokes: [stroke], canvasSize: Fixture.canvasSize))
    let ink = try #require(measuredInkBounds(rendering.image))
    let pixelLineWidth = layout.lineWidth * SignatureRenderer.pixelScale
    #expect(ink.height <= 1 * layout.scale * SignatureRenderer.pixelScale + pixelLineWidth + 2)
    #expect(ink.width > 20 * ink.height)
}

@MainActor
@Test
func drawnInkPrintsAtPenWeightOnADefaultSizedStamp() throws {
    let layout = try #require(SignatureRenderer.drawingLayout(
        strokes: scrawl(width: 400, height: 60),
        canvasSize: Fixture.canvasSize
    ))
    // PDFKitView places a new stamp 180pt wide.
    let printedLineWidth = layout.lineWidth * 180 / layout.outputSize.width
    #expect(printedLineWidth >= 1.4)
    #expect(printedLineWidth <= 2.2)
}

@MainActor
@Test
func singleTapRendersAVisibleDot() throws {
    let rendering = try #require(SignatureRenderer.renderDrawing(
        strokes: [[CGPoint(x: 100, y: 100)]],
        canvasSize: Fixture.canvasSize
    ))
    let ink = try #require(measuredInkBounds(rendering.image))
    #expect(ink.width >= 4)
    #expect(ink.height >= 4)
}

@MainActor
@Test
func iDotNextToAStrokeIsKept() throws {
    let stroke = [CGPoint(x: 40, y: 120), CGPoint(x: 80, y: 60), CGPoint(x: 120, y: 120)]
    let dot = [CGPoint(x: 300, y: 40)]
    let rendering = try #require(SignatureRenderer.renderDrawing(
        strokes: [stroke, dot],
        canvasSize: Fixture.canvasSize
    ))
    let ink = try #require(measuredInkBounds(rendering.image))
    let layout = try #require(SignatureRenderer.drawingLayout(strokes: [stroke, dot], canvasSize: Fixture.canvasSize))
    // Ink spans from the stroke to the dot, so the dot is in the image.
    #expect(ink.width >= (260 * layout.scale) * SignatureRenderer.pixelScale)
}

@MainActor
@Test
func drawnOutputIsCroppedTransparentAndTwiceScale() throws {
    let rendering = try #require(SignatureRenderer.renderDrawing(
        strokes: scrawl(width: 300, height: 80),
        canvasSize: Fixture.canvasSize
    ))
    #expect(rendering.image.width == Int((rendering.pointSize.width * 2).rounded(.up)))
    #expect(rendering.image.height == Int((rendering.pointSize.height * 2).rounded(.up)))
    #expect(alpha(atX: 0, y: 0, in: rendering.image) == 0)
    #expect(alpha(atX: rendering.image.width - 1, y: rendering.image.height - 1, in: rendering.image) == 0)

    let ink = try #require(measuredInkBounds(rendering.image))
    let padding = SignatureRenderer.padding * SignatureRenderer.pixelScale
    #expect(ink.minX >= padding - 2 && ink.minX <= padding + 2)
    #expect(ink.minY >= padding - 2 && ink.minY <= padding + 2)

    let decoded = try #require(SignatureRenderer.decodeImage(rendering.pngData))
    #expect(decoded.width == rendering.image.width)
}

@MainActor
@Test
func emptyDrawingRendersNothing() {
    #expect(SignatureRenderer.renderDrawing(strokes: [], canvasSize: Fixture.canvasSize) == nil)
    #expect(SignatureRenderer.renderDrawing(strokes: [[]], canvasSize: Fixture.canvasSize) == nil)
}

@MainActor
@Test
func smoothedPathUsesCurvesThroughMidpoints() {
    let zigzag = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 10)]
    let path = SignatureRenderer.smoothedPath(for: zigzag)
    var quadCurves = 0
    var lines = 0
    path.applyWithBlock { element in
        switch element.pointee.type {
        case .addQuadCurveToPoint: quadCurves += 1
        case .addLineToPoint: lines += 1
        default: break
        }
    }
    #expect(quadCurves == 2)
    #expect(lines == 1)
}

// MARK: - Typed signatures

@MainActor
@Test
func longTypedNameFitsWithoutClipping() throws {
    for fontName in SignatureRenderer.availableScriptFonts {
        let rendering = try #require(SignatureRenderer.renderText(
            "Alexandra Montgomery-Fitzgerald",
            fontName: fontName
        ))
        #expect(rendering.pointSize.width <= SignatureRenderer.maximumSize.width + 1)
        #expect(rendering.pointSize.height <= SignatureRenderer.maximumSize.height + 1)

        // Clipped glyphs would leave ink on the image edge.
        let ink = try #require(measuredInkBounds(rendering.image))
        #expect(ink.minX > 0 && ink.minY > 0, "\(fontName)")
        #expect(ink.maxX < CGFloat(rendering.image.width), "\(fontName)")
        #expect(ink.maxY < CGFloat(rendering.image.height), "\(fontName)")
    }
}

@MainActor
@Test
func shortTypedNameFillsTheStamp() throws {
    let rendering = try #require(SignatureRenderer.renderText("Al Li", fontName: "SnellRoundhand"))
    let ink = try #require(measuredInkBounds(rendering.image))
    #expect(ink.width / CGFloat(rendering.image.width) > 0.8)
    #expect(ink.height / CGFloat(rendering.image.height) > 0.6)
}

@MainActor
@Test
func blankTypedTextRendersNothing() {
    #expect(SignatureRenderer.renderText("   ", fontName: "SnellRoundhand") == nil)
}

@MainActor
@Test
func scriptFontsExistAndUnknownFontFallsBack() {
    #expect(!SignatureRenderer.availableScriptFonts.isEmpty)
    for fontName in SignatureRenderer.availableScriptFonts {
        #expect(NSFont(name: fontName, size: 12) != nil)
    }
    let rendering = SignatureRenderer.renderText("Jane Appleseed", fontName: "No Such Font 123")
    #expect(rendering != nil)
}

// MARK: - Appearance independence

@MainActor
@Test
func darkAppearanceDoesNotChangeExportedPNG() throws {
    func renderAll(in appearanceName: NSAppearance.Name) throws -> [Data] {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var outputs: [Data] = []
        appearance.performAsCurrentDrawingAppearance {
            outputs.append(SignatureRenderer.renderDrawing(
                strokes: scrawl(width: 300, height: 60),
                canvasSize: Fixture.canvasSize
            )?.pngData ?? Data())
            outputs
                .append(SignatureRenderer.renderText("Jane Appleseed", fontName: "SnellRoundhand")?.pngData ?? Data())
        }
        return outputs
    }

    let light = try renderAll(in: .aqua)
    let dark = try renderAll(in: .darkAqua)
    #expect(light.allSatisfy { !$0.isEmpty })
    #expect(light == dark)
}

// MARK: - Imported images

/// An opaque white image with a black bar in the middle, like a scanned signature.
private func scannedSignature(width: Int = 200, height: Int = 100) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 50, y: 40, width: 100, height: 20))
    return try #require(context.makeImage())
}

@MainActor
@Test
func importRemovesWhiteBackgroundAndCropsToInk() throws {
    let rendering = try #require(try SignatureRenderer.renderImport(scannedSignature(), removingWhiteBackground: true))
    let ink = try #require(measuredInkBounds(rendering.image))
    let padding = SignatureRenderer.padding * SignatureRenderer.pixelScale
    #expect(abs(ink.minX - padding) <= 1)
    #expect(abs(ink.minY - padding) <= 1)
    #expect(abs(ink.width / ink.height - 100.0 / 20.0) < 0.1)
    #expect(alpha(atX: Int(ink.midX), y: Int(ink.midY), in: rendering.image) == 255)
}

@MainActor
@Test
func importKeepsBackgroundWhenToggleIsOff() throws {
    let rendering = try #require(try SignatureRenderer.renderImport(scannedSignature(), removingWhiteBackground: false))
    let ink = try #require(measuredInkBounds(rendering.image))
    // The whole white sheet is kept as ink (200x100).
    #expect(abs(ink.width / ink.height - 2) < 0.05)
    #expect(alpha(atX: Int(ink.minX) + 2, y: Int(ink.minY) + 2, in: rendering.image) == 255)
}

@MainActor
@Test
func backgroundAlphaRampKeepsInkAndDropsPaper() {
    #expect(SignatureRenderer.backgroundAlphaFactor(minimumChannel: 255) == 0)
    #expect(SignatureRenderer.backgroundAlphaFactor(minimumChannel: 248) == 0)
    #expect(SignatureRenderer.backgroundAlphaFactor(minimumChannel: 0) == 1)
    #expect(SignatureRenderer.backgroundAlphaFactor(minimumChannel: 190) == 1)
    let middle = SignatureRenderer.backgroundAlphaFactor(minimumChannel: 230)
    #expect(middle > 0 && middle < 1)
}

@MainActor
@Test
func undecodableDataIsRejected() {
    #expect(SignatureRenderer.decodeImage(Data([0x89, 0x50, 0x4E, 0x47])) == nil)
    #expect(SignatureRenderer.decodeImage(Data("not an image".utf8)) == nil)
}

// MARK: - Date stamps

@MainActor
@Test
func dateStampUsesLocaleMediumStyleAndCustomFormat() throws {
    let date = Date(timeIntervalSince1970: 1_767_355_200) // 2026-01-02 12:00 UTC
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    #expect(SignatureRenderer.dateText(date, locale: Locale(identifier: "en_US"), timeZone: zone) == "Jan 2, 2026")
    #expect(SignatureRenderer.dateText(date, locale: Locale(identifier: "en_GB"), timeZone: zone) == "2 Jan 2026")
    #expect(SignatureRenderer.dateText(
        date, locale: Locale(identifier: "en_US"), timeZone: zone, customFormat: "yyyy-MM-dd"
    ) == "2026-01-02")
    #expect(SignatureRenderer.dateText(
        date, locale: Locale(identifier: "en_US"), timeZone: zone, customFormat: "  "
    ) == "Jan 2, 2026")
}

@MainActor
@Test
func dateStampSharesTypedInkSizingAndTransparency() throws {
    let date = Date(timeIntervalSince1970: 1_767_355_200)
    let locale = Locale(identifier: "en_US")
    let stamp = try #require(SignatureRenderer.renderDate(date, locale: locale))
    let text = SignatureRenderer.dateText(date, locale: locale)
    let typed = try #require(SignatureRenderer.renderText(text, font: SignatureRenderer.dateFont(size:)))
    #expect(stamp.pngData == typed.pngData)
    #expect(stamp.pointSize.width <= SignatureRenderer.maximumSize.width + 1)
    #expect(stamp.pointSize.height <= SignatureRenderer.maximumSize.height + 1)
    #expect(alpha(atX: 0, y: 0, in: stamp.image) == 0)
    #expect(alpha(atX: stamp.image.width - 1, y: stamp.image.height - 1, in: stamp.image) == 0)
    #expect(measuredInkBounds(stamp.image) != nil)
    #expect(SignatureRenderer.decodeImage(stamp.pngData) != nil)
    let long = try #require(SignatureRenderer.renderDate(
        date,
        customFormat: String(repeating: "EEEE MMMM ", count: 10)
    ))
    #expect(long.pointSize.width <= SignatureRenderer.maximumSize.width + 1)
}

/// A date is read, not signed: it uses the system font at medium weight, not a script face.
@MainActor
@Test
func dateStampUsesTheSystemFontAtMediumWeight() throws {
    let font = SignatureRenderer.dateFont(size: 64)
    #expect(font.familyName == NSFont.systemFont(ofSize: 64).familyName)
    let traits = try #require(font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])
    let weight = try #require(traits[.weight] as? CGFloat)
    #expect(abs(weight - NSFont.Weight.medium.rawValue) < 0.01)
    #expect(!font.fontDescriptor.symbolicTraits.contains(.italic))

    let date = Date(timeIntervalSince1970: 1_767_355_200)
    let script = try #require(SignatureRenderer.renderText(
        SignatureRenderer.dateText(date),
        fontName: "SnellRoundhand"
    ))
    #expect(SignatureRenderer.renderDate(date)?.pngData != script.pngData)
}

@MainActor
@Test
func dateStampIsIndependentOfAppearance() throws {
    let date = Date(timeIntervalSince1970: 1_767_355_200)
    var light: Data?
    var dark: Data?
    try #require(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance {
        light = SignatureRenderer.renderDate(date)?.pngData
    }
    try #require(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance {
        dark = SignatureRenderer.renderDate(date)?.pngData
    }
    #expect(light != nil)
    #expect(light == dark)
}
