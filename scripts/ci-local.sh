#!/bin/bash
# Run every pre-push check on this Mac. PDFView has no hosted CI.
# Usage: /bin/bash scripts/ci-local.sh   (from the repo root)
set -euo pipefail

SWIFTLINT_VERSION="0.65.1"
SWIFTFORMAT_VERSION="0.64.4"

failures=()
step() {
    local name="$1"
    shift
    echo "==> $name"
    if "$@"; then
        echo "    ok: $name"
    else
        echo "    FAILED: $name"
        failures+=("$name")
    fi
}

check_tool_version() {
    local tool="$1" expected="$2" actual
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "    $tool not installed (expected $expected)"
        return 1
    fi
    actual="$("$tool" --version 2>/dev/null | tail -1)"
    if [[ "$actual" != *"$expected"* ]]; then
        echo "    $tool is $actual, CI pins $expected"
        return 1
    fi
}

verify_bundle() {
    test -x PDFView.app/Contents/MacOS/PDFView
    test -s PDFView.app/Contents/Resources/AppIcon.icns
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' PDFView.app/Contents/Info.plist)" = AppIcon
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' PDFView.app/Contents/Info.plist)" = 14.2
    codesign --verify --strict PDFView.app
}

verify_docs() {
    grep -q "## Install" README.md
    grep -q "## Development" README.md
    grep -q "duhman/pdfview" README.md
    test -f Resources/PDFView.entitlements
    test -s Resources/AppIcon.icns
    test -f scripts/make-icon.swift
}

swift --version
step "Build debug app (stock Bash)" /bin/bash ./build_app.sh debug
step "Test" swift test --parallel
step "Build release app (stock Bash)" /bin/bash ./build_app.sh release
step "Verify app bundle" verify_bundle
step "SwiftLint $SWIFTLINT_VERSION" check_tool_version swiftlint "$SWIFTLINT_VERSION"
step "SwiftLint (strict)" swiftlint lint --strict --quiet Sources Tests scripts
step "SwiftFormat $SWIFTFORMAT_VERSION" check_tool_version swiftformat "$SWIFTFORMAT_VERSION"
step "SwiftFormat (lint)" swiftformat Sources Tests scripts --lint
step "Documentation and resources" verify_docs

rm -rf PDFView.app
echo
if ((${#failures[@]})); then
    echo "Local CI FAILED: ${failures[*]}"
    exit 1
fi
echo "Local CI passed."
