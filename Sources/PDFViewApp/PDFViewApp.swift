import SwiftUI

/// Main application entry point
/// Uses DocumentGroup for native document-based app architecture
@main
struct PDFViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    /// One signature for the whole app, so editing it in one window updates every window.
    @StateObject private var signatureStore = SignatureStore()

    var body: some Scene {
        DocumentGroup(viewing: PDFViewerDocument.self) { file in
            PDFContentView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(signatureStore)
        }
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.titleBar)
        .commands {
            AppInfoCommands()
            HelpCommands()
            ZoomCommands()
            ReaderCommands()
            SigningCommandMenu(signatureStore: signatureStore)
        }

        Window("About PDFView", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
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

    var body: some Commands {
        CommandGroup(replacing: .help) {
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
