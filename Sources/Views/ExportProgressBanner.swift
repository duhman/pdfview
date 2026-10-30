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
