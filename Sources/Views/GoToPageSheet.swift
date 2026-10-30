import SwiftUI

struct GoToPageSheet: View {
    let reader: ReaderController
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Page").font(.headline)
            TextField("Page number (1–\(reader.pageCount))", text: $input)
                .focused($focused)
                .accessibilityLabel("Page number")
                .onSubmit(go)
            Text("Enter a page number from 1 to \(reader.pageCount).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ReaderLogic.pageIndex(input: input, count: reader.pageCount) == nil)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            input = String((reader.pageIndex ?? 0) + 1)
            focused = true
        }
    }

    private func go() {
        guard let index = ReaderLogic.pageIndex(input: input, count: reader.pageCount) else { return }
        reader.go(to: index)
        dismiss()
    }
}
