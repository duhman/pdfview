# Contributing to PDFView

Thank you for your interest in contributing to PDFView! This document provides guidelines and information for contributors.

## 🚀 Quick Start

### Prerequisites

- **macOS 14.2+** (for building and running)
- **Xcode 15.0+** with Command Line Tools
- **Swift 6.0+** 
- **Git** for version control

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/pdfview.git
cd pdfview

# Build and run tests
swift build
swift test

# Build the app bundle for testing
./build_app.sh debug
```

## 🏗️ Project Architecture

### Core Components

```
Sources/
├── PDFViewApp/              # Application logic
│   ├── PDFViewApp.swift     # Main app entry point
│   ├── PDFViewerDocument.swift  # PDF document model
│   ├── SignatureProfile.swift  # Signature data models
│   ├── SignatureStore.swift    # Signature persistence
│   ├── SigningCommands.swift   # Menu commands
│   ├── SigningFlowLogic.swift  # Signing workflow
│   └── SigningMode.swift       # Signing state management
└── Views/                   # SwiftUI views
    ├── PDFContentView.swift     # Main content view
    ├── PDFKitView.swift         # PDFKit bridge
    └── SignatureSetupSheet.swift   # Signature setup UI
```

### Design Patterns

- **DocumentGroup/FileDocument**: Native macOS document architecture
- **MVVM**: SwiftUI reactive patterns with `@StateObject` and `@ObservableObject`
- **Command Pattern**: Menu commands with `FocusedValue` binding
- **Repository Pattern**: `SignatureStore` for data persistence
- **State Machine**: `SigningMode` enum for workflow states

### Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **PDFKit**: Apple's PDF rendering and manipulation framework
- **App Sandbox**: Security containment for distribution
- **Swift Concurrency**: `@preconcurrency` imports for thread safety

## 🔧 Development Workflow

### Code Quality Standards

We maintain high code quality through automated tools and manual review:

#### Automated Checks
- **SwiftLint**: Style and convention enforcement
- **SwiftFormat**: Consistent code formatting
- **Swift Compiler**: Strict concurrency checking
- **Unit Tests**: Comprehensive test coverage

#### Manual Review
- **Architecture consistency**: Follow established patterns
- **Performance considerations**: Efficient PDF handling
- **Security best practices**: Sandbox compliance
- **Accessibility**: VoiceOver and keyboard navigation

### Making Changes

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

3. **Run quality checks**:
   ```bash
   # Format code
   swiftformat .
   
   # Lint code
   swiftlint
   
   # Build and test
   swift build --configuration release
   swift test
   
   # Test app bundle creation
   ./build_app.sh debug
   ```

4. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat: add signature field auto-detection
   
   - Implement PDF form field scanning
   - Add visual indicators for detected fields
   - Update tests for new functionality"
   ```

5. **Push and create Pull Request**:
   ```bash
   git push origin feature/your-feature-name
   ```

### Commit Message Convention

We follow [Conventional Commits](https://conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring without feature changes
- `test:` Adding or updating tests
- `chore:` Build system, dependencies, etc.

## 🧪 Testing Guidelines

### Test Structure

```
Tests/
└── PDFViewAppTests/
    ├── PDFViewerDocumentTests.swift   # Document model tests
    ├── SignatureStoreTests.swift      # Storage tests
    └── SigningFlowLogicTests.swift    # Workflow tests
```

### Testing Principles

- **Unit tests**: Test individual components in isolation
- **Integration tests**: Test component interactions
- **UI tests**: Test user workflows (manual testing for now)
- **Performance tests**: Critical PDF operations

### Writing Tests

```swift
import Testing
@testable import PDFViewApp

@Test func documentSignaturePlacementRoundTrip() {
    var document = PDFViewerDocument()
    let placement = PDFViewerDocument.SignaturePlacement(
        pageIndex: 0,
        bounds: CGRect(x: 20, y: 30, width: 120, height: 40),
        signaturePNGData: makeTestSignatureData(),
        signerName: "Test User"
    )
    
    document.addSignaturePlacement(placement)
    #expect(document.signaturePlacements.count == 1)
    
    let removed = document.removeSignaturePlacement(id: placement.id)
    #expect(removed == placement)
    #expect(document.signaturePlacements.isEmpty)
}
```

## 📋 Issue Guidelines

### Bug Reports

When reporting bugs, please include:

- **Environment**: macOS version, Xcode version
- **Steps to reproduce**: Clear, minimal reproduction steps
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Sample files**: PDF files that demonstrate the issue (if applicable)

### Feature Requests

For new features:

- **Problem description**: What problem does this solve?
- **Proposed solution**: How should it work?
- **Alternatives considered**: Other approaches you've thought about
- **Implementation ideas**: Technical thoughts (optional)

## 🔒 Security Considerations

### App Sandbox Compliance

PDFView runs in App Sandbox for security:

- Only access user-selected files
- No network access unless explicitly needed
- Use security-scoped bookmarks for persistent access
- Follow principle of least privilege

### Code Security

- No hardcoded secrets or tokens
- Validate all user inputs (especially PDF data)
- Use safe Swift patterns (avoid force unwrapping)
- Handle errors gracefully without exposing internals

### Privacy

- No telemetry or analytics collection
- Local-only signature storage
- No cloud sync or remote services
- Transparent data handling

## 🚀 Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):
- `MAJOR.MINOR.PATCH` format
- Major: Breaking changes
- Minor: New features (backward compatible)
- Patch: Bug fixes

### Distribution

1. **Development builds**: Ad-hoc signed for local testing
2. **Beta releases**: Developer ID signed, limited distribution
3. **Production releases**: Developer ID + notarized for public distribution

### Checklist

Before releasing:

- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version bumped in appropriate files
- [ ] App bundle builds and signs correctly
- [ ] Manual testing on clean macOS installation

## 🤝 Code of Conduct

### Our Standards

- **Be respectful**: Treat all contributors with respect
- **Be inclusive**: Welcome people of all backgrounds
- **Be collaborative**: Work together constructively
- **Be helpful**: Share knowledge and assist others

### Enforcement

Report issues to project maintainers. All complaints will be reviewed and investigated promptly and fairly.

## 📞 Getting Help

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Code Review**: Submit PRs for feedback and collaboration

## 📚 Resources

### Apple Documentation
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [PDFKit](https://developer.apple.com/documentation/pdfkit)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Code Signing](https://developer.apple.com/documentation/security/code_signing_services)

### Swift Resources
- [Swift.org](https://swift.org/)
- [Swift Evolution](https://github.com/apple/swift-evolution)
- [Swift Package Manager](https://github.com/apple/swift-package-manager)

---

Thank you for contributing to PDFView! 🎉