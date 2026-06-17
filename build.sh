#!/bin/bash
set -e

export PATH="/usr/local/go/bin:/usr/local/flutter/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
GO_SRC="$ROOT/src/huginn-messenger"

echo "=== 1. Building Go shared library (host) ==="
cd "$GO_SRC"
go build -buildmode=c-shared -o libhuginn_messenger.so .
echo "   -> src/libhuginn_messenger.so"

echo ""
echo "=== 2. Building Go shared library for Android ==="
SDK_DIR="${ANDROID_HOME:-/home/killbane/Android/Sdk}"
NDK_DIR="$(ls -d "$SDK_DIR/ndk/"*.*.*/ 2>/dev/null | sort -V | tail -1)"
if [ -z "$NDK_DIR" ]; then
  echo "  ERROR: Android NDK not found in $SDK_DIR/ndk/"
  exit 1
fi
NDK_BIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
API_LEVEL=24

build_android_abi() {
  local GOARCH="$1"
  local ABI="$2"
  local CC_TRIPLE="$3"
  local GOARM="${4:-}"

  echo "  Building for $ABI (GOARCH=$GOARCH)..."
  (
    cd "$GO_SRC"
    export GOOS=android
    export GOARCH="$GOARCH"
    export CGO_ENABLED=1
    export CC="$NDK_BIN/${CC_TRIPLE}${API_LEVEL}-clang"
    export PATH="$NDK_BIN:$PATH"
    if [ -n "$GOARM" ]; then
      export GOARM="$GOARM"
    fi
    OUTDIR="$GO_SRC/android/$ABI"
    mkdir -p "$OUTDIR"
    go build -buildmode=c-shared -o "$OUTDIR/libhuginn_messenger.so" .
    echo "     -> android/$ABI/libhuginn_messenger.so"
  )
}

build_android_abi arm64      arm64-v8a  aarch64-linux-android
build_android_abi arm        armeabi-v7a armv7a-linux-androideabi 7
build_android_abi amd64      x86_64     x86_64-linux-android
build_android_abi 386        x86        i686-linux-android

echo ""
  echo "  Copying to jniLibs..."
JNIDIR="$ROOT/android/app/src/main/jniLibs"
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  mkdir -p "$JNIDIR/$abi"
  cp "$GO_SRC/android/$abi/libhuginn_messenger.so" "$JNIDIR/$abi/"
  echo "     -> jniLibs/$abi/libhuginn_messenger.so"
done

echo ""
echo "=== 3. Building Flutter Android APK ==="
cd "$ROOT"
flutter build apk --release

echo ""
echo "=== 4. Building Flutter Linux app ==="
cd "$ROOT"
flutter build linux --release

echo ""
echo "=== Done! ==="
echo "Android libraries: src/android/{arm64-v8a,armeabi-v7a,x86_64,x86}/"
echo "Android APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Linux bundle: build/linux/x64/release/bundle/"
