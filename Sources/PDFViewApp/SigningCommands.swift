import SwiftUI

/// Signing state and actions the focused document window publishes for the Sign menu.
struct SigningCommandActions {
    var signingMode: SigningMode
    /// The stamp being placed; Signature whenever the window is not signing.
    var stampKind: StampKind
    var canSign: Bool
    var hasSignatureFields: Bool
    var canSaveSignedCopy: Bool
    var toggleSigning: () -> Void
    var placeInNextField: () -> Void
    var placeOnCurrentPage: () -> Void
    var placeInitialsOnEveryPage: () -> Void
    var setAnywhere: (Bool) -> Void
    var selectNextStamp: () -> Void
    var selectPreviousStamp: () -> Void
    var saveSignedCopy: () -> Void
    /// The last signed copy this window saved, for the File menu's Share and Show in Finder.
    var lastSavedURL: URL?
    var shareSignedCopy: (URL) -> Void
    var editSignature: () -> Void
    var deleteProfile: (SignatureKind) -> Void
    var placeStamp: (StampKind) -> Void
    var editInitials: () -> Void
    var canUnlock: Bool
    var unlock: () -> Void
}

/// Sign menu titles that change with state or cover every stamp kind.
enum SignMenuTitles {
    /// "Create Initials…" until a profile exists, then "Edit Initials…", the same for the signature.
    static func profile(_ kind: SignatureKind, hasProfile: Bool) -> String {
        "\(hasProfile ? "Edit" : "Create") \(kind.title)…"
    }

    static let selectNextStamp = "Select Next Stamp"
    static let selectPreviousStamp = "Select Previous Stamp"
}

/// Every key equivalent PDFView adds to the menu bar, in one place so a test can prove none
/// collide with each other or with the standard macOS menu chords.
enum MenuShortcuts {
    /// Sign menu. Place in Next Field and Place on Current Page mirror `SigningShortcut`.
    static let toggleSigning = KeyboardShortcut("s", modifiers: [.command, .option])
    /// ⌥⇧⌘S is Save As in the system File menu, so the signature takes Control instead of Option.
    static let placeSignature = KeyboardShortcut("s", modifiers: [.command, .control, .shift])
    static let placeInitials = KeyboardShortcut("i", modifiers: [.command, .option, .shift])
    static let placeDate = KeyboardShortcut("d", modifiers: [.command, .option, .shift])
    static let placeInNextField = KeyboardShortcut("n", modifiers: [.command, .option])
    static let placeOnCurrentPage = KeyboardShortcut("p", modifiers: [.command, .option])
    /// One more modifier than Place Initials, so the pair is easy to remember.
    static let placeInitialsOnEveryPage = KeyboardShortcut("i", modifiers: [.command, .option])
    static let selectNextStamp = KeyboardShortcut("]", modifiers: [.command, .option])
    static let selectPreviousStamp = KeyboardShortcut("[", modifiers: [.command, .option])
    /// ⇧⌘S is Save As's convention and ⌥⇧⌘S is taken; ⇧⌘E ("export") is free in the standard menus.
    static let saveSignedCopy = KeyboardShortcut("e", modifiers: [.command, .shift])
    static let shareSignedCopy = KeyboardShortcut("e", modifiers: [.command, .option, .shift])
    /// R for "reveal", as Show in Finder is called elsewhere on the Mac.
    static let showSignedCopyInFinder = KeyboardShortcut("r", modifiers: [.command, .shift])

    // View and Go menus.
    static let toggleSidebar = KeyboardShortcut("s", modifiers: [.command, .control])
    static let nextPage = KeyboardShortcut(.downArrow, modifiers: [.option])
    static let previousPage = KeyboardShortcut(.upArrow, modifiers: [.option])
    static let firstPage = KeyboardShortcut(.upArrow, modifiers: [.command, .option])
    static let lastPage = KeyboardShortcut(.downArrow, modifiers: [.command, .option])
    static let goToPage = KeyboardShortcut("g", modifiers: [.command, .option])
    static let nextFormField = KeyboardShortcut(.rightArrow, modifiers: [.command, .option])
    static let previousFormField = KeyboardShortcut(.leftArrow, modifiers: [.command, .option])
    static let activateFormField = KeyboardShortcut(.return, modifiers: [.command, .option])
    static let actualSize = KeyboardShortcut("0", modifiers: .command)
    static let zoomToFit = KeyboardShortcut("9", modifiers: .command)
    static let zoomIn = KeyboardShortcut("+", modifiers: .command)
    static let zoomOut = KeyboardShortcut("-", modifiers: .command)

    // Standard items PDFView implements itself.
    static let find = KeyboardShortcut("f", modifiers: .command)
    static let findNext = KeyboardShortcut("g", modifiers: .command)
    static let findPrevious = KeyboardShortcut("g", modifiers: [.command, .shift])
    static let pageSetup = KeyboardShortcut("p", modifiers: [.command, .shift])
    static let print = KeyboardShortcut("p", modifiers: .command)

    /// Chords PDFView chose; none may shadow a standard one.
    static var appSpecific: [KeyboardShortcut] {
        [
            toggleSigning, placeSignature, placeInitials, placeDate, placeInNextField, placeOnCurrentPage,
            placeInitialsOnEveryPage,
            selectNextStamp, selectPreviousStamp, saveSignedCopy, shareSignedCopy, showSignedCopyInFinder,
            toggleSidebar, nextPage, previousPage,
            firstPage, lastPage, goToPage, nextFormField, previousFormField, activateFormField, actualSize, zoomToFit,
            zoomIn, zoomOut,
        ]
    }

    static var all: [KeyboardShortcut] {
        appSpecific + [find, findNext, findPrevious, pageSetup, print]
    }

    /// Chords macOS or a standard document app menu already uses.
    static let standardChords: [Chord] = [
        Chord("n", [.command]), Chord("o", [.command]), Chord("w", [.command]), Chord("w", [.command, .option]),
        Chord("s", [.command]), Chord("s", [.command, .shift]), Chord("s", [.command, .option, .shift]),
        Chord("z", [.command]), Chord("z", [.command, .shift]), Chord("x", [.command]), Chord("c", [.command]),
        Chord("v", [.command]), Chord("v", [.command, .option]), Chord("a", [.command]), Chord("e", [.command]),
        Chord("j", [.command]), Chord("f", [.command]), Chord("g", [.command]), Chord("g", [.command, .shift]),
        Chord("p", [.command]), Chord("p", [.command, .shift]), Chord("q", [.command]),
        Chord("q", [.command, .shift]), Chord("q", [.command, .control]), Chord("h", [.command]),
        Chord("h", [.command, .option]), Chord("m", [.command]), Chord(",", [.command]),
        Chord("f", [.command, .control]), Chord("t", [.command, .option]), Chord("d", [.command, .option]),
        Chord("?", [.command]), Chord("?", [.command, .shift]), Chord("`", [.command]),
        Chord(" ", [.command, .control]), Chord("3", [.command, .shift]), Chord("4", [.command, .shift]),
        Chord("5", [.command, .shift]),
    ]

    /// A key and its modifiers, comparable without relying on `KeyboardShortcut` being hashable.
    struct Chord: Hashable, CustomStringConvertible {
        let key: Character
        let modifiers: Int

        init(_ key: Character, _ modifiers: EventModifiers) {
            self.key = key
            self.modifiers = modifiers.rawValue
        }

        init(_ shortcut: KeyboardShortcut) {
            self.init(shortcut.key.character, shortcut.modifiers)
        }

        var description: String {
            "\(modifiers):\(key)"
        }
    }
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
        // File menu: the signed copy is this app's save, so it sits with Save and Share.
        CommandGroup(after: .saveItem) {
            Button("Save Signed Copy…") {
                actions?.saveSignedCopy()
            }
            .keyboardShortcut(MenuShortcuts.saveSignedCopy)
            .disabled(!(actions?.canSaveSignedCopy ?? false))

            let url = actions?.lastSavedURL
            Button("Share Signed Copy…") {
                if let url {
                    actions?.shareSignedCopy(url)
                }
            }
            .keyboardShortcut(MenuShortcuts.shareSignedCopy)
            .disabled(url == nil)
            Button("Show Signed Copy in Finder") {
                if let url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .keyboardShortcut(MenuShortcuts.showSignedCopyInFinder)
            .disabled(url == nil)

            Divider()

            Button("Unlock…") { actions?.unlock() }
                .disabled(actions?.canUnlock != true)
        }
        CommandMenu("Sign") {
            let canSign = actions?.canSign ?? false
            let hasFields = actions?.hasSignatureFields ?? false
            let mode = actions?.signingMode ?? .idle
            let kind = actions?.stampKind ?? .signature

            Button(StampWorkflow.signingToggleTitle(mode: mode, kind: kind)) {
                actions?.toggleSigning()
            }
            .keyboardShortcut(MenuShortcuts.toggleSigning)
            .disabled(!canSign)

            Button("Place Signature") { actions?.placeStamp(.signature) }
                .keyboardShortcut(MenuShortcuts.placeSignature)
                .disabled(!canSign)
            Button("Place Initials") { actions?.placeStamp(.initials) }
                .keyboardShortcut(MenuShortcuts.placeInitials)
                .disabled(!canSign)
            Button("Place Date") { actions?.placeStamp(.date) }
                .keyboardShortcut(MenuShortcuts.placeDate)
                .disabled(!canSign)

            // Keys mirror SigningShortcut, which the signing banner shows. Fields take signatures only.
            // Enabled whenever a document is open: when it can't place, it says why instead of beeping.
            let nextFieldReason = SigningFlowLogic.nextFieldUnavailableReason(kind: kind, hasSignatureFields: hasFields)
            Button(StampWorkflow.placeInNextFieldTitle(kind: .signature)) {
                actions?.placeInNextField()
            }
            .keyboardShortcut(MenuShortcuts.placeInNextField)
            .disabled(actions == nil)
            if hasFields, let nextFieldReason {
                Text(nextFieldReason)
            }

            Button(StampWorkflow.placeOnCurrentPageTitle(kind: kind)) {
                actions?.placeOnCurrentPage()
            }
            .keyboardShortcut(MenuShortcuts.placeOnCurrentPage)
            .disabled(!canSign)

            Button(StampWorkflow.everyPageActionName) {
                actions?.placeInitialsOnEveryPage()
            }
            .keyboardShortcut(MenuShortcuts.placeInitialsOnEveryPage)
            .disabled(!canSign)

            Divider()

            // Enabled with no stamps too, so the shortcut explains itself instead of beeping.
            Button(SignMenuTitles.selectNextStamp) {
                actions?.selectNextStamp()
            }
            .keyboardShortcut(MenuShortcuts.selectNextStamp)
            .disabled(actions == nil)

            Button(SignMenuTitles.selectPreviousStamp) {
                actions?.selectPreviousStamp()
            }
            .keyboardShortcut(MenuShortcuts.selectPreviousStamp)
            .disabled(actions == nil)

            Divider()

            Toggle("Anywhere", isOn: Binding(
                get: { actions?.signingMode == .freePlacement },
                set: { actions?.setAnywhere($0) }
            ))
            .disabled(!SigningFlowLogic.anywhereIsEnabled(mode: mode, canSign: canSign, hasSignatureFields: hasFields))

            Divider()

            Button(SignMenuTitles.profile(.signature, hasProfile: signatureStore.profile != nil)) {
                actions?.editSignature()
            }
            .disabled(actions == nil)

            Button(SignMenuTitles.profile(.initials, hasProfile: signatureStore.profile(for: .initials) != nil)) {
                actions?.editInitials()
            }
            .disabled(actions == nil)

            ForEach(SignatureKind.allCases, id: \.self) { kind in
                Button(StampWorkflow.deleteMenuTitle(kind)) {
                    actions?.deleteProfile(kind)
                }
                .disabled(actions == nil || signatureStore.profile(for: kind) == nil)
            }
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
        .keyboardShortcut(MenuShortcuts.actualSize)

        Button("Zoom to Fit") {
            actions?.zoomToFit()
        }
        .keyboardShortcut(MenuShortcuts.zoomToFit)

        Button("Zoom In") {
            actions?.zoomIn()
        }
        .keyboardShortcut(MenuShortcuts.zoomIn)

        Button("Zoom Out") {
            actions?.zoomOut()
        }
        .keyboardShortcut(MenuShortcuts.zoomOut)
    }
}
