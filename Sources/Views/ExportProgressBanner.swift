import SwiftUI

struct ExportProgressBanner: View {
    let progress: ExportProgress
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text(progress.text).monospacedDigit()
            ProgressView(value: progress.fraction)
                .frame(maxWidth: 160)
                .accessibilityLabel("Saving signed copy")
                .accessibilityValue("\(progress.completedPages) of \(progress.totalPages) pages")
            Spacer()
            Button("Cancel", action: cancel)
                .help("Cancel without changing the destination")
        }
        .padding(8)
        .background(.bar)
    }
}
