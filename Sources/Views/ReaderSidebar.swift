import Quartz
import SwiftUI

struct ReaderSidebar: View {
    let reader: ReaderController
    @State private var tab: Tab = .thumbnails

    enum Tab: String, CaseIterable {
        case thumbnails = "Thumbnails"
        case outline = "Outline"
    }

    /// Without an outline only thumbnails are shown, so the sidebar never shows an empty list.
    static func shownTab(_ tab: Tab, hasOutline: Bool) -> Tab {
        hasOutline ? tab : .thumbnails
    }

    /// A segmented picker ignores `.disabled` on one segment, so the picker appears only with a choice.
    static func availableTabs(hasOutline: Bool) -> [Tab] {
        hasOutline ? Tab.allCases : [.thumbnails]
    }

    var body: some View {
        let hasOutline = !reader.outline.isEmpty
        VStack(spacing: 0) {
            let tabs = Self.availableTabs(hasOutline: hasOutline)
            if tabs.count > 1 {
                Picker("Sidebar content", selection: shownTabBinding(hasOutline: hasOutline)) {
                    ForEach(tabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                // The label stays for VoiceOver; on screen the segments speak for themselves.
                .labelsHidden()
                .help("Show page thumbnails or the document outline")
                .padding(10)

                Divider()
            }

            switch Self.shownTab(tab, hasOutline: hasOutline) {
            case .thumbnails:
                PDFThumbnails(view: reader.view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .outline:
                List(reader.outline, children: \.children, selection: outlineSelection) { node in
                    Text(node.item.label ?? "Untitled section").tag(node.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Document outline")
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityLabel("Document sidebar")
    }

    /// Keeps the chosen tab, so Outline comes back when a PDF with an outline is shown again.
    private func shownTabBinding(hasOutline: Bool) -> Binding<Tab> {
        Binding(
            get: { Self.shownTab(tab, hasOutline: hasOutline) },
            set: { tab = $0 }
        )
    }

    private var outlineSelection: Binding<ObjectIdentifier?> {
        Binding(
            get: { reader.currentOutlineID },
            set: { id in
                if let item = Self.find(id, in: reader.outline) {
                    reader.follow(item)
                }
            }
        )
    }

    static func find(_ id: ObjectIdentifier?, in nodes: [ReaderOutlineNode]) -> PDFOutline? {
        guard let id else { return nil }
        for node in nodes {
            if node.id == id {
                return node.item
            }
            if let match = find(id, in: node.children ?? []) {
                return match
            }
        }
        return nil
    }
}

private struct PDFThumbnails: NSViewRepresentable {
    let view: PDFView?

    func makeNSView(context _: Context) -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView()
        thumbnails.backgroundColor = .clear
        thumbnails.thumbnailSize = NSSize(width: 120, height: 160)
        thumbnails.setAccessibilityLabel("Page thumbnails")
        return thumbnails
    }

    func updateNSView(_ nsView: PDFThumbnailView, context _: Context) {
        nsView.pdfView = view
    }

    static func dismantleNSView(_ nsView: PDFThumbnailView, coordinator _: ()) {
        nsView.pdfView = nil
    }
}
