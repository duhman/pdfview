# PDFView

Native macOS PDF reader built with SwiftUI and PDFKit, with a simple visual-signature workflow.

## Scope

- PDF viewing via Apple PDFKit
- Visual signature stamp placement and flattened export
- Local-only signature profile storage

## Non-goals

- Certificate-based digital signatures (PKI)
- Cloud sync or remote signing services

## Requirements

- macOS 26.2+
- Swift 6.2+
- Xcode Command Line Tools

## Build

```bash
# Debug build
swift build

# Release app bundle
./build_app.sh
```

The bundle is created at `PDFView.app`.

## Quality Checks

```bash
swift build
swift build -Xswiftc -strict-concurrency=complete
./build_app.sh debug
```

Test suites are included under `/Users/minimac/projects/pdfview/Tests/PDFViewAppTests` for XCTest/Swift-Testing capable toolchains.

## Usage

1. Open a PDF (double-click or `File > Open`).
2. Click the signature toolbar button to start signing.
3. Create or edit your signature profile (Draw / Type / Import).
4. Place signatures in field mode or free placement mode.
5. Save a signed copy.

Note: Signing is a **visual signature stamp** and not a certificate-based digital signature.

## Architecture

- `DocumentGroup` app model (`Sources/PDFViewApp/PDFViewApp.swift`)
- `FileDocument` PDF model (`Sources/PDFViewApp/PDFViewerDocument.swift`)
- SwiftUI + PDFKit bridge (`Sources/Views/PDFKitView.swift`)
- Signature setup and placement UX (`Sources/Views/PDFContentView.swift`, `Sources/Views/SignatureSetupSheet.swift`)

## Distribution

### Local development

```bash
./build_app.sh
```

Default is ad-hoc signing for local use.

### Developer ID + notarization

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build_app.sh

NOTARIZE=true \
NOTARY_PROFILE="your-notary-profile" \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./build_app.sh
```

The script verifies signatures with:

- `codesign --verify --strict --verbose=2 PDFView.app`
- `spctl -a -vv --type execute PDFView.app` (Developer ID builds)

## Set as default PDF app

### Finder

1. Right-click any PDF file
2. Choose **Get Info**
3. Under **Open with**, select **PDFView**
4. Click **Change All**

### Command line

```bash
brew install duti
duti -s com.bigmac.pdfview com.adobe.pdf all
```

## Security notes

- App Sandbox is enabled in distribution entitlements.
- File access is limited to user-selected files/folders for read/write.
- Signed-copy export is flattened from an immutable baseline document plus in-session placements.

## References

- [SwiftUI DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup)
- [SwiftUI FileDocument](https://developer.apple.com/documentation/swiftui/filedocument)
- [PDFKit](https://developer.apple.com/documentation/pdfkit)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

## License

MIT. See `LICENSE`.
