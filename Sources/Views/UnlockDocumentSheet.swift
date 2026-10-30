import SwiftUI

struct UnlockDocumentSheet: View {
    let protection: DocumentProtection
    let onUnlock: () -> Void
    let onCancel: () -> Void
    @State private var password = ""
    @State private var error: String?
    @FocusState private var isPasswordFocused: Bool

    /// Nil when the password opened the document; otherwise the message to show and announce.
    static func attempt(_ password: String, with protection: DocumentProtection) -> String? {
        protection.unlock(withPassword: password) ? nil : "Incorrect password. Try again."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock PDF").font(.headline)
            Text("Enter this PDF's password to read and sign it.")
            SecureField("Password", text: $password)
                .focused($isPasswordFocused)
                .onSubmit(unlock)
            if let error {
                // Red marks the problem; the words stay in the primary colour so they keep full contrast.
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    password.removeAll()
                    onCancel()
                }.keyboardShortcut(.cancelAction)
                Button("Unlock", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { isPasswordFocused = true }
    }

    private func unlock() {
        let failure = Self.attempt(password, with: protection)
        password.removeAll()
        guard let failure else {
            onUnlock()
            return
        }
        error = failure
        isPasswordFocused = true
        // Posted every time, so a second wrong password is announced too.
        StampAccessibility.announce(failure, in: NSApp.keyWindow)
    }
}

struct SignedCopyProtectionAccessory: View {
    @Bindable var protection: DocumentProtection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if protection.canKeepPasswordProtection {
                Toggle("Keep password protection", isOn: $protection.keepPasswordProtection)
            }
            Text(protection.exportNotice).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
    }
}
