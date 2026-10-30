import SwiftUI

/// Main application entry point
/// Uses DocumentGroup for native document-based app architecture
@main
struct PDFViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    /// One signature for the whole app, so editing it in one window updates every window.
    @StateObject private var signatureStore = SignatureStore()
    @State private var stampSizes = StampSizeMemory()
    @State private var undoMenu = UndoMenuModel()

    var body: some Scene {
        DocumentGroup(viewing: PDFViewerDocument.self) { file in
            PDFContentView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(signatureStore)
                .environment(stampSizes)
        }
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.titleBar)
        .commands {
            AppInfoCommands()
            ReadOnlyDocumentCommands()
            UndoCommands(model: undoMenu)
            HelpCommands()
            ZoomCommands()
            ReaderCommands()
            SigningCommandMenu(signatureStore: signatureStore)
        }

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsView()
        }
        .commandsRemoved()

        Window("About PDFView", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

/// Save, Save As, Duplicate, Rename and Move To would write the PDF without its stamps (and,
/// for Duplicate, an unsigned copy); the only way to write is File > Save Signed Copy.
/// Replacing the group also drops Close, so it is restored here.
private struct ReadOnlyDocumentCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w")
        }
    }
}

private struct AppInfoCommands: Commands {
    @Environment(\.openWindow)
    private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About PDFView") {
                openWindow(id: "about")
            }
        }
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openURL)
    private var openURL
    @Environment(\.openWindow)
    private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            // Offline and generated from the menus, so it comes before the online README.
            Button("Keyboard Shortcuts") {
                openWindow(id: "keyboard-shortcuts")
            }

            Button("PDFView Help") {
                openURL(AppLinks.readme)
            }

            Button("Report an Issue…") {
                openURL(AppLinks.issues)
            }
        }
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/duhman/pdfview")!
    static let readme = URL(string: "https://github.com/duhman/pdfview#readme")!
    static let issues = URL(string: "https://github.com/duhman/pdfview/issues/new")!
    static let license = URL(string: "https://github.com/duhman/pdfview/blob/main/LICENSE")!
}
