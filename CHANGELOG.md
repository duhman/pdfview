# Changelog

All notable changes to PDFView will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Restored `PDFViewAppTests` Swift Testing target in `Package.swift`
- Committed `Resources/PDFView.entitlements` sandbox template
- `.github/SECURITY.md` vulnerability reporting policy

### Changed
- README and CONTRIBUTING now use the real repository URL and accurate CI/test claims
- CI uses Xcode on `macos-15` (no overlapping Swift toolchain install)
- `build_app.sh` uses `Resources/Info.plist`, patches metadata, signs the executable with entitlements
- ARCHITECTURE.md aligned with current signing modes and test layout

### Fixed
- UndoManager registration uses `MainActor.assumeIsolated` for Swift 6.1 CI
- Signature store reload test avoids brittle `createdAt` equality after JSON round-trip
- CI installs SwiftLint/SwiftFormat into `.tools/` to avoid unzip LICENSE prompts
- Unit tests call `SignatureStore.saveProfile` (was stale `upsert` API)
- `AboutView` imports AppKit for `NSApp` / `NSImage`
- Security-scoped access when importing signature images and writing signed copies
- `Resources/Info.plist` minimum macOS version set to 14.2 (was 26.2)
- SwiftLint `file_header` rule disabled (sources use doc comments, not banner headers)

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