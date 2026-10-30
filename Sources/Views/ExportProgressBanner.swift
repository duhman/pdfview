import SwiftUI

/// Why the window is rendering a flattened copy; the exporter's progress text only knows about saving.
enum ExportPurpose {
    case signedCopy
    case print

    /// Spoken when the banner appears and used as the progress bar's label.
    var title: String {
        switch self {
        case .signedCopy: "Saving signed copy"
        case .print: "Preparing to print"
        }
    }

    func text(for progress: ExportProgress) -> String {
        switch self {
        case .signedCopy:
            progress.text
        case .print:
            progress.stage == .rendering
                ? "Preparing to print… \(progress.completedPages) of \(progress.totalPages) pages"
                : "Preparing to print…"
        }
    }

    /// What the window says when the export ends early: a cancel is the user's own choice, so it
    /// gets a banner message, and anything else is an error alert.
    enum Feedback: Equatable {
        case notice(String)
        case alert(ErrorAlert)
    }

    func feedback(for error: Error) -> Feedback {
        guard !(error is CancellationError) else {
            return .notice(Self.cancelledNotice(self))
        }
        return .alert(ErrorAlert(
            title: self == .print ? "Couldn’t Print PDF" : "Couldn’t Save Signed Copy",
            error: error
        ))
    }

    /// Cancelling Save Signed Copy's panel is a cancelled save too, so the banner says so the same way;
    /// nil once a destination is chosen.
    static func savePanelNotice(for response: NSApplication.ModalResponse) -> String? {
        response == .OK ? nil : cancelledNotice(.signedCopy)
    }

    private static func cancelledNotice(_ purpose: Self) -> String {
        purpose == .print ? "Printing cancelled." : "Save cancelled."
    }

    var cancelHelp: String {
        switch self {
        case .signedCopy: "Cancel without changing the destination"
        case .print: "Cancel printing"
        }
    }
}

struct ExportProgressBanner: View {
    let progress: ExportProgress
    var purpose: ExportPurpose = .signedCopy
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text(purpose.text(for: progress)).monospacedDigit()
            ProgressView(value: progress.fraction)
                .frame(maxWidth: 160)
                .accessibilityLabel(purpose.title)
                .accessibilityValue("\(progress.completedPages) of \(progress.totalPages) pages")
            Spacer()
            Button("Cancel", action: cancel)
                .help(purpose.cancelHelp)
        }
        .padding(8)
        .background(.bar)
        .onAppear {
            StampAccessibility.announce(purpose.title, in: NSApp.keyWindow)
        }
    }
}
