import SwiftUI

struct GoToPageSheet: View {
    let reader: ReaderController
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Nil while the input is empty or names a real page; otherwise says what is wrong and what is allowed.
    nonisolated static func validationMessage(input: String, count: Int) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, ReaderLogic.pageIndex(input: trimmed, count: count) == nil else { return nil }
        if let number = Int(trimmed) {
            return "There is no page \(number). Enter a number from 1 to \(count)."
        }
        return "Enter a page number from 1 to \(count)."
    }

    var body: some View {
        let message = Self.validationMessage(input: input, count: reader.pageCount)
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Page").font(.headline)
            HStack {
                Text("Page number:")
                    .accessibilityHidden(true)
                TextField("1–\(reader.pageCount)", text: $input)
                    .focused($focused)
                    .accessibilityLabel("Page number")
                    .accessibilityHint("A number from 1 to \(reader.pageCount)")
                    .onSubmit(go)
            }
            if let message {
                // Red marks the problem; the words stay in the primary colour so they keep full contrast.
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(message)")
            } else {
                Text("Enter a page number from 1 to \(reader.pageCount).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ReaderLogic.pageIndex(input: input, count: reader.pageCount) == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            input = String((reader.pageIndex ?? 0) + 1)
            focused = true
        }
        .onChange(of: message) { _, newMessage in
            if let newMessage {
                NSAccessibility.post(
                    element: NSApp.keyWindow as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: newMessage]
                )
            }
        }
    }

    private func go() {
        guard let index = ReaderLogic.pageIndex(input: input, count: reader.pageCount) else { return }
        reader.go(to: index)
        dismiss()
    }
}
