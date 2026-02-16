import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SignatureSetupSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case draw
        case type
        case `import`

        var id: String { rawValue }

        var title: String {
            switch self {
            case .draw: return "Draw"
            case .type: return "Type"
            case .import: return "Import"
            }
        }

        var sourceKind: SignatureProfile.SourceKind {
            switch self {
            case .draw: return .draw
            case .type: return .type
            case .import: return .import
            }
        }
    }

    @State private var selectedMode: Mode = .draw
    @State private var fullName: String
    @State private var typedSignature: String
    @State private var drawStrokes: [[CGPoint]] = []
    @State private var importedImage: NSImage?
    @State private var isImportPickerPresented = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case fullName
        case typedSignature
    }

    let existingProfile: SignatureProfile?
    let onCancel: () -> Void
    let onSave: (SignatureProfile) -> Void

    init(
        existingProfile: SignatureProfile?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SignatureProfile) -> Void
    ) {
        self.existingProfile = existingProfile
        self.onCancel = onCancel
        self.onSave = onSave

        let existingName = existingProfile?.fullName ?? ""
        _fullName = State(initialValue: existingName)
        _typedSignature = State(initialValue: existingName)
        _selectedMode = State(initialValue: Self.mode(for: existingProfile?.sourceKind))
    }

    private static func mode(for sourceKind: SignatureProfile.SourceKind?) -> Mode {
        switch sourceKind {
        case .draw:
            return .draw
        case .type:
            return .type
        case .import:
            return .import
        case .none:
            return .draw
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingProfile == nil ? "Create Signature" : "Edit Signature")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Full legal name", text: $fullName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .fullName)

            Picker("Method", selection: $selectedMode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedMode {
                case .draw:
                    VStack(alignment: .leading, spacing: 8) {
                        DrawSignatureCanvas(strokes: $drawStrokes)
                            .frame(height: 180)
                            .background(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                            )

                        Button("Clear Drawing") {
                            drawStrokes = []
                        }
                    }
                case .type:
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Type signature text", text: $typedSignature)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .typedSignature)

                        SignaturePreview(image: typePreviewImage)
                            .frame(height: 120)
                    }
                case .import:
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Import Signature Image") {
                            isImportPickerPresented = true
                        }
                        .fileImporter(
                            isPresented: $isImportPickerPresented,
                            allowedContentTypes: [.png, .jpeg, .image],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                guard let first = urls.first else { return }
                                if let image = NSImage(contentsOf: first) {
                                    importedImage = image
                                }
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                            }
                        }

                        SignaturePreview(image: importedImage)
                            .frame(height: 120)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("This creates a visual signature stamp (not a certificate-based digital signature).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save Signature", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            focusedField = .fullName
        }
    }

    private var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && previewImage != nil
    }

    private var typePreviewImage: NSImage? {
        let text = typedSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Self.renderTextSignature(text)
    }

    private var previewImage: NSImage? {
        switch selectedMode {
        case .draw:
            return Self.renderDrawnSignature(from: drawStrokes)
        case .type:
            return typePreviewImage
        case .import:
            return importedImage
        }
    }

    private func save() {
        errorMessage = nil

        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter your full name before saving."
            focusedField = .fullName
            return
        }

        guard let previewImage,
              let normalizedPNGData = Self.normalizeToSignaturePNG(image: previewImage)
        else {
            errorMessage = "Could not create a valid signature image."
            return
        }

        let profile = SignatureProfile(
            id: existingProfile?.id ?? UUID(),
            fullName: trimmedName,
            createdAt: existingProfile?.createdAt ?? Date(),
            signaturePNGData: normalizedPNGData,
            sourceKind: selectedMode.sourceKind
        )

        onSave(profile)
    }

    private static func renderDrawnSignature(from strokes: [[CGPoint]]) -> NSImage? {
        guard !strokes.isEmpty else { return nil }

        let size = NSSize(width: 700, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let allPoints = strokes.flatMap { $0 }
        guard
            let minX = allPoints.map(\.x).min(),
            let maxX = allPoints.map(\.x).max(),
            let minY = allPoints.map(\.y).min(),
            let maxY = allPoints.map(\.y).max()
        else {
            image.unlockFocus()
            return nil
        }

        let sourceWidth = max(1, maxX - minX)
        let sourceHeight = max(1, maxY - minY)
        let targetRect = NSRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40)

        NSColor.black.setStroke()
        for stroke in strokes where stroke.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let first = normalizedPoint(
                stroke[0],
                minX: minX,
                minY: minY,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetRect: targetRect
            )
            path.move(to: first)

            for point in stroke.dropFirst() {
                path.line(to: normalizedPoint(
                    point,
                    minX: minX,
                    minY: minY,
                    sourceWidth: sourceWidth,
                    sourceHeight: sourceHeight,
                    targetRect: targetRect
                ))
            }
            path.stroke()
        }

        image.unlockFocus()
        return image
    }

    private static func normalizedPoint(
        _ point: CGPoint,
        minX: CGFloat,
        minY: CGFloat,
        sourceWidth: CGFloat,
        sourceHeight: CGFloat,
        targetRect: NSRect
    ) -> NSPoint {
        let xRatio = (point.x - minX) / sourceWidth
        let yRatioTopOrigin = (point.y - minY) / sourceHeight

        let x = targetRect.minX + (xRatio * targetRect.width)
        let y = targetRect.minY + ((1 - yRatioTopOrigin) * targetRect.height)
        return NSPoint(x: x, y: y)
    }

    private static func renderTextSignature(_ text: String) -> NSImage? {
        let size = NSSize(width: 700, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let font = NSFont(name: "Snell Roundhand", size: 74) ?? NSFont.systemFont(ofSize: 58, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let origin = NSPoint(x: max(20, (size.width - textSize.width) / 2), y: max(20, (size.height - textSize.height) / 2))
        attributedString.draw(at: origin)

        image.unlockFocus()
        return image
    }

    private static func normalizeToSignaturePNG(image: NSImage, maxSize: NSSize = NSSize(width: 700, height: 220)) -> Data? {
        guard let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceWidth = CGFloat(sourceCGImage.width)
        let sourceHeight = CGFloat(sourceCGImage.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let scale = min(maxSize.width / sourceWidth, maxSize.height / sourceHeight, 1.0)
        let targetSize = NSSize(width: sourceWidth * scale, height: sourceHeight * scale)

        let renderedImage = NSImage(size: maxSize)
        renderedImage.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: maxSize)).fill()

        let rect = NSRect(
            x: (maxSize.width - targetSize.width) / 2,
            y: (maxSize.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        image.draw(in: rect)
        renderedImage.unlockFocus()

        guard
            let tiffData = renderedImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return pngData
    }
}

private struct SignaturePreview: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                Text("No signature preview yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private struct DrawSignatureCanvas: View {
    @Binding var strokes: [[CGPoint]]
    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                Canvas { context, _ in
                    for stroke in strokes {
                        draw(stroke: stroke, in: &context)
                    }
                    draw(stroke: currentStroke, in: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = CGPoint(x: value.location.x, y: value.location.y)
                        currentStroke.append(point)
                    }
                    .onEnded { _ in
                        if currentStroke.count > 1 {
                            strokes.append(currentStroke)
                        }
                        currentStroke = []
                    }
            )
        }
    }

    private func draw(stroke: [CGPoint], in context: inout GraphicsContext) {
        guard stroke.count > 1 else { return }

        var path = Path()
        path.move(to: CGPoint(x: stroke[0].x, y: stroke[0].y))
        for point in stroke.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }

        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
}
