#!/usr/bin/env bash
# Package PDFView SwiftPM macOS app into a .app bundle with PDF file association
set -euo pipefail

CONFIG="${1:-release}"

# Configuration
APP_NAME="PDFView"
BUNDLE_ID="com.bigmac.pdfview"
MACOS_MIN_VERSION="15.0"
ARCHES="$(uname -m)"
VERSION="1.0.0"
BUILD_NUMBER="1"

APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"

echo "==> Building $APP_NAME ($CONFIG) for: $ARCHES"

# Build for each architecture
for arch in $ARCHES; do
    echo "==> swift build --arch $arch -c $CONFIG"
    swift build --arch "$arch" -c "$CONFIG"
done

# Clean and create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Find and copy binary
ARCH_ARRAY=($ARCHES)
if [[ ${#ARCH_ARRAY[@]} -eq 1 ]]; then
    BINARY_PATH=".build/${ARCH_ARRAY[0]}-apple-macosx/$CONFIG/$APP_NAME"
    cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
else
    LIPO_INPUTS=()
    for arch in $ARCHES; do
        LIPO_INPUTS+=(".build/${arch}-apple-macosx/$CONFIG/$APP_NAME")
    done
    echo "==> Creating universal binary"
    lipo -create "${LIPO_INPUTS[@]}" -output "$MACOS_DIR/$APP_NAME"
fi

# Verify architecture
echo "==> Binary architectures:"
lipo -info "$MACOS_DIR/$APP_NAME"

# Copy resources if they exist
if [[ -d "Sources/$APP_NAME/Resources" ]]; then
    cp -R "Sources/$APP_NAME/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Get git commit for build metadata
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Generate Info.plist with PDF file association
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MACOS_MIN_VERSION</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>BuildMachineOSBuild</key>
    <string>$(sw_vers -buildVersion)</string>
    <key>GitCommit</key>
    <string>$GIT_COMMIT</string>
    <key>BuildDate</key>
    <string>$BUILD_DATE</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Create default entitlements for local use
ENTITLEMENTS=$(mktemp)
cat > "$ENTITLEMENTS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

# Clear extended attributes
xattr -cr "$APP_BUNDLE"

# Ad-hoc code signing for local use
echo "==> Ad-hoc signing"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "==> Created: $APP_BUNDLE"
echo ""
echo "To set as default PDF app:"
echo "  1. Open System Settings > Desktop & Dock > Default web browser (for documents)"
echo "  2. Or right-click any PDF > Get Info > Open with: PDFView > Change All"
echo ""
ls -la "$APP_BUNDLE"
