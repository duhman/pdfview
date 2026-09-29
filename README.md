# PDFView

A native macOS PDF reader and visual signature stamp app built with Swift 6, SwiftUI, and PDFKit.

![macOS](https://img.shields.io/badge/macOS-14.2+-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Native PDF reading

- Fast PDF rendering via PDFKit
- Continuous scrolling and zoom
- PDF document type association (`com.adobe.pdf`)
- DocumentGroup-based window and recents integration

### Visual signatures (not certificate signatures)

- Draw, type, or import a signature image
- Place stamps on pages or on detected signature widget fields
- Undo and redo for placements in the current session
- Export a flattened signed copy to a user-chosen path
- Signature profile stored locally under Application Support (no network)

### Security and privacy

- App Sandbox with user-selected read/write file access
- Security-scoped resource access for import and export URLs chosen in sheets/panels
- No cloud services or telemetry

## Quick Start

### Build from source (macOS)

```bash
git clone https://github.com/duhman/pdfview.git
cd pdfview
swift build -c release
./build_app.sh release
cp -R PDFView.app /Applications/
```

Pre-built release artifacts may be published on the [GitHub Releases](https://github.com/duhman/pdfview/releases) page when available.

### Set as default PDF reader

```bash
duti -s com.bigmac.pdfview com.adobe.pdf all
```

Or use Finder: Get Info on a PDF, Open with PDFView, Change All.

## Requirements

- macOS 14.2 or later
- Xcode 16+ (or a Swift 6 toolchain that ships AppKit/SwiftUI/PDFKit SDKs)

## Development

```bash
swift build
swift test
swiftlint
swiftformat --lint .
./build_app.sh debug
```

CI runs on `macos-15` GitHub-hosted runners with the Xcode toolchain (`DEVELOPER_DIR`).

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow details.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - design and data flow
- [CONTRIBUTING.md](CONTRIBUTING.md) - contributor setup
- [CHANGELOG.md](CHANGELOG.md) - release notes
- [Security policy](.github/SECURITY.md) - vulnerability reporting

## Project structure

```
pdfview/
├── Sources/
│   ├── PDFViewApp/     # App entry, document model, signing logic
│   └── Views/          # SwiftUI and PDFKit bridge
├── Tests/PDFViewAppTests/
├── Resources/          # Info.plist template and entitlements
├── Package.swift
└── build_app.sh        # .app packaging and codesign
```

## Build configuration

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name"
export NOTARIZE="true"
export NOTARY_PROFILE="your-notary-profile"
export VERSION="1.0.0"
export BUILD_NUMBER="1"
./build_app.sh release
```

Ad-hoc signing uses `SIGNING_IDENTITY=-` (default).

## Contributing

Contributions are welcome. Please run `swift test` and lint/format checks before opening a PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Bug reports and security

- Bugs and features: GitHub Issues with the provided templates
- Security issues: [private advisory](https://github.com/duhman/pdfview/security/advisories/new) (see [SECURITY.md](.github/SECURITY.md))

## License

MIT - see [LICENSE](LICENSE).
