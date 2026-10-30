# Contributing to PDFView

PDFView is a sandboxed, macOS-only SwiftUI and PDFKit app: a full PDF reader with offline visual signing.

## Prerequisites

- macOS 14.2 or later.
- Xcode 27.1 or later (Swift 6.4), the toolchain PDFView is built and tested with.
- Git.

The commands below work with stock macOS `/bin/bash` 3.2. Linux cannot build the AppKit target.

## Build and run

```bash
git clone https://github.com/duhman/pdfview.git
cd pdfview
swift build
swift test
/bin/bash ./build_app.sh debug
open PDFView.app
```

Package a release locally with:

```bash
/bin/bash ./build_app.sh release
```

Both modes produce an ad-hoc signed `PDFView.app`. For a universal build:

```bash
ARCHES="arm64 x86_64" /bin/bash ./build_app.sh release
```

## Install the pinned quality tools

The checks use SwiftLint **0.65.1** and SwiftFormat **0.64.4**. Homebrew's `swiftlint` and `swiftformat` work if they are these versions; otherwise install the pinned binaries outside the checkout and put them on your `PATH`:

```bash
PDFVIEW_TOOLS="$HOME/Library/Caches/PDFView-tools"
mkdir -p "$PDFVIEW_TOOLS/swiftlint" "$PDFVIEW_TOOLS/swiftformat"
curl -fsSL https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip -o "$PDFVIEW_TOOLS/swiftlint.zip"
unzip -oq "$PDFVIEW_TOOLS/swiftlint.zip" -d "$PDFVIEW_TOOLS/swiftlint"
curl -fsSL https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.4/swiftformat.zip -o "$PDFVIEW_TOOLS/swiftformat.zip"
unzip -oq "$PDFVIEW_TOOLS/swiftformat.zip" -d "$PDFVIEW_TOOLS/swiftformat"
"$PDFVIEW_TOOLS/swiftlint/swiftlint" version
"$PDFVIEW_TOOLS/swiftformat/swiftformat" --version
```

## Quality checks

PDFView has no hosted CI. Run the full gate from the repository root before pushing:

```bash
/bin/bash scripts/ci-local.sh
```

It builds the debug and release bundles with stock `/bin/bash`, runs `swift test --parallel`, verifies the bundle (icon, minimum macOS, code signature), checks the SwiftLint and SwiftFormat versions, runs `swiftlint lint --strict` and `swiftformat --lint` on `Sources Tests scripts`, and checks documentation and resources. It exits non-zero if any step fails and lists the failed steps.

To fix formatting, invoke SwiftFormat with just the files you changed, then rerun the checks. Do not format another contributor's files during parallel work. The lint steps check the untouched checkout; they never rewrite it.

## Publish a release

Releases are built on a Mac, not by a hosted workflow:

```bash
/bin/bash scripts/ci-local.sh
ARCHES="arm64 x86_64" VERSION="0.2.0" BUILD_NUMBER="2" /bin/bash ./build_app.sh release
ditto -c -k --keepParent PDFView.app PDFView-0.2.0-universal.zip
gh release create v0.2.0 PDFView-0.2.0-universal.zip --title "PDFView 0.2.0" --notes-file <notes.md>
```

Without a Developer ID the app is ad-hoc signed; the release notes must give the Gatekeeper steps from the README.

## Regenerate the app icon

```bash
swift scripts/make-icon.swift
open .build/AppIcon.iconset/icon_512x512@2x.png
```

The script creates all standard iconset sizes in `.build/AppIcon.iconset` and writes `Resources/AppIcon.icns`. Inspect the 1024-pixel master and small sizes. Commit the script and `.icns` together when the design changes; do not commit the generated iconset.

## Architecture and tests

See [ARCHITECTURE.md](ARCHITECTURE.md) for the release target and sections still in progress. Swift Testing tests live in `Tests/PDFViewAppTests`. Generate PDF fixtures in test code so tests do not depend on local files.

For reader or signing changes, verify the affected flows on a Mac:

- Open PDFs, navigate, search, change zoom/layout, and reopen to check reading position.
- Create or edit a signature, place it in a field and on a page, move/resize, and undo/redo.
- Save and reopen a signed copy; check page dimensions, rotation, links, bookmarks, and form content.
- Check multiwindow state, keyboard commands, VoiceOver, and Print.
- On macOS 14.2, 15, 26 and 27, use Go > Next/Previous Form Field and Activate Form Field to focus a visible text widget, type, then Tab onward. Confirm signing mode, a stamp overlay, an offscreen field or an overlapping link never receives the synthesized widget click. Record the exact OS version and visible result; automated hit-target checks do not verify PDFKit's native editor.

Report which checks ran and what remains unverified. A successful build is not evidence that the on-screen flow works.

## Pull requests

1. Branch from `main` and keep changes focused.
2. Use Conventional Commits and describe the problem the change solves.
3. Update `CHANGELOG.md` under Unreleased for user-visible changes.
4. Run the local checks and document relevant manual verification.

Keep sandbox entitlements minimal and secrets out of source control. Report vulnerabilities through [GitHub Security Advisories](https://github.com/duhman/pdfview/security/advisories/new).
