import SwiftUI

/// Help > Keyboard Shortcuts: every menu chord, grouped by menu, then the keys the document handles.
struct KeyboardShortcutsView: View {
    private static let menus = ["File", "Edit", "View", "Go", "Sign"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Self.menus, id: \.self) { menu in
                    section(menu) {
                        ForEach(MenuShortcuts.entries.filter { $0.menu == menu }, id: \.title) { entry in
                            row(
                                keys: MenuShortcuts.display(entry.shortcut),
                                action: entry.title,
                                spokenKeys: MenuShortcuts.spoken(entry.shortcut)
                            )
                        }
                    }
                }
                section("In the Document") {
                    ForEach(MenuShortcuts.documentKeys, id: \.keys) { key in
                        row(keys: key.keys, action: key.action, spokenKeys: key.keys)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 640)
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                rows()
            }
        }
    }

    private func row(keys: String, action: String, spokenKeys: String) -> some View {
        GridRow {
            Text(keys)
                .monospaced()
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(action)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(action), \(spokenKeys)")
    }
}
