#!/bin/bash
# Run the native window regressions from a disposable build with its own entry point.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mtmr-customizer-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

for entry in MTMR MTMR.xcodeproj MTMRTests Resources Sparkle.framework; do
    ditto "$repo_dir/$entry" "$test_dir/$entry"
done
# Each fixture owns its @main and runs in a fresh process.
for fixture in "$repo_dir"/MTMRTests/*Integration.swift; do
    sed '/^@NSApplicationMain$/d' "$repo_dir/MTMR/AppDelegate.swift" > "$test_dir/MTMR/AppDelegate.swift"
    cat "$fixture" >> "$test_dir/MTMR/AppDelegate.swift"

    cd "$test_dir"
    xcodebuild build -project MTMR.xcodeproj -scheme MTMR -configuration Debug -quiet \
        -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath Build \
        DEVELOPMENT_TEAM="" CODE_SIGN_IDENTITY="" PRODUCT_BUNDLE_IDENTIFIER="local.MTMR.CustomizerTests"
    mkdir -p Presets
    Build/Build/Products/Debug/MTMR.app/Contents/MacOS/MTMR "$test_dir/Presets"
done
