#!/usr/bin/env bash
# Package PDFView SwiftPM macOS app into a .app bundle with PDF file association
set -euo pipefail

CONFIG="${1:-release}"

# Configuration
APP_NAME="PDFView"
BUNDLE_ID="com.bigmac.pdfview"
MACOS_MIN_VERSION="14.2"
ARCHES="${ARCHES:-$(uname -m)}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-false}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
ENTITLEMENTS="${ENTITLEMENTS:-Resources/PDFView.entitlements}"
INFO_PLIST_SOURCE="${INFO_PLIST_SOURCE:-Resources/Info.plist}"

products_configuration_name() {
    case "${1,,}" in
        release) echo "Release" ;;
        debug) echo "Debug" ;;
        *)
            echo "ERROR: Unsupported build configuration: $1" >&2
            exit 1
            ;;
    esac
}

# Resolve the built executable for a given architecture (SwiftPM layout varies by toolchain).
resolve_binary_path() {
    local arch="$1"
    local config="$2"
    local bin_dir=""
    local candidate=""

    if bin_dir="$(swift build --show-bin-path -c "$config" --arch "$arch" 2>/dev/null)"; then
        if [[ -f "$bin_dir/$APP_NAME" ]]; then
            echo "$bin_dir/$APP_NAME"
            return 0
        fi
        if [[ -f "$bin_dir" ]]; then
            echo "$bin_dir"
            return 0
        fi
    fi

    local products_config
    products_config="$(products_configuration_name "$config")"

    local fallback_paths=(
        ".build/out/Products/$products_config/$APP_NAME"
        ".build/${arch}-apple-macosx/${config}/$APP_NAME"
    )

    for candidate in "${fallback_paths[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "ERROR: Could not find $APP_NAME binary for arch=$arch config=$config" >&2
    echo "       Checked: swift build --show-bin-path and ${fallback_paths[*]}" >&2
    return 1
}

echo "==> Building $APP_NAME ($CONFIG) for: $ARCHES"

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "ERROR: Missing entitlements at $ENTITLEMENTS"
    exit 1
fi

# Build for each architecture with optimization
SWIFT_BUILD_FLAGS=()
if [[ "$CONFIG" == "release" ]]; then
    SWIFT_BUILD_FLAGS=(-Xswiftc -O -Xswiftc -whole-module-optimization)
fi

for arch in $ARCHES; do
    echo "==> swift build --arch $arch -c $CONFIG ${SWIFT_BUILD_FLAGS[*]:-}"
    swift build --arch "$arch" -c "$CONFIG" "${SWIFT_BUILD_FLAGS[@]}"
done

# Clean and create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Find and copy binary
read -r -a ARCH_ARRAY <<< "$ARCHES"
if [[ ${#ARCH_ARRAY[@]} -eq 1 ]]; then
    BINARY_PATH="$(resolve_binary_path "${ARCH_ARRAY[0]}" "$CONFIG")"
    echo "==> Using binary: $BINARY_PATH"
    cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
else
    LIPO_INPUTS=()
    for arch in $ARCHES; do
        arch_binary="$(resolve_binary_path "$arch" "$CONFIG")"
        echo "==> Using binary ($arch): $arch_binary"
        LIPO_INPUTS+=("$arch_binary")
    done
    echo "==> Creating universal binary"
    lipo -create "${LIPO_INPUTS[@]}" -output "$MACOS_DIR/$APP_NAME"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

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

# Info.plist: start from repo template when present, then patch build metadata.
if [[ -f "$INFO_PLIST_SOURCE" ]]; then
    cp "$INFO_PLIST_SOURCE" "$CONTENTS/Info.plist"
else
    echo "ERROR: Missing Info.plist template at $INFO_PLIST_SOURCE"
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MACOS_MIN_VERSION" "$CONTENTS/Info.plist"

if /usr/libexec/PlistBuddy -c "Print :BuildDate" "$CONTENTS/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :BuildDate $BUILD_DATE" "$CONTENTS/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Add :BuildDate string $BUILD_DATE" "$CONTENTS/Info.plist"
fi

if /usr/libexec/PlistBuddy -c "Print :GitCommit" "$CONTENTS/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :GitCommit $GIT_COMMIT" "$CONTENTS/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Add :GitCommit string $GIT_COMMIT" "$CONTENTS/Info.plist"
fi

# Clear extended attributes
xattr -cr "$APP_BUNDLE"

# Code signing (Developer ID or ad-hoc) without blanket --deep usage.
echo "==> Code signing ($SIGNING_IDENTITY)"

BASE_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    BASE_SIGN_ARGS+=(--timestamp --options runtime)
fi

sign_path() {
    local target="$1"
    local with_entitlements="${2:-false}"
    local args=("${BASE_SIGN_ARGS[@]}")
    if [[ "$with_entitlements" == "true" ]]; then
        args+=(--entitlements "$ENTITLEMENTS")
    fi
    codesign "${args[@]}" "$target"
}

# Sign nested code first if present.
if [[ -d "$FRAMEWORKS_DIR" ]]; then
    while IFS= read -r nested; do
        sign_path "$nested"
    done < <(find "$FRAMEWORKS_DIR" -type f \( -name "*.dylib" -o -perm -111 \) -print | sort)
fi

# Sandbox entitlements belong on the main executable.
if [[ -x "$MACOS_DIR/$APP_NAME" ]]; then
    sign_path "$MACOS_DIR/$APP_NAME" "true"
fi

sign_path "$APP_BUNDLE" "true"

if [[ "$NOTARIZE" == "true" ]]; then
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        echo "ERROR: NOTARIZE=true requires a valid Developer ID signing identity"
        exit 1
    fi
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "ERROR: NOTARY_PROFILE is required when NOTARIZE=true"
        exit 1
    fi
    echo "==> Submitting for notarization"
    xcrun notarytool submit "$APP_BUNDLE" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_BUNDLE"
fi

echo "==> Verifying signature integrity"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    spctl -a -vv --type execute "$APP_BUNDLE"
else
    echo "==> Skipping Gatekeeper assessment for ad-hoc signing"
fi

echo "==> Created: $APP_BUNDLE"
echo ""
echo "To set as default PDF app:"
echo "  1. Right-click any PDF > Get Info > Open with: PDFView > Change All"
echo "  2. Or run: duti -s $BUNDLE_ID com.adobe.pdf all"
echo ""
ls -la "$APP_BUNDLE"
