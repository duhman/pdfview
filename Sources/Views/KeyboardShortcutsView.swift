import SwiftUI

/// Help > Keyboard Shortcuts: every menu chord, grouped by menu, then the keys the document handles.
struct KeyboardShortcutsView: View {
    private static let menus = ["File", "Edit", "View", "Go", "Sign"]

    var body: some View {
        ScrollView {
            // One grid for every section, so the key column lines up from File down to the document keys.
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Self.menus, id: \.self) { menu in
                    heading(menu)
                    ForEach(MenuShortcuts.entries.filter { $0.menu == menu }, id: \.title) { entry in
                        row(
                            keys: MenuShortcuts.display(entry.shortcut),
                            action: entry.title,
                            spokenKeys: MenuShortcuts.spoken(entry.shortcut)
                        )
                    }
                }
                heading("In the Document")
                ForEach(MenuShortcuts.documentKeys, id: \.keys) { key in
                    row(keys: key.keys, action: key.action, spokenKeys: key.keys)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 640)
    }

    private func heading(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, title == Self.menus.first ? 0 : 14)
                .padding(.bottom, 2)
                .gridCellColumns(2)
        }
    }

    private func row(keys: String, action: String, spokenKeys: String) -> some View {
        GridRow {
            Text(keys)
                .monospaced()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                // The longest key list wraps instead of pushing every action far to the right.
                .frame(maxWidth: 110, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(.trailing)
            Text(action)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(action), \(spokenKeys)")
    }
}
