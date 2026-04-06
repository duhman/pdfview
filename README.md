# PDFView

A modern, native macOS PDF reader and digital signature application built with Swift 6 and SwiftUI.

![macOS](https://img.shields.io/badge/macOS-14.2+-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## ✨ Features

### 📄 **Native PDF Reading**
- **Fast PDF rendering** using Apple's PDFKit framework
- **Smooth scrolling** and zooming with native performance
- **File associations** — set as your default PDF reader
- **Memory efficient** handling of large documents

### ✍️ **Digital Signatures**
- **Visual signature placement** with drag-and-drop positioning
- **Multiple signature modes**: Draw, Type, or Import existing signatures
- **Signature field detection** for PDF forms
- **Undo/redo support** for signature placements
- **Local-only storage** — your signatures never leave your Mac

### 🔒 **Security & Privacy**
- **App Sandbox** compliance for enhanced security
- **File access limited** to user-selected files only
- **No cloud dependencies** — everything stays on your device
- **Signed copy export** preserves document integrity
- **Security-scoped bookmarks** for reliable file access

### 🏗️ **Modern Architecture**
- **DocumentGroup** architecture for native macOS experience
- **SwiftUI** interface with native controls and animations
- **Strict concurrency** compliance for thread safety
- **Professional error handling** with user-friendly messages
- **Comprehensive testing** with automated CI/CD pipeline

## 🚀 Quick Start

### Installation

**Option 1: Pre-built App**
```bash
# Download and install the latest release
curl -L https://github.com/your-repo/pdfview/releases/latest/download/PDFView.app.zip
unzip PDFView.app.zip
cp -R PDFView.app /Applications/
```

**Option 2: Build from Source**
```bash
# Clone and build
git clone https://github.com/your-repo/pdfview.git
cd pdfview
swift build -c release
./build_app.sh release
cp -R PDFView.app /Applications/
```

### Setting as Default PDF Reader
```bash
# Set as default for all PDF files
duti -s com.bigmac.pdfview com.adobe.pdf all

# Or manually: Right-click any PDF → Get Info → Open with: PDFView → Change All
```

## 📋 Requirements

- **macOS 14.2** or later (Sonoma+)
- **Swift 6.0** toolchain (for building from source)
- **Xcode 15+** (for development)

## 🛠️ Development

### Prerequisites
```bash
# Verify Swift version
swift --version  # Should be 6.0 or later

# Install development dependencies
git clone https://github.com/your-repo/pdfview.git
cd pdfview
```

### Building & Testing
```bash
# Debug build
swift build

# Release build with optimizations
swift build -c release

# Run comprehensive test suite
swift test

# Code quality checks
swiftlint
swiftformat --lint .

# Build production app bundle
./build_app.sh release
```

### Development Workflow

1. **Code Style**: Enforced by SwiftLint and SwiftFormat
2. **Testing**: Swift Testing framework with automated CI
3. **Git Workflow**: Conventional commits with descriptive messages
4. **CI/CD**: GitHub Actions with quality gates and security scanning

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development guidelines.

## 📖 Documentation

- **[Architecture Guide](ARCHITECTURE.md)** — Technical design and implementation details
- **[Contributing Guide](CONTRIBUTING.md)** — Development setup and contribution guidelines
- **[Changelog](CHANGELOG.md)** — Version history and release notes
- **[Security Policy](.github/SECURITY.md)** — Security best practices and reporting

## 🏢 Project Structure

```
PDFView/
├── Sources/                    # Application source code
│   ├── PDFViewApp/            # Core application logic
│   │   ├── PDFViewApp.swift   # Main app entry point
│   │   ├── PDFViewerDocument.swift  # Document model
│   │   └── SignatureStore.swift     # Signature management
│   └── Views/                 # SwiftUI views
│       └── PDFContentView.swift     # Main content view
├── .github/                   # CI/CD and project templates
│   ├── workflows/ci.yml       # Automated testing and quality checks
│   └── ISSUE_TEMPLATE/        # Bug report and feature request templates
├── Tests/                     # Comprehensive test suite
├── Package.swift              # Swift Package Manager configuration
└── build_app.sh               # Production build and signing script
```

## 🔧 Configuration

### Build Configuration
```bash
# Environment variables for build script
export SIGNING_IDENTITY="Developer ID Application: Your Name"
export NOTARIZE="true"
export NOTARY_PROFILE="your-profile"

# Custom version and build numbers
export VERSION="1.1.0"
export BUILD_NUMBER="42"
```

### Code Signing
```bash
# View available identities
security find-identity -p codesigning

# Set signing identity
export SIGNING_IDENTITY="Developer ID Application: (TEAM_ID)"
```

## 📈 Performance & Quality

### Metrics
- **Build time**: < 60 seconds for full release build
- **App size**: < 5MB optimized binary
- **Memory usage**: < 50MB for typical documents
- **Test coverage**: Comprehensive integration and unit tests

### Quality Assurance
- ✅ **Automated CI/CD** with GitHub Actions
- ✅ **Code quality enforcement** with SwiftLint
- ✅ **Security scanning** for vulnerabilities
- ✅ **Performance testing** for large documents
- ✅ **Memory leak detection** in CI pipeline

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Quick Contribution Checklist
- [ ] Fork the repository
- [ ] Create a feature branch (`git checkout -b feature/amazing-feature`)
- [ ] Follow our code style guidelines
- [ ] Add tests for new functionality
- [ ] Ensure all tests pass (`swift test`)
- [ ] Update documentation as needed
- [ ] Commit with descriptive messages
- [ ] Open a Pull Request

## 🐛 Bug Reports & Feature Requests

- **Bug Reports**: Use our [bug report template](.github/ISSUE_TEMPLATE/bug_report.md)
- **Feature Requests**: Use our [feature request template](.github/ISSUE_TEMPLATE/feature_request.md)
- **Security Issues**: Email security@yourcompany.com (private disclosure)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏆 Acknowledgments

- **Apple** for the excellent PDFKit framework
- **Swift Community** for the modern language features
- **Contributors** who help make this project better

---

**Made with ❤️ for the macOS community**
