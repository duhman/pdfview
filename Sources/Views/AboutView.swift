import SwiftUI

/// About dialog displaying app version, build date, and copyright information
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("PDFView")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Built \(buildDateString)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            Text("© 2026 BigMac. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 320)
    }

    private var buildDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: buildDate)
    }

    /// Compile-time build date derived from the __DATE__ equivalent.
    /// Falls back to current date for development builds.
    private var buildDate: Date {
        if let infoDate = Bundle.main.infoDictionary?["BuildDate"] as? String,
           let date = ISO8601DateFormatter().date(from: infoDate) {
            return date
        }
        return Date()
    }
}
