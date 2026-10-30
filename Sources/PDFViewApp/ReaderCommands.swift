import SwiftUI

struct ReaderCommandActions {
    var reader: ReaderController
    var isBusy: Bool
    var printDocument: () -> Void
    var pageSetup: () -> Void
}

private struct ReaderCommandActionsKey: FocusedValueKey {
    typealias Value = ReaderCommandActions
}

extension FocusedValues {
    var readerActions: ReaderCommandActions? {
        get { self[ReaderCommandActionsKey.self] }
        set { self[ReaderCommandActionsKey.self] = newValue }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.readerActions) private var actions
    private var reader: ReaderController? {
        actions?.reader
    }

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(reader?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                reader?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(reader == nil)
        }
        CommandGroup(after: .toolbar) {
            Picker("Page Layout", selection: Binding(
                get: { reader?.displayMode ?? .singleContinuous },
                set: { reader?.displayMode = $0 }
            )) {
                ForEach(ReaderDisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.inline)
            .disabled(reader == nil)
            Toggle("Show Cover Page Separately", isOn: Binding(
                get: { reader?.displaysAsBook ?? false }, set: { reader?.displaysAsBook = $0 }
            ))
            .disabled(reader?.displayMode.supportsCover != true)
        }
        CommandMenu("Go") { navigationItems }
        CommandGroup(after: .textEditing) { findItems }
        // Replacing .printItem removes the standard Page Setup… too, so it is put back here.
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { actions?.pageSetup() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Print…") { actions?.printDocument() }
                .keyboardShortcut("p")
                .disabled(reader?.canPrint != true || actions?.isBusy == true)
            if let reason = reader?.printDisabledReason {
                Text(reason)
            }
        }
    }

    @ViewBuilder private var navigationItems: some View {
        Button("Next Page") { reader?.view?.goToNextPage(nil) }
            .keyboardShortcut(.downArrow, modifiers: [.option])
            .disabled(reader?.canGoNext != true)
        Button("Previous Page") { reader?.view?.goToPreviousPage(nil) }
            .keyboardShortcut(.upArrow, modifiers: [.option])
            .disabled(reader?.canGoPrevious != true)
        Button("First Page") { reader?.view?.goToFirstPage(nil) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(reader?.canRead != true)
        Button("Last Page") { reader?.view?.goToLastPage(nil) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(reader?.canRead != true)
        Divider()
        Button("Go to Page…") { reader?.showGoToPage = true }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(reader?.canRead != true)
    }

    @ViewBuilder private var findItems: some View {
        Button("Find…") { reader?.find.show() }
            .keyboardShortcut("f")
            .disabled(reader?.canRead != true)
        Button("Find Next") { reader?.find.advance() }
            .keyboardShortcut("g")
            .disabled(reader?.find.state.isEmpty == true || reader == nil)
        Button("Find Previous") { reader?.find.advance(backwards: true) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(reader?.find.state.isEmpty == true || reader == nil)
    }
}
