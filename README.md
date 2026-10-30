# PDFView

A full native Mac PDF reader with private, offline visual signing.

- Native and fast, built with SwiftUI and Apple's PDFKit.
- Sign into the PDF's own signature fields or anywhere on a page, then move and resize your signature.
- Save a flattened signed copy that keeps page sizes, links, and bookmarks.
- Private: no network access, cloud services, or telemetry; your saved signature stays only on this Mac.

## Install

Requires **macOS 14.2 or later**. Download the universal ZIP for Apple silicon and Intel from the [latest release](https://github.com/duhman/pdfview/releases/latest), unzip it, and move `PDFView.app` to Applications. The feature list below is the target for this release; older downloads may not include all of it.

The downloadable build is ad-hoc signed and not notarized. For the first launch:

| macOS version | Open PDFView |
| --- | --- |
| macOS 14 | In Finder, right-click `PDFView.app`, choose **Open**, then confirm **Open**. |
| macOS 15 or later | Try opening the app once and dismiss the alert. Open **System Settings > Privacy & Security > Open Anyway** for PDFView, authenticate if asked, and confirm **Open**. The right-click override is no longer available. |

### Set as your default PDF reader

In Finder, select a PDF and choose **Get Info > Open with > PDFView > Change All**.

If you have `duti` installed, you can also run:

```bash
duti -s com.bigmac.pdfview com.adobe.pdf all
```

## Features — target for this release

These are the release targets being integrated and verified, not a claim about every existing download.

### Read

- Page indicator and Go to Page.
- Thumbnails and document outline (bookmarks) in the sidebar.
- Find text and Print.
- Remember your place when reopening a document.
- Single-page and two-page layouts, continuous scrolling, and full screen.
- Actual Size, Zoom to Fit, and manual zoom.

### Sign offline

- Create a signature by drawing, typing, or importing an image; edit your saved signature.
- Place it in the PDF's own signature fields or anywhere on a page.
- Select, move, resize, delete, undo, and redo signature placements.
- Save a flattened signed copy while keeping page sizes, links, and bookmarks; the original stays separate.
- Keep the signature profile locally in the app's sandbox, shared across document windows.

Signatures are **visual stamps, not certificate-based digital signatures**. They do not provide certificate identity verification or cryptographic tamper detection. Flattening puts the visible signature into the page content; it does not make the PDF tamper-proof.

### Keyboard shortcuts — release target

| Shortcut | Action |
| --- | --- |
| ⌥⌘S | Start/Stop Signing |
| ⇧⌘E | Save Signed Copy… |
| Esc | Finish signing |
| ⌘F | Find |
| ⌘P | Print |
| ⌘0 | Actual Size |
| ⌘9 | Zoom to Fit |
| ⌘+ / ⌘− | Zoom in / out |

## Development

Use a Mac with Xcode 27.1 or later (Swift 6.4); that is the toolchain PDFView is built and tested with. No Homebrew Bash is needed.

```bash
git clone https://github.com/duhman/pdfview.git
cd pdfview
swift build
swift test
/bin/bash ./build_app.sh debug
open PDFView.app
```

To build a release bundle:

```bash
/bin/bash ./build_app.sh release
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the pinned SwiftLint and SwiftFormat setup, quality checks, icon generation, and manual verification. There is no hosted CI: run `/bin/bash scripts/ci-local.sh` before pushing. It builds both bundle configurations with `/bin/bash`, runs the tests, checks the bundle, and lints the unmodified checkout.

### Signing and notarization

Local builds use ad-hoc signing (`SIGNING_IDENTITY=-`) by default. With a Developer ID identity and an existing `notarytool` keychain profile:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=true \
NOTARY_PROFILE="your-notary-profile" \
VERSION="0.1.0" \
BUILD_NUMBER="1" \
/bin/bash ./build_app.sh release
```

The script submits a ZIP, requires an Accepted result, staples and validates the app's ticket, and creates `PDFView.zip` containing the stapled app. Set `ARCHES="arm64 x86_64"` to build a universal bundle. Developer ID credentials are not needed for local ad-hoc builds.

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Security policy](.github/SECURITY.md)

Report bugs through [GitHub Issues](https://github.com/duhman/pdfview/issues) and vulnerabilities through a [private security advisory](https://github.com/duhman/pdfview/security/advisories/new).

MIT licensed — see [LICENSE](LICENSE).
