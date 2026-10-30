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
    var hasPlacements: Bool
    var selectNextSignature: () -> Void
    var selectPreviousSignature: () -> Void
    var saveSignedCopy: () -> Void
    /// The last signed copy this window saved, for the File menu's Share and Show in Finder.
    var lastSavedURL: URL?
    var shareSignedCopy: (URL) -> Void
    var editSignature: () -> Void
    var deleteSignature: () -> Void
    var placeStamp: (StampKind) -> Void
    var editInitials: () -> Void
    var canUnlock: Bool
    var unlock: () -> Void
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
        CommandGroup(after: .saveItem) {
            let url = actions?.lastSavedURL
            Button("Share Signed Copy…") {
                if let url {
                    actions?.shareSignedCopy(url)
                }
            }
            .disabled(url == nil)
            Button("Show Signed Copy in Finder") {
                if let url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(url == nil)
        }
        CommandMenu("Sign") {
            let canSign = actions?.canSign ?? false
            let hasFields = actions?.hasSignatureFields ?? false
            let isSigning = (actions?.signingMode ?? .idle) != .idle

            Button(isSigning ? "Stop Signing" : "Start Signing") {
                actions?.toggleSigning()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!canSign)

            Button("Place Signature") { actions?.placeStamp(.signature) }
                .disabled(!canSign)
            Button("Place Initials") { actions?.placeStamp(.initials) }
                .keyboardShortcut("i", modifiers: [.command, .option, .shift])
                .disabled(!canSign)
            Button("Place Date") { actions?.placeStamp(.date) }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                .disabled(!canSign)

            // Keys mirror SigningShortcut, which the signing banner shows.
            Button("Place in Next Field") {
                actions?.placeInNextField()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!(canSign && hasFields))

            Button("Place on Current Page") {
                actions?.placeOnCurrentPage()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!canSign)

            Divider()

            Button("Select Next Signature") {
                actions?.selectNextSignature()
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(!(actions?.hasPlacements ?? false))

            Button("Select Previous Signature") {
                actions?.selectPreviousSignature()
            }
            .keyboardShortcut("[", modifiers: [.command, .option])
            .disabled(!(actions?.hasPlacements ?? false))

            Divider()

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

            Button(SigningFlowLogic.signatureMenuTitle(hasProfile: signatureStore.profile != nil)) {
                actions?.editSignature()
            }
            .disabled(actions == nil)

            Button("Create/Edit Initials…") { actions?.editInitials() }
                .disabled(actions == nil)

            Button("Unlock…") { actions?.unlock() }
                .disabled(actions?.canUnlock != true)

            Button("Delete Saved Signature…") {
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
