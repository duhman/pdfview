import SwiftUI
import Quartz
import AppKit

/// Main content view for PDF documents
/// Provides the SwiftUI interface wrapping the PDFKit view
struct PDFContentView: View {

    /// The document binding from DocumentGroup
    @Binding var document: PDFViewerDocument
    @Environment(\.undoManager) private var undoManager

    /// Current zoom scale
    @State private var zoomScale: CGFloat = 1.0

    @StateObject private var signatureStore = SignatureStore()
    @StateObject private var signatureUndoController = SignaturePlacementUndoController()

    @State private var signingMode: SigningMode = .idle
    @State private var hasSignatureFields = false
    @State private var lastSignedOutputURL: URL?

    @State private var showSignatureSetupSheet = false
    @State private var isEditingSignature = false
    @State private var shouldResumeSigningAfterSetup = false
    @State private var showDeleteSignatureAlert = false

    @State private var activeAlertMessage: String?

    var body: some View {
        content
            .frame(minWidth: 600, minHeight: 400)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showSignatureSetupSheet) {
                signatureSetupSheet
            }
            .alert("Delete Signature?", isPresented: $showDeleteSignatureAlert) {
                Button("Delete", role: .destructive) {
                    do {
                        try signatureStore.deleteProfile()
                        signingMode = .idle
                    } catch {
                        activeAlertMessage = "Could not delete signature: \(error.localizedDescription)"
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved signature will be removed from this device.")
            }
            .alert("Error", isPresented: errorAlertIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(activeAlertMessage ?? "Unknown error")
            }
            .focusedSceneValue(\.startSigningAction, startSigning)
            .focusedSceneValue(\.canStartSigningAction, canStartSigningAction)
            .focusedSceneValue(\.toggleFreePlacementAction, toggleFreePlacementMode)
            .focusedSceneValue(\.saveSignedCopyAction, saveSignedCopy)
            .focusedSceneValue(\.canSaveSignedCopyAction, canSaveSignedCopyAction)
            .focusedSceneValue(\.saveSignedCopyAsAction, saveSignedCopyAs)
            .focusedSceneValue(\.undoSignaturePlacementAction, performUndoSignaturePlacement)
            .focusedSceneValue(\.redoSignaturePlacementAction, performRedoSignaturePlacement)
            .focusedSceneValue(\.canUndoSignaturePlacementAction, canUndoSignaturePlacement)
            .focusedSceneValue(\.canRedoSignaturePlacementAction, canRedoSignaturePlacement)
            .focusedSceneValue(\.editSignatureAction, editSignature)
            .focusedSceneValue(\.deleteSignatureAction, { showDeleteSignatureAlert = true })
    }

    private var content: some View {
        VStack(spacing: 0) {
            if signingMode != .idle {
                signingStatusBanner
            }

            pdfView
        }
    }

    private var pdfView: some View {
        PDFKitView(
            document: document.pdfDocument,
            signaturePlacements: document.signaturePlacements,
            zoomScale: $zoomScale,
            signingMode: signingMode,
            signatureProfile: signatureStore.profile,
            onSignaturePlacement: handleSignaturePlacement,
            onSignatureFieldAvailability: { hasSignatureFields = $0 }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: startSigning) {
                Image(systemName: "signature")
            }
            .help("Sign PDF")
            .disabled(!canStartSigning)
            .accessibilityLabel("Start signing")
            .accessibilityHint("Creates or uses your saved visual signature stamp.")

            Button(action: saveSignedCopy) {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save Signed Copy")
            .disabled(!canSaveSignedCopy)
            .accessibilityLabel("Save signed copy")
            .accessibilityHint("Exports a flattened visual signature copy.")

            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out")
            .accessibilityLabel("Zoom out")

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("=", modifiers: .command)
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom In")
            .accessibilityLabel("Zoom in")

            Button(action: resetZoom) {
                Image(systemName: "arrow.uturn.left.circle")
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Reset Zoom")
            .accessibilityLabel("Reset zoom")
        }
    }

    private var signatureSetupSheet: some View {
        SignatureSetupSheet(
            existingProfile: isEditingSignature ? signatureStore.profile : nil,
            onCancel: {
                showSignatureSetupSheet = false
                shouldResumeSigningAfterSetup = false
                signingMode = .idle
            },
            onSave: { profile in
                do {
                    try signatureStore.upsert(profile: profile)
                    showSignatureSetupSheet = false
                    if shouldResumeSigningAfterSetup {
                        enterSigningMode()
                    }
                    shouldResumeSigningAfterSetup = false
                } catch {
                    activeAlertMessage = "Could not save signature: \(error.localizedDescription)"
                }
            }
        )
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { activeAlertMessage != nil },
            set: { if !$0 { activeAlertMessage = nil } }
        )
    }

    private var signingStatusBanner: some View {
        HStack {
            Text(signingBannerText)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button(signingMode.allowsFreePlacement ? "Field Mode" : "Free Placement") {
                toggleFreePlacementMode()
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var signingBannerText: String {
        SigningFlowLogic.statusText(mode: signingMode, hasSignatureFields: hasSignatureFields)
    }

    private var canStartSigning: Bool {
        guard let pdf = document.pdfDocument else { return false }
        guard pdf.pageCount > 0 else { return false }
        return !pdf.isLocked
    }

    private var canSaveSignedCopy: Bool {
        document.pdfDocument != nil && !document.signaturePlacements.isEmpty
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

    private func startSigning() {
        guard canStartSigning else { return }

        if signatureStore.profile == nil {
            isEditingSignature = false
            shouldResumeSigningAfterSetup = true
            showSignatureSetupSheet = true
            return
        }

        enterSigningMode()
    }

    private func enterSigningMode() {
        signingMode = SigningFlowLogic.entryMode(hasSignatureFields: hasSignatureFields)
    }

    private func toggleFreePlacementMode() {
        guard canStartSigning else { return }

        if signingMode == .idle {
            startSigning()
            return
        }

        signingMode = SigningFlowLogic.toggledMode(current: signingMode, hasSignatureFields: hasSignatureFields)
    }

    private func handleSignaturePlacement(_ placement: PDFViewerDocument.SignaturePlacement) {
        syncUndoController()
        signatureUndoController.addPlacement(placement, registerUndo: true)
    }

    private func performUndoSignaturePlacement() {
        syncUndoController()
        signatureUndoController.undo()
    }

    private func performRedoSignaturePlacement() {
        syncUndoController()
        signatureUndoController.redo()
    }

    private func canUndoSignaturePlacement() -> Bool {
        undoManager?.canUndo ?? false
    }

    private func canRedoSignaturePlacement() -> Bool {
        undoManager?.canRedo ?? false
    }

    private func canStartSigningAction() -> Bool {
        canStartSigning
    }

    private func canSaveSignedCopyAction() -> Bool {
        canSaveSignedCopy
    }

    private func syncUndoController() {
        signatureUndoController.document = $document
        signatureUndoController.undoManager = undoManager
    }

    private func editSignature() {
        isEditingSignature = true
        shouldResumeSigningAfterSetup = signingMode != .idle
        showSignatureSetupSheet = true
    }

    private func saveSignedCopy() {
        guard let destinationURL = lastSignedOutputURL else {
            saveSignedCopyAs()
            return
        }

        writeSignedCopy(to: destinationURL)
    }

    private func saveSignedCopyAs() {
        guard canSaveSignedCopy else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultSignedFileName()

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        writeSignedCopy(to: url)
    }

    private func writeSignedCopy(to url: URL) {
        do {
            try document.writeSignedCopy(to: url)
            lastSignedOutputURL = url
        } catch {
            activeAlertMessage = "Could not save signed PDF: \(error.localizedDescription)"
        }
    }

    private func defaultSignedFileName() -> String {
        let sourceURL = NSApp.keyWindow?.representedURL
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "document"
        return "\(baseName)-signed.pdf"
    }
}

@MainActor
private final class SignaturePlacementUndoController: ObservableObject {
    var document: Binding<PDFViewerDocument>?
    weak var undoManager: UndoManager?

    func addPlacement(_ placement: PDFViewerDocument.SignaturePlacement, registerUndo: Bool) {
        guard let document else { return }
        document.wrappedValue.addSignaturePlacement(placement)

        guard registerUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.removePlacement(id: placement.id, registerUndo: true)
        }
        undoManager.setActionName("Add Signature")
    }

    func removePlacement(id: UUID, registerUndo: Bool) {
        guard let document,
              let removedPlacement = document.wrappedValue.removeSignaturePlacement(id: id)
        else {
            return
        }

        guard registerUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.addPlacement(removedPlacement, registerUndo: true)
        }
        undoManager.setActionName("Remove Signature")
    }

    func undo() {
        undoManager?.undo()
    }

    func redo() {
        undoManager?.redo()
    }
}
