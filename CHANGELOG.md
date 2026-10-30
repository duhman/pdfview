# Changelog

All notable changes to PDFView will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Form entries count as unsaved work: the close prompt names them, and a filled form can be saved without a stamp
- Quitting reviews every window with unsaved signatures or form entries (Review Changes / Discard Changes / Cancel)
- File > Share Signed Copy… and Show Signed Copy in Finder for the window's last saved copy
- Sign > Place in Next Field (⌥⌘N), Place on Current Page (⌥⌘P), Select Next / Previous Signature (⌥⌘] / ⌥⌘[)
- Option-arrow 50 pt nudges and Option-Shift-arrow aspect-locked keyboard resizing for a selected stamp
- VoiceOver elements for placed stamps (signer, page, field or position) with Remove and Move actions, plus position announcements after placing and moving
- Stop Signing context menu while signing; Go to Page explains invalid input inline
- Document-scoped, memory-only password state, secure unlock sheet and save-accessory components for view-layer integration
- Protected signed export with default-on password retention, explicit opt-out and unknown-password notice APIs
- Incremental, cancellable signature-field scanning API for the PDFKit view layer
- Independent signature and initials profiles with legacy JSON migration and initials setup entry point
- Transparent locale-aware date stamp renderer for placement integration
- Thumbnail and recursive outline sidebar, page labels, Go menu and validated Go to Page sheet
- Asynchronous Find with match count, highlights, next/previous commands and Escape dismissal
- Signed printing with PDF permission checks, auto-rotation, temporary-file cleanup and a sandbox print entitlement
- View layout commands for single/two-page and continuous modes, with separate cover-page support
- Remembered page, destination point and zoom using a hashed-path store bounded to 200 files
- Cancellable signed-copy export with page progress, main-actor yielding and duplicate-save protection
- Reader logic, PDFKit integration, print preparation and async export regression tests
- Procedurally drawn macOS app icon, bundled with PDFView, and a Swift regeneration script
- Restored `PDFViewAppTests` Swift Testing target in `Package.swift`
- Committed `Resources/PDFView.entitlements` sandbox template
- `.github/SECURITY.md` vulnerability reporting policy

### Changed
- Signature fields and form widgets are scanned a few pages at a time after the pages appear; page overlays redraw only when their inputs change
- The saved banner stays until closed and names the folder; the signing banner names the keyboard path
- Escape closes Find first when the Find field has focus; leaving signing is announced and focus returns to the document
- Placing before a signature exists runs the placement after setup; Place on Current Page scrolls to the stamp
- Menu names: Create Signature… (when none exists), Delete Saved Signature…, Remove Signature from Page
- Thicker selection outline, larger handles and higher-contrast signature field outlines
- File > Page Setup… is back alongside Print…
- Reader sidebar uses a top segmented control, native outline selection and full-height thumbnails
- About window reads the bundled copyright; app metadata declares the Productivity category
- Verification runs locally: `scripts/ci-local.sh` builds debug and release bundles with stock `/bin/bash`, runs the tests, checks the bundle and runs pinned SwiftLint 0.65.1 / SwiftFormat 0.64.4 on the untouched checkout
- Building requires Xcode 27.1 or later (Swift 6.4), the toolchain the app is tested with
- README and CONTRIBUTING now use the real repository URL and accurate test claims
- README documents shipped reader/signing features and shortcuts, while distinguishing older downloads
- Architecture and contributor documentation describe the release target and reproducible local commands
- `build_app.sh` uses `Resources/Info.plist`, patches metadata, signs the executable with entitlements
- ARCHITECTURE.md aligned with current signing modes and test layout

### Removed
- Unused original PDF bytes, signature-store lookup wrappers and signing-mode convenience property
- Redundant StrictConcurrency upcoming-feature flags in the Swift 6 package
- GitHub Actions workflows (`ci.yml`, `quality.yml`, `release.yml`); checks and releases run locally

### Fixed
- Async exports freeze form/page state before yielding, including unlocked encrypted sources
- Signed-copy destination checks reject the original by path, symlink and hard-link identity
- Finalize yields between writing, geometry repair and validation; pure geometry work runs off the main actor
- Scroll observation is scoped to the PDF clip view and outline lookups are cached per page
- Unsupported geometry fails without replacing the destination and gives normalization/reopen instructions
- Drawing strokes and clearing participate in the sheet window's native undo/redo history
- Debug packaging works with Bash 3.2; configuration parsing no longer uses Bash 4-only syntax
- Universal packaging preserves each architecture before SwiftPM can overwrite its shared product path
- Notarization submits a ZIP, requires Accepted, staples and validates the app, then rebuilds the distribution ZIP
- Install and release instructions distinguish macOS 14 right-click Open from macOS 15+ Privacy & Security > Open Anyway
- `build_app.sh` locates the SwiftPM binary via `--show-bin-path` with Products and triple-path fallbacks
- UndoManager registration uses `MainActor.assumeIsolated` for Swift 6.1 CI
- Signature store reload test avoids brittle `createdAt` equality after JSON round-trip
- CI installs SwiftLint/SwiftFormat into `.tools/` to avoid unzip LICENSE prompts
- Unit tests call `SignatureStore.saveProfile` (was stale `upsert` API)
- `AboutView` imports AppKit for `NSApp` / `NSImage`
- Security-scoped access when importing signature images and writing signed copies
- `Resources/Info.plist` minimum macOS version set to 14.2 (was 26.2)
- SwiftLint `file_header` rule disabled (sources use doc comments, not banner headers)

## [0.1.0] - 2026-10-28

First downloadable build. The app is unchanged from the 2026-09-29 modernization; this release makes it installable without Xcode.

### Added
- `PDFView-0.1.0-universal.zip` release asset, a universal binary for Apple silicon and Intel Macs, ad-hoc signed and not notarized
- README download path with the exact Gatekeeper first-launch steps
- `release.yml` workflow that builds, zips and attaches the app when a `v*` tag is pushed

### Changed
- README opens with one plain requirement line instead of a three-badge row
- `build_app.sh` and `Resources/Info.plist` default to version 0.1.0

## [1.0.0] - 2024-02-16

### Added
- Native macOS PDF reader built with SwiftUI and PDFKit
- Visual signature stamp placement and flattened export
- Local-only signature profile storage
- DocumentGroup-based app architecture for native macOS experience
- App Sandbox compliance for enhanced security
- Professional build script with code signing and notarization support
- Comprehensive test suite using Swift Testing framework
- PDF file association for default app integration

### Features
- PDF viewing via Apple PDFKit
- Visual signature workflow with draw/type/import options
- Free placement and signature field detection modes
- Undo/redo support for signature placements
- Signed copy export with flattened signatures
- Keyboard shortcuts for common operations
- Native menus and toolbar integration

### Security
- App Sandbox enabled with minimal required entitlements
- File access limited to user-selected files/folders
- Local-only signature storage (no cloud sync)
- Signed-copy export preserves document integrity

### Documentation
- Comprehensive README with build and usage instructions
- Architecture documentation for developers
- Security notes and best practices
- Distribution guides for various signing scenarios

---

## Release Notes Format

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Features removed in this version

### Fixed
- Bug fixes

### Security
- Security improvements and vulnerability fixes
