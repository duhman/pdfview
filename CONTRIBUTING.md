# Contributing to PDFView

Thank you for contributing. PDFView is a sandboxed, macOS-only SwiftUI + PDFKit app.

## Prerequisites

- macOS 14.2+
- Xcode 16+ (recommended) or Swift 6 with Apple SDKs
- Git

## Setup

```bash
git clone https://github.com/duhman/pdfview.git
cd pdfview
swift build
swift test
./build_app.sh debug
```

Linux hosts cannot link the AppKit target; use a Mac or rely on GitHub Actions for build/test.

## Architecture overview

```
Sources/
├── PDFViewApp/
│   ├── PDFViewApp.swift
│   ├── PDFViewerDocument.swift
│   ├── SignatureProfile.swift
│   ├── SignatureStore.swift
│   ├── SigningCommands.swift
│   ├── SigningFlowLogic.swift
│   └── SigningMode.swift
└── Views/
    ├── PDFContentView.swift
    ├── PDFKitView.swift
    ├── SignatureSetupSheet.swift
    └── AboutView.swift
```

Patterns:

- `DocumentGroup` + `FileDocument` for PDF documents
- `FocusedValues` for menu commands
- `SignatureStore` for local profile persistence
- `SigningMode` state for placement workflow

## Quality checks

```bash
swiftformat .
swiftlint
swift build --configuration release
swift test
./build_app.sh debug
```

CI (`.github/workflows/ci.yml`) runs build, test, app bundle packaging, SwiftLint, and SwiftFormat on `macos-15`.

## Tests

Unit tests live in `Tests/PDFViewAppTests/` and use [Swift Testing](https://developer.apple.com/documentation/testing). They cover document export helpers, signing flow logic, and signature profile storage.

UI and PDF rendering still require manual smoke testing on macOS.

## Commits

We prefer [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Security

- Keep App Sandbox entitlements minimal (`Resources/PDFView.entitlements`).
- Use security-scoped resource access when reading imported signature images or writing exported PDFs.
- Do not add network entitlements without an explicit product decision.
- Report vulnerabilities via [GitHub Security Advisories](https://github.com/duhman/pdfview/security/advisories/new).

## Pull requests

1. Branch from `main`
2. Keep changes focused
3. Update `CHANGELOG.md` (Unreleased) for user-visible changes
4. Ensure `swift test` passes on macOS
5. Describe manual Mac verification if UI or signing behavior changed

## Resources

- [DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup)
- [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument)
- [PDFKit](https://developer.apple.com/documentation/pdfkit)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Swift Testing](https://developer.apple.com/documentation/testing)
