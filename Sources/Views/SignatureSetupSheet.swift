import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SignatureSetupSheet: View {
    /// The drawing canvas is a fixed size so the pen width, and therefore the printed ink, never changes.
    static let canvasSize = CGSize(width: 520, height: 180)
    private static let privacyNote = "Your signature is stored only on this Mac. "
        + "This is a visual stamp, not a certificate-based digital signature."

    @State private var selectedMode: Mode
    @State private var fullName: String
    @State private var typedText: String
    @State private var typedTextEdited: Bool
    @State private var fontName: String
    @State private var drawStrokes: [[CGPoint]] = []
    @State private var importedImage: CGImage?
    @State private var importedFileName: String?
    @State private var importRendering: SignatureRenderer.Rendering?
    @State private var removesWhiteBackground = true
    @State private var importError: String?
    @State private var isImportPickerPresented = false
    @State private var errorMessage: String?
    /// The saved artwork stays the current signature until the user draws, types or imports a new one.
    @State private var keepsExistingArtwork: Bool
    @FocusState private var focusedField: Field?

    private enum Field {
        case fullName
        case typedText
    }

    let existingProfile: SignatureProfile?
    let onCancel: () -> Void
    let onSave: (SignatureProfile) -> Void
    private let existingArtwork: NSImage?

    init(
        existingProfile: SignatureProfile?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SignatureProfile) -> Void
    ) {
        self.existingProfile = existingProfile
        self.onCancel = onCancel
        self.onSave = onSave

        let existingName = existingProfile?.fullName ?? ""
        let typedText = existingProfile?.typedText ?? existingName
        let fonts = SignatureRenderer.availableScriptFonts
        existingArtwork = existingProfile?.signaturePNGData.flatMap(NSImage.init(data:))
        _fullName = State(initialValue: existingName)
        _typedText = State(initialValue: typedText)
        _typedTextEdited = State(initialValue: typedText != existingName)
        _fontName = State(initialValue: existingProfile?.fontName.flatMap { fonts.contains($0) ? $0 : nil }
            ?? fonts.first ?? SignatureRenderer.scriptFontNames[0])
        // Typing is the keyboard-accessible default for a new signature.
        _selectedMode = State(initialValue: existingProfile.map { Mode($0.sourceKind) } ?? .type)
        _keepsExistingArtwork = State(initialValue: existingArtwork != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingProfile == nil ? "Create Signature" : "Edit Signature")
                .font(.title2)
                .fontWeight(.semibold)

            nameField

            Picker("Method", selection: $selectedMode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SignaturePaper {
                signatureSurface
            }
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)

            modeControls

            if let errorMessage {
                InlineError(message: errorMessage)
            }

            Text(Self.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            footer
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            focusedField = .fullName
        }
        .onChange(of: fullName) { _, newName in
            if !typedTextEdited {
                typedText = newName
            }
        }
        .onChange(of: typedText) { replaceExistingArtwork(for: .type) }
        .onChange(of: fontName) { replaceExistingArtwork(for: .type) }
        .onChange(of: drawStrokes) { replaceExistingArtwork(for: .draw) }
        .onChange(of: removesWhiteBackground) { updateImportRendering() }
    }

    private var nameField: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Full name:")
            TextField("Full name", text: $fullName, prompt: Text("Jane Appleseed"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($focusedField, equals: .fullName)
        }
    }

    @ViewBuilder private var signatureSurface: some View {
        switch selectedMode {
        case .draw:
            DrawSignatureCanvas(
                strokes: $drawStrokes,
                underlay: showsExistingArtwork ? existingArtwork : nil
            )
        case .type, .import:
            SignaturePreview(image: previewImage, placeholder: previewPlaceholder)
        }
    }

    @ViewBuilder private var modeControls: some View {
        switch selectedMode {
        case .draw:
            HStack {
                Button("Undo Stroke") {
                    drawStrokes.removeLast()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(drawStrokes.isEmpty)

                Button("Clear") {
                    drawStrokes = []
                    keepsExistingArtwork = false
                }
                .disabled(drawStrokes.isEmpty && !showsExistingArtwork)
            }
        case .type:
            typeControls
        case .import:
            importControls
        }
    }

    private var typeControls: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Signature:")
            TextField("Signature text", text: typedTextBinding, prompt: Text("Your name"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($focusedField, equals: .typedText)

            Picker("Style", selection: $fontName) {
                ForEach(SignatureRenderer.availableScriptFonts, id: \.self) { name in
                    Text(NSFont(name: name, size: NSFont.systemFontSize)?.displayName ?? name).tag(name)
                }
            }
            .fixedSize()
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose Image…") {
                    isImportPickerPresented = true
                }
                .fileImporter(
                    isPresented: $isImportPickerPresented,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false,
                    onCompletion: importSignature
                )

                if let importedFileName {
                    Text(importedFileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Remove white background", isOn: $removesWhiteBackground)
                    .disabled(importedImage == nil)
            }

            if let importError {
                InlineError(message: importError)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let saveHint {
                Text(saveHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save Signature", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(saveHint != nil)
        }
    }

    /// Typing into the signature field stops it following the name field.
    private var typedTextBinding: Binding<String> {
        Binding(
            get: { typedText },
            set: { newValue in
                typedText = newValue
                typedTextEdited = true
            }
        )
    }

    private var showsExistingArtwork: Bool {
        keepsExistingArtwork && existingProfile.map { Mode($0.sourceKind) } == selectedMode
    }

    private var previewImage: NSImage? {
        if showsExistingArtwork {
            return existingArtwork
        }
        let rendering = selectedMode == .type
            ? SignatureRenderer.renderText(typedText, fontName: fontName)
            : importRendering
        return rendering.map { NSImage(cgImage: $0.image, size: $0.pointSize) }
    }

    private var previewPlaceholder: String {
        selectedMode == .type ? "Type your signature below" : "Choose an image of your signature"
    }

    /// Why Save is disabled, or nil when the signature can be saved.
    private var saveHint: String? {
        if fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your full name to save."
        }
        if showsExistingArtwork {
            return nil
        }
        switch selectedMode {
        case .draw:
            return drawStrokes.isEmpty ? "Draw your signature in the box to save." : nil
        case .type:
            return typedText.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? "Type your signature to save." : nil
        case .import:
            return importRendering == nil ? "Choose an image of your signature to save." : nil
        }
    }
}

extension SignatureSetupSheet {
    enum Mode: String, CaseIterable, Identifiable {
        case draw
        case type
        case `import`

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .draw: "Draw"
            case .type: "Type"
            case .import: "Import"
            }
        }

        var sourceKind: SignatureProfile.SourceKind {
            switch self {
            case .draw: .draw
            case .type: .type
            case .import: .import
            }
        }

        init(_ sourceKind: SignatureProfile.SourceKind) {
            switch sourceKind {
            case .draw: self = .draw
            case .type: self = .type
            case .import: self = .import
            }
        }
    }
}

private extension SignatureSetupSheet {
    func replaceExistingArtwork(for mode: Mode) {
        if existingProfile.map({ Mode($0.sourceKind) }) == mode {
            keepsExistingArtwork = false
        }
    }

    func importSignature(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            // Read the bytes while the security scope is open; NSImage would load them lazily after it closes.
            guard let data = try? Data(contentsOf: url), let image = SignatureRenderer.decodeImage(data) else {
                importError = "“\(url.lastPathComponent)” isn’t an image PDFView can read."
                return
            }
            importedImage = image
            importedFileName = url.lastPathComponent
            updateImportRendering()
            replaceExistingArtwork(for: .import)
        case let .failure(error):
            importError = error.localizedDescription
        }
    }

    func updateImportRendering() {
        guard let importedImage else { return }
        importRendering = SignatureRenderer.renderImport(importedImage, removingWhiteBackground: removesWhiteBackground)
        importError = importRendering == nil
            ? "“\(importedFileName ?? "This image")” has no visible signature after removing the white background."
            : nil
    }

    func save() {
        errorMessage = nil
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            focusedField = .fullName
            return
        }

        // Keeping the saved artwork writes its original bytes back rather than re-encoding them.
        if showsExistingArtwork, let existingProfile, let existingData = existingProfile.signaturePNGData {
            var profile = existingProfile
            profile.fullName = trimmedName
            profile.signaturePNGBase64 = existingData.base64EncodedString()
            onSave(profile)
            return
        }

        let isTyped = selectedMode == .type
        let rendering = switch selectedMode {
        case .draw: SignatureRenderer.renderDrawing(strokes: drawStrokes, canvasSize: Self.canvasSize)
        case .type: SignatureRenderer.renderText(typedText, fontName: fontName)
        case .import: importRendering
        }
        guard let rendering else {
            errorMessage = "Couldn’t create an image from this signature. Try again."
            return
        }

        onSave(SignatureProfile(
            id: existingProfile?.id ?? UUID(),
            fullName: trimmedName,
            createdAt: existingProfile?.createdAt ?? Date(),
            signaturePNGData: rendering.pngData,
            sourceKind: selectedMode.sourceKind,
            typedText: isTyped ? typedText.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            fontName: isTyped ? fontName : nil
        ))
    }
}

/// The signing surface: white paper with a signature line in both light and dark mode, so black ink is
/// always visible and the preview looks like the stamp will on the page.
private struct SignaturePaper<Content: View>: View {
    @ViewBuilder let content: Content

    private let guideColor = Color(white: 0.7)

    var body: some View {
        ZStack {
            Color.white
            GeometryReader { geometry in
                let baselineY = geometry.size.height * 0.7
                Path { path in
                    path.move(to: CGPoint(x: 40, y: baselineY))
                    path.addLine(to: CGPoint(x: geometry.size.width - 24, y: baselineY))
                }
                .stroke(guideColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                Text("×")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(guideColor)
                    .position(x: 26, y: baselineY - 8)
            }
            .accessibilityHidden(true)

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct SignaturePreview: View {
    let image: NSImage?
    let placeholder: String

    var body: some View {
        Group {
            if let image {
                // Shrink to fit, but never enlarge: a bigger preview would show heavier ink than the stamp has.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
            } else {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signature preview")
        .accessibilityValue(image == nil ? placeholder : "Contains a signature")
    }
}

private struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }
}

/// Draws exactly what `SignatureRenderer.renderDrawing` will export: the same smoothed curves, dots and pen width.
private struct DrawSignatureCanvas: View {
    @Binding var strokes: [[CGPoint]]
    /// Saved artwork shown until the first new stroke.
    let underlay: NSImage?
    @State private var currentStroke: [CGPoint] = []

    private let size = SignatureSetupSheet.canvasSize
    private let lineWidth = SignatureRenderer.inkWidth(forCanvasHeight: SignatureSetupSheet.canvasSize.height)

    var body: some View {
        ZStack {
            if let underlay {
                SignaturePreview(image: underlay, placeholder: "")
            }
            Canvas { context, _ in
                for stroke in strokes + [currentStroke] {
                    draw(stroke, in: &context)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    currentStroke.append(CGPoint(
                        x: min(max(value.location.x, 0), size.width),
                        y: min(max(value.location.y, 0), size.height)
                    ))
                }
                .onEnded { _ in
                    if !currentStroke.isEmpty {
                        strokes.append(currentStroke)
                    }
                    currentStroke = []
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signature drawing area")
        .accessibilityHint("To sign without drawing, choose Type")
        .accessibilityValue(strokes.isEmpty && underlay == nil ? "Empty" : "Contains a signature")
    }

    private func draw(_ stroke: [CGPoint], in context: inout GraphicsContext) {
        guard !stroke.isEmpty else { return }
        if let dot = SignatureRenderer.dotRect(for: stroke, lineWidth: lineWidth) {
            context.fill(Path(ellipseIn: dot), with: .color(.black))
        } else {
            context.stroke(
                Path(SignatureRenderer.smoothedPath(for: stroke)),
                with: .color(.black),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
