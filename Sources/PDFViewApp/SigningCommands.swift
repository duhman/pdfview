import SwiftUI

/// Signing state and actions the focused document window publishes for the Sign menu.
struct SigningCommandActions {
    var signingMode: SigningMode
    var canSign: Bool
    var hasSignatureFields: Bool
    var canSaveSignedCopy: Bool
    var toggleSigning: () -> Void
    var placeInNextField: () -> Void
    var placeOnCurrentPage: () -> Void
    var setAnywhere: (Bool) -> Void
    var saveSignedCopy: () -> Void
    var editSignature: () -> Void
    var deleteSignature: () -> Void
}

/// Zoom actions the focused document window publishes for the View menu.
struct ZoomCommandActions {
    var actualSize: () -> Void
    var zoomToFit: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
}

private struct SigningCommandActionsKey: FocusedValueKey {
    typealias Value = SigningCommandActions
}

private struct ZoomCommandActionsKey: FocusedValueKey {
    typealias Value = ZoomCommandActions
}

extension FocusedValues {
    var signingActions: SigningCommandActions? {
        get { self[SigningCommandActionsKey.self] }
        set { self[SigningCommandActionsKey.self] = newValue }
    }

    var zoomActions: ZoomCommandActions? {
        get { self[ZoomCommandActionsKey.self] }
        set { self[ZoomCommandActionsKey.self] = newValue }
    }
}

struct SigningCommandMenu: Commands {
    @FocusedValue(\.signingActions)
    private var actions
    @ObservedObject var signatureStore: SignatureStore

    var body: some Commands {
        CommandMenu("Sign") {
            let canSign = actions?.canSign ?? false
            let hasFields = actions?.hasSignatureFields ?? false
            let isSigning = (actions?.signingMode ?? .idle) != .idle

            Button(isSigning ? "Stop Signing" : "Start Signing") {
                actions?.toggleSigning()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!canSign)

            Button("Place in Next Field") {
                actions?.placeInNextField()
            }
            .disabled(!(canSign && hasFields))

            Button("Place on Current Page") {
                actions?.placeOnCurrentPage()
            }
            .disabled(!canSign)

            Toggle("Anywhere", isOn: Binding(
                get: { actions?.signingMode == .freePlacement },
                set: { actions?.setAnywhere($0) }
            ))
            .disabled(!(canSign && hasFields))

            Divider()

            Button("Save Signed Copy…") {
                actions?.saveSignedCopy()
            }
            // ⇧⌘S is Save As's convention and the system File menu already owns ⌥⇧⌘S (Save As…),
            // which makes SwiftUI drop a duplicate; ⇧⌘E ("export") is free in the standard menus.
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!(actions?.canSaveSignedCopy ?? false))

            Divider()

            Button("Edit Signature…") {
                actions?.editSignature()
            }
            .disabled(actions == nil || signatureStore.profile == nil)

            Button("Delete Signature…") {
                actions?.deleteSignature()
            }
            .disabled(actions == nil || signatureStore.profile == nil)
        }
    }
}

struct ZoomCommands: Commands {
    @FocusedValue(\.zoomActions)
    private var actions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Group {
                zoomButtons
            }
            .disabled(actions == nil)
        }
    }

    @ViewBuilder private var zoomButtons: some View {
        Button("Actual Size") {
            actions?.actualSize()
        }
        .keyboardShortcut("0", modifiers: .command)

        Button("Zoom to Fit") {
            actions?.zoomToFit()
        }
        .keyboardShortcut("9", modifiers: .command)

        Button("Zoom In") {
            actions?.zoomIn()
        }
        .keyboardShortcut("+", modifiers: .command)

        Button("Zoom Out") {
            actions?.zoomOut()
        }
        .keyboardShortcut("-", modifiers: .command)
    }
}
