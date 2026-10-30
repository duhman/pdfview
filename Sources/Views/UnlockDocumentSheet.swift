import SwiftUI

struct UnlockDocumentSheet: View {
    let protection: DocumentProtection
    let onUnlock: () -> Void
    let onCancel: () -> Void
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock PDF").font(.headline)
            Text("Enter this PDF's password to read and sign it.")
            SecureField("Password", text: $password).onSubmit(unlock)
            if let error {
                Text(error).foregroundStyle(.red).accessibilityLabel(error)
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
    }

    private func unlock() {
        guard protection.unlock(withPassword: password) else {
            error = "Incorrect password. Try again."
            password.removeAll()
            return
        }
        password.removeAll()
        onUnlock()
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
