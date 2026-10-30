# Changelog

All notable changes to PDFView will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Procedurally drawn macOS app icon, bundled with PDFView, and a Swift regeneration script
- Restored `PDFViewAppTests` Swift Testing target in `Package.swift`
- Committed `Resources/PDFView.entitlements` sandbox template
- `.github/SECURITY.md` vulnerability reporting policy

### Changed
- README positions PDFView as a full native reader with offline visual signing and labels the feature list as the release target
- CI and release share pinned SwiftLint 0.65.1 and SwiftFormat 0.64.4 gates that check the untouched checkout
- CI builds debug and release app bundles with stock macOS `/bin/bash`; release packaging uses the same script for universal builds
- Architecture and contributor documentation describe the release target and reproducible local commands
- README and CONTRIBUTING now use the real repository URL and accurate CI/test claims
- CI uses Xcode on `macos-15` (no overlapping Swift toolchain install)
- `build_app.sh` uses `Resources/Info.plist`, patches metadata, signs the executable with entitlements
- ARCHITECTURE.md aligned with current signing modes and test layout

### Fixed
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