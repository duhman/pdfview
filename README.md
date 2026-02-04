# PDFView

A native, blazing-fast macOS PDF reader built with SwiftUI and Apple's PDFKit framework. Designed for developers who appreciate clean code, native performance, and modern macOS architecture.

## ✨ Features

- **Native Performance**: Hardware-accelerated PDF rendering via Apple's PDFKit
- **Modern Architecture**: Pure Swift Package Manager project—no Xcode project files
- **SwiftUI Integration**: Latest DocumentGroup APIs for native document handling
- **Minimal & Fast**: Single window per PDF, instant rendering
- **Dark Mode**: Automatic system appearance support
- **Keyboard Navigation**: Full keyboard shortcut support

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/duhman/pdfview.git
cd pdfview

# Build the app
./build_app.sh

# Launch PDFView
open PDFView.app
```

## 📋 Requirements

- **macOS**: 26.2+ (latest only)
- **Swift**: 6.2+
- **Xcode**: 16.0+ (Command Line Tools)

## 🛠️ Building from Source

### One-Command Build

```bash
./build_app.sh
```

This creates `PDFView.app` in the project directory, ready to use.

### Manual Build

```bash
# Development build
swift build

# Release build
swift build -c release

# Run directly (for testing)
swift run
```

## 🎯 Setting as Default PDF App

### Option 1: Right-Click (Per File)
1. Right-click any PDF file
2. Select **Get Info** (⌘+I)
3. Under **Open with:**, select **PDFView**
4. Click **Change All...** to apply to all PDFs

### Option 2: Command Line (All PDFs)
```bash
# Install duti if not already installed
brew install duti

# Set PDFView as default for all PDF files
duti -s com.bigmac.pdfview com.adobe.pdf all
```

### Option 3: System Settings
1. Open **System Settings**
2. Navigate to **Desktop & Dock**
3. Scroll to **Default web browser** (macOS uses this for document handlers too)
4. Select **PDFView**

## 🏗️ Architecture

### Design Decisions

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Build System** | Swift Package Manager | No Xcode project, CI/CD friendly |
| **UI Framework** | SwiftUI + DocumentGroup | Native document-based architecture |
| **PDF Engine** | PDFKit | Apple's native, hardware-accelerated framework |
| **Bridge Pattern** | NSViewRepresentable | Clean SwiftUI/AppKit integration |
| **Document Model** | FileDocument | SwiftUI's native document protocol |

### Project Structure

```
pdfview/
├── Package.swift                    # Swift Package Manager manifest
├── build_app.sh                     # App bundling script
├── README.md                        # This file
├── .gitignore                       # Git ignore rules
├── Sources/
│   ├── PDFViewApp/
│   │   ├── PDFViewApp.swift         # @main App entry point
│   │   └── PDFViewerDocument.swift  # FileDocument implementation
│   └── Views/
│       ├── PDFContentView.swift     # Main SwiftUI interface
│       └── PDFKitView.swift         # PDFKit NSViewRepresentable bridge
└── Resources/
    └── Info.plist                   # App metadata & PDF association
```

### Key Implementation Details

**DocumentGroup Pattern** (`Sources/PDFViewApp/PDFViewApp.swift`):
```swift
@main
struct PDFViewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: PDFViewerDocument.self) { file in
            PDFContentView(document: file.$document)
        }
        .defaultSize(width: 1000, height: 800)
    }
}
```

**PDFKit Bridge** (`Sources/Views/PDFKitView.swift`):
```swift
struct PDFKitView: NSViewRepresentable {
    var document: PDFDocument?
    @Binding var zoomScale: CGFloat
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}
```

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘+O` | Open PDF file |
| `⌘+W` | Close window |
| `⌘+Q` | Quit app |
| `⌘++` | Zoom in |
| `⌘+-` | Zoom out |
| `⌘+0` | Reset zoom |
| `⌘+F` | Find in document |
| `⌘+P` | Print document |
| `⌘+[` | Previous page |
| `⌘+]` | Next page |

## 🔧 Development

### Adding Features

The codebase follows Swift 6.2 best practices with strict concurrency checking:

1. **Document Handling**: Extend `PDFViewerDocument.swift` for new file types
2. **UI Components**: Add SwiftUI views in `Sources/Views/`
3. **PDF Features**: Access PDFKit's rich API via the `PDFKitView` bridge

### Code Quality

- **Swift 6.2** with complete concurrency checking
- **No external dependencies** (pure Apple frameworks)
- **Type-safe** document handling via `FileDocument` protocol
- **Memory-efficient** single-window-per-document architecture

## 📦 Distribution

### Local Installation

```bash
# Copy to Applications folder
cp -R PDFView.app /Applications/

# Or create symlink
ln -s $(pwd)/PDFView.app /Applications/PDFView.app
```

### Sharing the App

The built `PDFView.app` is self-contained and can be:
- Copied to other Macs running macOS 15+
- Shared via AirDrop, Dropbox, etc.
- Installed by simply dragging to `/Applications`

**Note**: If the app is ad-hoc signed (default), users may need to:
1. Right-click the app and select **Open** (first launch only)
2. Or run: `xattr -cr PDFView.app` to remove quarantine

### Distribution (Developer ID + Notarization)

```bash
# Sign with Developer ID (requires SIGNING_IDENTITY)
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build_app.sh

# Verify entitlements and signature
codesign -dv --entitlements :- PDFView.app

# Notarize (requires a keychain profile created via notarytool)
NOTARIZE=true NOTARY_PROFILE="your-notary-profile" \
  SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./build_app.sh

# Verify notarization
spctl -a -v PDFView.app
```

## 🐛 Troubleshooting

### App Won't Open

```bash
# Remove quarantine attribute
xattr -cr PDFView.app

# Or allow in System Settings > Privacy & Security
```

### PDFs Not Opening

1. Check **System Settings > Privacy & Security > Files and Folders**
2. Ensure PDFView has access to the folder containing your PDFs
3. Try opening via **File > Open** menu instead of double-click

### Build Errors

```bash
# Clean build
swift package clean
rm -rf .build/

# Rebuild
./build_app.sh
```

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

This is a personal project by [@duhman](https://github.com/duhman).

## 🙏 Acknowledgments

- Built with Apple's [PDFKit](https://developer.apple.com/documentation/pdfkit) framework
- Uses [SwiftUI](https://developer.apple.com/documentation/swiftui)'s DocumentGroup architecture
- Inspired by the macOS document-based app paradigm

## 📸 Screenshots

*Screenshots coming soon...*

---

**Made with ❤️ for macOS** — Fast, native, no Electron, no bloat.
