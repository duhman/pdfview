import AppKit
import Foundation

/// Run from the repository root: swift scripts/make-icon.swift
/// The editable artwork and iconset are build artifacts; only AppIcon.icns is shipped.
enum IconError: Error {
    case bitmapCreation
    case imageEncoding
    case iconutilFailed(Int32)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func squircle() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 320, y: 80))
    path.addLine(to: CGPoint(x: 704, y: 80))
    path.addCurve(
        to: CGPoint(x: 944, y: 320),
        control1: CGPoint(x: 884, y: 80),
        control2: CGPoint(x: 944, y: 140)
    )
    path.addLine(to: CGPoint(x: 944, y: 704))
    path.addCurve(
        to: CGPoint(x: 704, y: 944),
        control1: CGPoint(x: 944, y: 884),
        control2: CGPoint(x: 884, y: 944)
    )
    path.addLine(to: CGPoint(x: 320, y: 944))
    path.addCurve(
        to: CGPoint(x: 80, y: 704),
        control1: CGPoint(x: 140, y: 944),
        control2: CGPoint(x: 80, y: 884)
    )
    path.addLine(to: CGPoint(x: 80, y: 320))
    path.addCurve(
        to: CGPoint(x: 320, y: 80),
        control1: CGPoint(x: 80, y: 140),
        control2: CGPoint(x: 140, y: 80)
    )
    path.closeSubpath()
    return path
}

func gradient(_ context: CGContext, colors: [CGColor], from start: CGPoint, to end: CGPoint) throws {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: nil
    )
    else {
        throw IconError.bitmapCreation
    }
    context.drawLinearGradient(
        gradient,
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func drawBackground(_ context: CGContext) throws {
    let shape = squircle()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0.12, 0.18, 0.25, 0.24))
    context.addPath(shape)
    context.setFillColor(color(0.79, 0.85, 0.89))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    try gradient(
        context,
        colors: [color(0.91, 0.94, 0.95), color(0.65, 0.75, 0.82)],
        from: CGPoint(x: 290, y: 944),
        to: CGPoint(x: 740, y: 80)
    )
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(color(1, 1, 1, 0.5))
    context.setLineWidth(2)
    context.strokePath()
}

func paperPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -240, y: -322))
    path.addLine(to: CGPoint(x: 240, y: -322))
    path.addQuadCurve(to: CGPoint(x: 254, y: -308), control: CGPoint(x: 254, y: -322))
    path.addLine(to: CGPoint(x: 254, y: 218))
    path.addLine(to: CGPoint(x: 150, y: 322))
    path.addLine(to: CGPoint(x: -240, y: 322))
    path.addQuadCurve(to: CGPoint(x: -254, y: 308), control: CGPoint(x: -254, y: 322))
    path.addLine(to: CGPoint(x: -254, y: -308))
    path.addQuadCurve(to: CGPoint(x: -240, y: -322), control: CGPoint(x: -254, y: -322))
    path.closeSubpath()
    return path
}

func drawPaper(_ context: CGContext) throws {
    let paper = paperPath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 4, height: -17), blur: 28, color: color(0.14, 0.23, 0.31, 0.3))
    context.addPath(paper)
    context.setFillColor(color(0.99, 0.98, 0.94))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(paper)
    context.clip()
    try gradient(
        context,
        colors: [color(1, 0.997, 0.98), color(0.96, 0.95, 0.91)],
        from: CGPoint(x: -100, y: 322),
        to: CGPoint(x: 200, y: -322)
    )
    context.restoreGState()
    context.addPath(paper)
    context.setStrokeColor(color(1, 1, 1, 0.8))
    context.setLineWidth(2)
    context.strokePath()
}

func drawFold(_ context: CGContext) throws {
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 150, y: 322))
    fold.addLine(to: CGPoint(x: 254, y: 218))
    fold.addLine(to: CGPoint(x: 164, y: 218))
    fold.addQuadCurve(to: CGPoint(x: 150, y: 232), control: CGPoint(x: 150, y: 218))
    fold.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: -3, height: -4), blur: 7, color: color(0.25, 0.28, 0.3, 0.2))
    context.addPath(fold)
    context.setFillColor(color(0.87, 0.89, 0.88))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(fold)
    context.clip()
    try gradient(
        context,
        colors: [color(0.84, 0.86, 0.85), color(0.98, 0.98, 0.95)],
        from: CGPoint(x: 150, y: 220),
        to: CGPoint(x: 226, y: 295)
    )
    context.restoreGState()
}

func signaturePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -206, y: -132))
    path.addCurve(
        to: CGPoint(x: -84, y: -84),
        control1: CGPoint(x: -152, y: -102),
        control2: CGPoint(x: -25, y: 21)
    )
    path.addCurve(
        to: CGPoint(x: -158, y: -207),
        control1: CGPoint(x: -139, y: -168),
        control2: CGPoint(x: -202, y: -238)
    )
    path.addCurve(
        to: CGPoint(x: -38, y: -115),
        control1: CGPoint(x: -107, y: -171),
        control2: CGPoint(x: -49, y: -54)
    )
    path.addCurve(
        to: CGPoint(x: 13, y: -104),
        control1: CGPoint(x: -26, y: -164),
        control2: CGPoint(x: -2, y: -73)
    )
    path.addCurve(
        to: CGPoint(x: 65, y: -120),
        control1: CGPoint(x: 29, y: -156),
        control2: CGPoint(x: 48, y: -82)
    )
    path.addCurve(
        to: CGPoint(x: 102, y: -82),
        control1: CGPoint(x: 80, y: -149),
        control2: CGPoint(x: 72, y: -69)
    )
    appendSignatureFlourish(to: path)
    return path
}

func appendSignatureFlourish(to path: CGMutablePath) {
    path.addCurve(
        to: CGPoint(x: 166, y: -120),
        control1: CGPoint(x: 137, y: -103),
        control2: CGPoint(x: 105, y: -163)
    )
    path.addCurve(
        to: CGPoint(x: 205, y: -103),
        control1: CGPoint(x: 206, y: -89),
        control2: CGPoint(x: 234, y: -77)
    )
    path.addCurve(
        to: CGPoint(x: -156, y: -233),
        control1: CGPoint(x: 138, y: -164),
        control2: CGPoint(x: -86, y: -171)
    )
}

func drawSignature(_ context: CGContext) {
    context.addPath(signaturePath())
    context.setStrokeColor(color(0.055, 0.13, 0.22))
    context.setLineWidth(9)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func bitmap(size: Int) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        throw IconError.bitmapCreation
    }
    return context
}

func renderIcon() throws -> CGImage {
    let context = try bitmap(size: 512 * 2)
    try drawBackground(context)
    context.translateBy(x: 512, y: 526)
    context.rotate(by: -6 * .pi / 180)
    try drawPaper(context)
    try drawFold(context)
    drawSignature(context)
    guard let image = context.makeImage() else { throw IconError.bitmapCreation }
    return image
}

func writePNG(_ image: CGImage, size: Int, to url: URL) throws {
    let context = try bitmap(size: size)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let scaled = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    else {
        throw IconError.imageEncoding
    }
    try data.write(to: url)
}

func generateIcon() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    let artwork = try renderIcon()
    for points in [16, 32, 128, 256, 512] {
        try writePNG(artwork, size: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try writePNG(artwork, size: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { throw IconError.iconutilFailed(iconutil.terminationStatus) }
}

try generateIcon()
