# Changelog

All notable changes to PDFView will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Initials and dates start in Anywhere even when the PDF has signature fields; only signatures start in Fields, and each kind remembers its Fields/Anywhere choice for the window
- Place Signature in Next Field is disabled, with the reason, while placing initials or a date
- A just-placed stamp leaves plain arrow keys to scrolling; click it or choose Select Next Stamp (⌥⌘]) to move it with the arrows
- The save and print progress banner appears only when the work takes longer than 300 ms
- Sign menu titles: Create Initials… / Edit Initials… follow whether initials exist; Select Next / Previous Stamp replace Select Next / Previous Signature

### Added
- Banner messages instead of beeps, also read by VoiceOver: a click outside every signature field in Fields mode, every field already filled, nothing left for Place Initials on Every Page, a stamp at the page edge or size limit, and a cancelled save or print ("Save cancelled.")
- Place Initials on Every Page shortcut (⌥⌘I), named in the signing banner while placing initials
- Command-arrows move a selected stamp 50 pt
- Go > Activate Form Field (⌥⌘↩), or Space / Return on the field just moved to: toggles checkboxes, selects radio buttons, offers pop-up and list choices, and starts editing text fields; field announcements include the state ("Agree, checkbox, checked, page 2")
- Help > Keyboard Shortcuts window generated from the menu chord table, listed before the online help
- VoiceOver announcements for Escape deselecting a stamp ("Stamp deselected.") and for the unlock sheet's title and instruction when it opens

### Fixed
- Cancelling initials setup while signing returns to the previous stamp kind and placement mode instead of leaving initials active without artwork

## [0.2.0] - 2026-10-30

A full native reader with offline visual signing: correct signed export, visible and editable stamps, initials and dates, password-protected copies, keyboard and VoiceOver support.

### Fixed
- Keep closing/quitting cancelled and the window edited when stamps or form values change during Save Signed Copy
- Capture initial form values before editing, including during incremental field discovery and immediately after unlock
- Return the exact form baseline captured with the exported snapshot and preserve stamp removals as unsaved work
- Render, serialize, repair geometry and validate independent export snapshots off the main actor, with cancellation and atomic replacement
- Explicitly disable unsigned document writing content types and include hidden/minimized document windows in quit review
- Cache date artwork per local day, locale and time zone; remove unused signature-storage errors

### Added
- Sign > Place Initials on Every Page: one undoable step at the selected or last initials' relative position, or the bottom-right margin; pages that already have initials are skipped and the count is announced
- Go > Next / Previous Form Field (⌥⌘→ / ⌥⌘←) reveals each form widget in reading order, announces its name, kind and page, and opens text fields for typing
- Delete Saved Initials… beside Delete Saved Signature…
- Place Signature (⌃⇧⌘S), Share Signed Copy… (⌥⇧⌘E) and Show Signed Copy in Finder (⇧⌘R) shortcuts, with a test that every menu chord is unique and avoids standard macOS chords
- VoiceOver announcements for Find results, the start of a save or print, and a wrong unlock password; the Sign toolbar menu reports Signing / Not signing
- Secure unlock on opening a locked PDF, File > Unlock… retry, and a locked-state banner after Cancel
- Sign menu and compact toolbar menu for Signature, Initials and Date; initials setup resumes pending placement
- Place Initials (⌥⇧⌘I), Place Date (⌥⇧⌘D), and Create/Edit Initials… commands
- Per-placement stamp kind, image and formatted date, including initials/date VoiceOver labels
- Form entries count as unsaved work: the close prompt names them, and a filled form can be saved without a stamp
- Quitting reviews every window with unsaved signatures or form entries (Review Changes / Discard Changes / Cancel)
- File > Share Signed Copy… and Show Signed Copy in Finder for the window's last saved copy
- Sign > Place Signature in Next Field (⌥⌘N), Place Signature on Current Page (⌥⌘P), Select Next / Previous Signature (⌥⌘] / ⌥⌘[)
- Option-Shift-arrow aspect-locked keyboard resizing for a selected stamp
- VoiceOver elements for placed stamps (signer, page, field or position) with Remove and Move actions, plus position announcements after placing and moving
- Stop Signing context menu while signing; Go to Page explains invalid input inline
- Document-scoped, memory-only password state, secure unlock sheet and save protection accessory
- Protected signed export with default-on password retention, explicit opt-out and unknown-password notice in Save Signed Copy
- Incremental, cancellable signature-field scanning shared by field placement and editable-form discovery
- Independent signature and initials profiles with legacy JSON migration and initials setup entry point
- Transparent locale-aware date stamps rendered at placement time
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
- Initials and date stamps start at 60 and 110 pt wide (signatures 180 pt), and the last resize of each kind becomes its size for the session
- The stamp kind returns to Signature after each placement or Stop Signing; menu titles name the kind they will place
- Place in Next Field skips fields that already hold a stamp and beeps and announces when none are left
- Date stamps use the system font at medium weight instead of a script face
- Save Signed Copy… and Unlock… moved to the File menu
- Undo names, the stamp context menu and VoiceOver actions say Signature, Initials or Date; the print banner says “Preparing to print…”
- Locked PDFs unlock only through the password sheet (PDFKit's own password field no longer appears); the print caption is hidden while the locked banner shows
- The document takes keyboard focus when a window opens and after unlocking; the unlock sheet focuses its password field
- A selected stamp no longer takes Option-arrows (formerly a 50 pt move), so Option-Up/Down keep turning pages; Escape deselects the stamp, then closes the saved banner
- Overlay outlines and handles thicken and darken with Increase Contrast; message text is at least 12 pt
- Save Signed Copy configures protection and original-file safety before opening the save panel
- Protected signed printing unlocks its temporary copy in memory and cleans it after use
- One signature-field scan preserves field names and restarts safely on unlock or document replacement
- Signature fields and form widgets are scanned a few pages at a time after the pages appear; page overlays redraw only when their inputs change
- The saved banner stays until closed and names the folder; the signing banner names the keyboard path
- Escape closes Find first when the Find field has focus; leaving signing is announced and focus returns to the document
- Placing before a signature exists runs the placement after setup; Place on Current Page scrolls to the stamp
- Menu names: Create Signature… (when none exists), Delete Saved Signature…, Remove Signature/Initials/Date from Page
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
- Duplicate synchronous signature-field scan and unused profile-kind identity property
- Unused original PDF bytes, signature-store lookup wrappers and signing-mode convenience property
- Redundant StrictConcurrency upcoming-feature flags in the Swift 6 package
- GitHub Actions workflows (`ci.yml`, `quality.yml`, `release.yml`); checks and releases run locally

### Fixed
- Signature-field outlines with a yellow accent measured 2.8:1 against the page; they now reach 3.7:1 (5.7:1 with Increase Contrast)
- Long date stamps in the system font could overflow the stamp after one fit pass
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
- Signature-field outlines with a yellow accent measured 2.8:1 against the page; they now reach 3.7:1 (5.7:1 with Increase Contrast)
- Long date stamps in the system font could overflow the stamp after one fit pass
- Bug fixes

### Security
- Security improvements and vulnerability fixes
