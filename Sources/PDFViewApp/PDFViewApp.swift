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
        .commands {
            SigningCommandMenu()
        }
    }
}

private struct SigningCommandMenu: Commands {
    @FocusedValue(\.startSigningAction) private var startSigningAction
    @FocusedValue(\.toggleFreePlacementAction) private var toggleFreePlacementAction
    @FocusedValue(\.saveSignedCopyAction) private var saveSignedCopyAction
    @FocusedValue(\.saveSignedCopyAsAction) private var saveSignedCopyAsAction
    @FocusedValue(\.undoSignaturePlacementAction) private var undoSignaturePlacementAction
    @FocusedValue(\.redoSignaturePlacementAction) private var redoSignaturePlacementAction
    @FocusedValue(\.canUndoSignaturePlacementAction) private var canUndoSignaturePlacementAction
    @FocusedValue(\.canRedoSignaturePlacementAction) private var canRedoSignaturePlacementAction
    @FocusedValue(\.editSignatureAction) private var editSignatureAction
    @FocusedValue(\.deleteSignatureAction) private var deleteSignatureAction

    var body: some Commands {
        CommandMenu("Sign") {
            Button("Start Signing") {
                startSigningAction?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Toggle Free Placement") {
                toggleFreePlacementAction?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button("Undo Last Signature Placement") {
                undoSignaturePlacementAction?()
            }
            .disabled(!(canUndoSignaturePlacementAction?() ?? false))

            Button("Redo Last Signature Placement") {
                redoSignaturePlacementAction?()
            }
            .disabled(!(canRedoSignaturePlacementAction?() ?? false))

            Divider()

            Button("Edit Signature…") {
                editSignatureAction?()
            }

            Button("Delete Signature…") {
                deleteSignatureAction?()
            }

            Divider()

            Button("Save Signed Copy") {
                saveSignedCopyAction?()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save Signed Copy As…") {
                saveSignedCopyAsAction?()
            }
            .keyboardShortcut("s", modifiers: [.command, .option, .shift])
        }
    }
}
