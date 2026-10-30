# PDFView

A full native Mac PDF reader with private, offline visual signing.

- Native and fast, built with SwiftUI and Apple's PDFKit.
- Sign into the PDF's own signature fields or anywhere on a page, then move and resize your signature.
- Save a flattened signed copy that keeps page sizes, links, and bookmarks.
- Private: no network access, cloud services, or telemetry; your saved signature stays only on this Mac.

## Install

Requires **macOS 14.2 or later**. Download the universal ZIP for Apple silicon and Intel from the [latest release](https://github.com/duhman/pdfview/releases/latest), unzip it, and move `PDFView.app` to Applications. The features below describe the current source; older downloads may not include all of them.

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

## Features

### Read

- Page indicator with PDF page labels and a validated Go to Page sheet.
- A native sidebar with a Thumbnails/Outline selector and current-section selection in the outline.
- Asynchronous text search with match highlights and previous/next navigation; VoiceOver hears the result and each move.
- Unlock password-protected PDFs with secure entry; cancel keeps the locked reader open with an Unlock banner.
- Move between form fields with Go > Next/Previous Form Field; text fields open for typing.
- Print the PDF with any placed stamps included; document print permissions are respected.
- Remember your page, scroll position and zoom for the 200 most recently read file paths.
- Single-page and two-page layouts, continuous scrolling, and full screen.
- Actual Size, Zoom to Fit, and manual zoom.

### Sign offline

- Create and edit independent signature and initials profiles by drawing, typing, or importing an image.
- Choose Signature, Initials, or Date from the Sign toolbar menu; dates use today’s date and your locale at placement time.
- Place each stamp in the PDF’s own signature fields or anywhere on a page, including the keyboard placement commands. Place in Next Field skips fields that already hold a stamp.
- Initials and dates start at their own sizes (60 and 110 pt wide; signatures 180 pt), and the last size you resize each kind to is reused while the app is open.
- Place Initials on Every Page initials each page that has none, in one undoable step, at the position of your selected or last initials, or in the bottom-right margin.
- After each stamp the Sign menu goes back to Signature, and its commands say which kind they will place.
- Select, move, resize, delete, undo, and redo signature placements, with the mouse or the keyboard.
- Fill the PDF's form fields; a filled form can be saved as a signed copy even without a stamp.
- Get asked before closing or quitting with unsaved signatures or form entries.
- VoiceOver identifies signatures and initials by name, dates by displayed text, and every stamp by page and field or position, with Remove and Move actions.
- Save a flattened signed copy while keeping page sizes, links, and bookmarks; the original stays separate.
- Follow page-by-page save progress and cancel before the destination changes.
- Keep both profiles locally in the app's sandbox, shared across document windows; delete either one from the Sign menu.
- Overlays follow Increase Contrast, and messages use at least 12 pt text.

For encrypted sources, Save Signed Copy offers **Keep password protection**, enabled by default when PDFView knows the password. Locked PDFs unlock only through PDFView’s own password sheet; File > Unlock… reopens it while a PDF is locked.

Signatures are **visual stamps, not certificate-based digital signatures**. They do not provide certificate identity verification or cryptographic tamper detection. Flattening puts the visible signature into the page content; it does not make the PDF tamper-proof.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥⌘S | Start/Stop Signing |
| ⌃⇧⌘S | Place Signature (then click, or use a placement command) |
| ⌥⇧⌘I | Place Initials (then click, or use a placement command) |
| ⌥⇧⌘D | Place Date (then click, or use a placement command) |
| ⌥⌘N | Place in Next Field |
| ⌥⌘P | Place on Current Page |
| ⌥⌘] / ⌥⌘[ | Select Next / Previous Signature |
| ← → ↑ ↓ | Move the selected stamp 1 pt (⇧ 10 pt) |
| ⌥⇧→ / ⌥⇧↑, ⌥⇧← / ⌥⇧↓ | Enlarge / shrink the selected stamp |
| ⌫ | Remove the selected stamp from the page |
| ⇧⌘E | Save Signed Copy… (File menu) |
| ⌥⇧⌘E | Share Signed Copy… |
| ⇧⌘R | Show Signed Copy in Finder |
| Esc | Cancel an export, finish signing, close Find, deselect a stamp, or close the saved banner, in that order (in the Find field, closes Find first) |
| ⌃⌘S | Show/Hide Sidebar |
| ⌥⌘G | Go to Page… |
| ⌥↓ / ⌥↑ | Next / Previous Page |
| ⌥⌘↑ / ⌥⌘↓ | First / Last Page (Option-arrows page even while a stamp is selected) |
| ⌥⌘→ / ⌥⌘← | Next / Previous Form Field |
| ⌘F | Find |
| ⌘G / ⇧⌘G | Next / Previous Match |
| ⌃⌘F | Enter/Exit Full Screen |
| ⇧⌘P | Page Setup… |
| ⌘P | Print |
| ⌘Z / ⇧⌘Z | Undo / redo drawing edits while the signature canvas has focus |
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

Signed exports capture form values and a stable document snapshot together, then render and validate that private snapshot in the background. Closing or quitting after a save proceeds only when the live stamps and form values still match the saved copy. Form baselines are captured before editing, including before the incremental field scan finishes. Viewer documents explicitly offer no writable content types; use Save Signed Copy for flattened output. Signed exports reject replacing the original file. The window retains password state only for the current PDF, offers secure unlock, and passes the save accessory’s protection choice to export. Protected export with nonzero page origins fails with recovery advice instead of risking an invalid copy.

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
