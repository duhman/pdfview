# Changelog

All notable changes to PDFView will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive CI/CD pipeline with GitHub Actions
- Code quality tools (SwiftLint, SwiftFormat)
- Developer documentation (CONTRIBUTING.md, ARCHITECTURE.md)
- Issue templates for bug reports and feature requests
- Security scanning in CI pipeline
- Code coverage reporting
- Enhanced error handling with detailed user messages
- Comprehensive validation for signature profiles
- Performance optimizations for large PDF documents
- Build script improvements with optimization flags

### Changed
- Updated Package.swift test target configuration for proper test discovery
- Updated macOS platform requirement from 26.2 to 14.2 for broader compatibility
- Updated Swift tools version from 6.2 to 6.0 for toolchain compatibility
- Enhanced SignatureStore with comprehensive error handling
- Improved API consistency across signature management
- Updated README with comprehensive feature documentation

### Fixed
- Tests can now be discovered and run with 'swift test'
- Resolved Swift version compatibility issues
- Fixed API inconsistencies in SignatureStore methods
- Enhanced error messages for better user experience
- Improved validation for corrupted signature data
- Build script platform version corrections

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