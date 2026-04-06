# PDFView Architecture

This document describes the technical architecture, design decisions, and implementation details of PDFView.

## 🏗️ Overview

PDFView is a native macOS PDF reader with visual signature capabilities, built using SwiftUI and PDFKit. The architecture emphasizes security, performance, and maintainability.

## 🎯 Design Goals

### Primary Goals
- **Security**: App Sandbox compliance, secure PDF handling
- **Performance**: Efficient PDF rendering, memory management
- **Usability**: Native macOS experience, intuitive workflow
- **Reliability**: Robust error handling, data integrity

### Non-Goals
- Cross-platform support (macOS-only)
- Cloud sync or remote services
- Certificate-based digital signatures
- Advanced PDF editing beyond signing

## 📁 Architecture Layers

### 1. Application Layer (`Sources/PDFViewApp/`)

#### `PDFViewApp.swift`
Main application entry point using `DocumentGroup` for native document-based app architecture.

```swift
@main
struct PDFViewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: PDFViewerDocument.self) { file in
            PDFContentView(document: file.$document)
        }
    }
}
```

**Key Features:**
- Native document handling with recent documents support
- Window management and restoration
- Menu system with keyboard shortcuts

#### `PDFViewerDocument.swift`
Core document model conforming to `FileDocument` protocol.

```swift
struct PDFViewerDocument: FileDocument {
    var pdfDocument: PDFDocument?
    private var originalPDFData: Data?
    var signaturePlacements: [SignaturePlacement] = []
}
```

**Responsibilities:**
- PDF loading and validation
- Signature placement tracking
- Signed copy export with flattening
- Immutable baseline preservation

### 2. View Layer (`Sources/Views/`)

#### `PDFContentView.swift`
Main SwiftUI content view coordinating the entire user interface.

**State Management:**
- `@StateObject` for signature store and undo controller
- `@State` for UI state (zoom, signing mode, alerts)
- `@Environment` for system services (undo manager)

#### `PDFKitView.swift`
UIViewRepresentable bridge connecting SwiftUI to PDFKit.

```swift
struct PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        // Configuration...
        return pdfView
    }
}
```

**Responsibilities:**
- PDF rendering and display
- User interaction handling (clicks, gestures)
- Coordinate system translation
- Performance optimization

#### `SignatureSetupSheet.swift`
Modal sheet for signature profile creation and editing.

**Features:**
- Drawing canvas for signature creation
- Text-based signature generation
- Image import functionality
- Profile management

### 3. Business Logic Layer

#### `SigningFlowLogic.swift`
Core signing workflow orchestration.

```swift
class SigningFlowLogic: ObservableObject {
    @Published var signingMode: SigningMode = .idle
    @Published var hasSignatureFields = false
    
    func startSigning() { /* ... */ }
    func placeSignature(at point: CGPoint) { /* ... */ }
}
```

**State Machine:**
- `idle`: Normal viewing mode
- `selectingProfile`: Choosing signature profile
- `placingSignatures`: Active signing mode
- `reviewingPlacements`: Final review before export

#### `SignatureStore.swift`
Signature profile persistence and management.

**Security Features:**
- Local-only storage in app container
- Secure data encoding
- No keychain storage (user preference)

#### `SigningCommands.swift`
FocusedValue-based command system for menu integration.

### 4. Data Models

#### `SignatureProfile.swift`
```swift
struct SignatureProfile: Codable {
    let id: UUID
    var name: String
    var pngData: Data
    let createdDate: Date
    var lastUsedDate: Date
}
```

#### `SigningMode.swift`
```swift
enum SigningMode {
    case idle
    case selectingProfile
    case placingSignatures(profile: SignatureProfile)
    case reviewingPlacements
}
```

## 🔄 Data Flow

### PDF Loading Flow
1. User selects PDF via DocumentGroup
2. `PDFViewerDocument.init(configuration:)` loads file
3. Original data preserved for export integrity
4. PDFKit document created for display

### Signature Placement Flow
1. User initiates signing via toolbar/menu
2. `SigningFlowLogic` transitions to signing mode
3. Profile selection or creation via `SignatureSetupSheet`
4. Click handling in `PDFKitView` captures placement coordinates
5. `SignaturePlacement` added to document model
6. Visual feedback updated in real-time

### Export Flow
1. User triggers "Save Signed Copy"
2. `PDFViewerDocument.writeSignedCopy()` called
3. Original PDF used as baseline
4. Signature placements rendered via CoreGraphics
5. Flattened PDF written to user-selected location

## 🔧 Technical Decisions

### SwiftUI + PDFKit Integration

**Decision**: Use `NSViewRepresentable` to bridge PDFKit into SwiftUI rather than pure SwiftUI PDF rendering.

**Rationale**:
- PDFKit provides mature PDF rendering optimizations
- Hardware-accelerated display
- Built-in zoom, scroll, selection handling
- Apple's recommended approach for PDF apps

**Trade-offs**:
- More complex coordinate system handling
- Imperative updates in reactive environment
- Platform-specific code

### Document Architecture

**Decision**: Use `FileDocument` with `DocumentGroup` rather than custom document handling.

**Rationale**:
- Native macOS document app experience
- Automatic recent documents, window restoration
- System integration (Versions, Auto Save)
- Reduced boilerplate code

**Trade-offs**:
- Less control over document lifecycle
- SwiftUI-specific (not AppKit compatible)

### Signature Storage

**Decision**: Local-only storage in app container rather than keychain or cloud sync.

**Rationale**:
- Simplified privacy model
- No network dependencies
- User control over data location
- App Sandbox compliance

**Trade-offs**:
- No cross-device sync
- Data lost on app deletion
- No enterprise management

### Export Strategy

**Decision**: Flatten signatures into immutable PDF rather than PDF form fields or annotations.

**Rationale**:
- Guaranteed compatibility across PDF viewers
- Cannot be accidentally removed or modified
- Simpler implementation
- Clear visual signature intent

**Trade-offs**:
- Cannot remove signatures after export
- Larger file sizes
- No metadata preservation for signatures

## 🔒 Security Architecture

### App Sandbox

PDFView runs in App Sandbox with minimal entitlements:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Implications**:
- Only user-selected files accessible
- No network access
- No arbitrary file system access
- Enhanced security posture

### Memory Safety

- Swift's memory safety eliminates buffer overflows
- PDF data validation on load
- Bounds checking for signature placement
- Error handling prevents crashes

### Input Validation

```swift
// Example: PDF data validation
guard let document = PDFDocument(data: data) else {
    throw CocoaError(.fileReadCorruptFile)
}

// Coordinate clamping for signature placement
let clampedRect = CGRect(
    x: max(mediaBox.minX, min(placement.bounds.origin.x, mediaBox.maxX)),
    y: max(mediaBox.minY, min(placement.bounds.origin.y, mediaBox.maxY)),
    width: min(placement.bounds.width, mediaBox.width),
    height: min(placement.bounds.height, mediaBox.height)
)
```

## ⚡ Performance Considerations

### PDF Rendering

- PDFKit handles rendering optimization automatically
- Page-based rendering for large documents
- Memory pressure handling via system
- Hardware acceleration where available

### Memory Management

- Weak references in delegates and coordinators
- Immediate release of large data structures
- Signature image compression for storage
- Original PDF data preserved efficiently

### Threading

- UI updates on main queue via `@MainActor`
- PDF operations on background queues where possible
- Swift Concurrency for async operations
- `@preconcurrency` imports for legacy APIs

## 🧪 Testing Strategy

### Unit Tests

Focus on business logic and data models:
- Document signature placement/removal
- Export functionality
- Signature store operations
- Error handling paths

### Integration Tests

Test component interactions:
- PDF loading and validation
- Signature workflow end-to-end
- File system operations

### Manual Testing

UI and user experience validation:
- Signature placement accuracy
- Export quality verification
- Performance with large PDFs
- Accessibility compliance

## 🚀 Build and Distribution

### Build Process

1. **Swift Package Manager**: Dependency management and building
2. **build_app.sh**: App bundle creation with proper Info.plist
3. **Code Signing**: Developer ID or ad-hoc signing
4. **Notarization**: Apple notary service for distribution

### Distribution Channels

- **Development**: Ad-hoc signed for local testing
- **Beta**: Developer ID signed, TestFlight alternative
- **Production**: Developer ID + notarized for public release

## 🔮 Future Considerations

### Scalability

- Plugin architecture for extended functionality
- Document format support beyond PDF
- Advanced signing features (timestamps, certificates)

### Performance

- Lazy loading for large documents
- Signature caching and optimization
- Memory usage profiling and optimization

### Features

- Batch signing workflows
- Form field auto-detection
- Accessibility improvements
- Localization support

---

This architecture provides a solid foundation for a secure, performant, and maintainable PDF signing application while leaving room for future enhancements.