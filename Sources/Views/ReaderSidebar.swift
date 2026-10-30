import Quartz
import SwiftUI

struct ReaderSidebar: View {
    let reader: ReaderController
    @State private var tab: Tab = .thumbnails

    private enum Tab: String, CaseIterable {
        case thumbnails = "Thumbnails"
        case outline = "Outline"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar content", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            // The label stays for VoiceOver; on screen the segments speak for themselves.
            .labelsHidden()
            .padding(10)

            Divider()

            switch tab {
            case .thumbnails:
                PDFThumbnails(view: reader.view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .outline:
                if reader.outline.isEmpty {
                    ContentUnavailableView(
                        "No Outline",
                        systemImage: "list.bullet.indent",
                        description: Text("This PDF has no bookmarks.")
                    )
                } else {
                    List(reader.outline, children: \.children, selection: outlineSelection) { node in
                        Text(node.item.label ?? "Untitled section").tag(node.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Document outline")
                }
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityLabel("Document sidebar")
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
