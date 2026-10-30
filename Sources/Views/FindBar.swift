import SwiftUI

struct FindBar: View {
    let find: FindController
    let onEscape: () -> Void
    @FocusState private var focused: Bool

    /// What VoiceOver hears when the result changes: nothing while matches are still arriving, then
    /// the count, then the position after each Next or Previous.
    nonisolated static func announcement(for state: FindState) -> String? {
        guard !state.query.isEmpty, !state.isSearching else { return nil }
        guard let index = state.currentIndex, !state.isEmpty else { return "No matches" }
        return "Match \(index + 1) of \(state.count)"
    }

    var body: some View {
        HStack {
            TextField("Find in document", text: Binding(get: { find.state.query }, set: find.search))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { find.advance() }
                .accessibilityLabel("Find in document")
            Text(find.state.matchText)
                .monospacedDigit()
                .accessibilityLabel("Find matches")
                .accessibilityValue(find.state.matchText)
            if find.state.isSearching {
                ProgressView().controlSize(.small).accessibilityLabel("Searching document")
            }
            Button { find.advance(backwards: true) } label: {
                Label("Previous Match", systemImage: "chevron.up")
            }
            .disabled(find.state.isEmpty)
            Button { find.advance() } label: {
                Label("Next Match", systemImage: "chevron.down")
            }
            .disabled(find.state.isEmpty)
            Button("Done", action: find.close)
        }
        .labelStyle(.iconOnly)
        .padding(8)
        .background(.bar)
        .onAppear { focused = true }
        .onChange(of: find.focusRequest) { _, _ in focused = true }
        .onChange(of: Self.announcement(for: find.state)) { _, message in
            if let message {
                StampAccessibility.announce(message, in: NSApp.keyWindow, priority: .medium)
            }
        }
        .onExitCommand(perform: onEscape)
    }
}
