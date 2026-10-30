import Quartz
import SwiftUI

struct ReaderSidebar: View {
    let reader: ReaderController
    @State private var tab = "thumbnails"

    var body: some View {
        TabView(selection: $tab) {
            PDFThumbnails(view: reader.view)
                .tabItem { Label("Thumbnails", systemImage: "rectangle.grid.1x2") }
                .tag("thumbnails")
            if !reader.outline.isEmpty {
                List(reader.outline, children: \.children) { node in
                    Button { reader.follow(node.item) } label: {
                        Text(node.item.label ?? "Untitled section")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(3)
                            .background(reader.currentOutlineID == node.id ? Color.accentColor.opacity(0.2) : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(node.item.label ?? "Untitled section")
                }
                .tabItem { Label("Outline", systemImage: "list.bullet.indent") }
                .tag("outline")
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
        .accessibilityLabel("Document sidebar")
        .onChange(of: reader.outline.isEmpty) { _, empty in
            if empty {
                tab = "thumbnails"
            }
        }
    }
}

private struct PDFThumbnails: NSViewRepresentable {
    let view: PDFView?

    func makeNSView(context _: Context) -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView()
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
