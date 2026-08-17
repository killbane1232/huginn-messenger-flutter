#!/bin/bash
set -e

export PATH="/usr/local/flutter/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "=== 1. Downloading prebuilt Huginn core libraries ==="
cd "$ROOT"
scripts/download-core-libraries.sh

echo ""
echo "=== 2. Building Flutter Android APK ==="
cd "$ROOT"
flutter build apk --release

echo ""
echo "=== 3. Building Flutter Linux app ==="
cd "$ROOT"
flutter build linux --release

echo ""
echo "=== Done! ==="
echo "Core version: $(tr -d '[:space:]' < core-library.version)"
echo "Android APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Linux bundle: build/linux/x64/release/bundle/"
