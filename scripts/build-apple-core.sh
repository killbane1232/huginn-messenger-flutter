#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
core_dir="$root_dir/src/huginn-messenger"
target="${1:-all}"
case "$target" in
  all|macos|ios) ;;
  *) echo "Usage: $0 [all|macos|ios]" >&2; exit 1 ;;
esac
[[ "$(uname -s)" == Darwin ]] || { echo "Apple builds require macOS." >&2; exit 1; }
go_bin="${GO_BIN:-$(command -v go || true)}"
[[ -x "$go_bin" ]] || { echo "Go is required; set GO_BIN if it is not on PATH." >&2; exit 1; }
if [[ "$target" != macos ]]; then
  xcodebuild -version >/dev/null
  xcrun --sdk iphoneos --show-sdk-path >/dev/null
  xcrun --sdk iphonesimulator --show-sdk-path >/dev/null
fi
if [[ -e "$core_dir/.git" ]] && [[ -n "$(git -C "$core_dir" status --porcelain)" ]]; then
  echo "Go submodule has local changes; commit or stash them before building." >&2
  exit 1
fi
git -C "$root_dir" submodule sync --recursive -- src/huginn-messenger
git -C "$root_dir" -c submodule.src/huginn-messenger.branch=main \
  submodule update --init --recursive --remote --checkout -- src/huginn-messenger
core_revision="$(git -C "$core_dir" rev-parse HEAD)"
echo "Building Apple core from main: $core_revision"
mkdir -p "$root_dir/native/apple"
work_dir="$(mktemp -d "$root_dir/native/apple/build.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
cd "$core_dir"

build_slice() {
  local sdk="$1" arch="$2" goos="$3" triple="$4" mode="$5" output="$6"
  local sdk_path compiler
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  compiler="$(xcrun --sdk "$sdk" --find clang)"
  mkdir -p "$(dirname "$output")"
  echo "Building $sdk/$arch ($mode)"
  GOOS="$goos" GOARCH="$arch" CGO_ENABLED=1 CC="\"$compiler\"" \
    CGO_CFLAGS="-target $triple -isysroot \"$sdk_path\"" \
    CGO_LDFLAGS="-target $triple -isysroot \"$sdk_path\"" \
    "$go_bin" build -trimpath -ldflags='-checklinkname=0' \
    -buildmode="$mode" -o "$output" .
}

if [[ "$target" != ios ]]; then
  for arch in arm64 amd64; do
    clang_arch="$arch"
    [[ "$arch" != amd64 ]] || clang_arch=x86_64
    build_slice macosx "$arch" darwin "$clang_arch-apple-macos13.0" c-shared \
      "$work_dir/macos-$arch/huginn_messenger.dylib"
  done
  framework="$work_dir/huginn_messenger.framework"
  mkdir -p "$framework/Versions/A/Headers" "$framework/Versions/A/Resources"
  xcrun lipo -create "$work_dir"/macos-*/huginn_messenger.dylib \
    -output "$framework/Versions/A/huginn_messenger"
  xcrun install_name_tool -id \
    '@rpath/huginn_messenger.framework/Versions/A/huginn_messenger' \
    "$framework/Versions/A/huginn_messenger"
  cp "$work_dir/macos-arm64/huginn_messenger.h" "$framework/Versions/A/Headers/"
  cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.huginn.messenger.core</string>
<key>CFBundleName</key><string>huginn_messenger</string>
<key>CFBundleExecutable</key><string>huginn_messenger</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/huginn_messenger "$framework/huginn_messenger"
  ln -s Versions/Current/Headers "$framework/Headers"
  ln -s Versions/Current/Resources "$framework/Resources"
  # Ad-hoc signing permits loading locally; Xcode re-signs on embedding.
  codesign --force --sign - "$framework"
  mkdir -p "$root_dir/macos/Frameworks"
  rm -rf "$root_dir/macos/Frameworks/huginn_messenger.framework"
  cp -R "$framework" "$root_dir/macos/Frameworks/"
fi

if [[ "$target" != macos ]]; then
  build_slice iphoneos arm64 ios arm64-apple-ios15.0 c-archive \
    "$work_dir/device/libhuginn_messenger.a"
  build_slice iphonesimulator arm64 ios arm64-apple-ios15.0-simulator c-archive \
    "$work_dir/simulator-arm64/libhuginn_messenger.a"
  build_slice iphonesimulator amd64 ios x86_64-apple-ios15.0-simulator c-archive \
    "$work_dir/simulator-amd64/libhuginn_messenger.a"
  mkdir -p "$work_dir/simulator" "$work_dir/device/Headers" "$work_dir/simulator/Headers"
  xcrun lipo -create "$work_dir"/simulator-*/libhuginn_messenger.a \
    -output "$work_dir/simulator/libhuginn_messenger.a"
  cp "$work_dir/device/libhuginn_messenger.h" "$work_dir/device/Headers/"
  cp "$work_dir/simulator-arm64/libhuginn_messenger.h" "$work_dir/simulator/Headers/"
  xcodebuild -create-xcframework \
    -library "$work_dir/device/libhuginn_messenger.a" -headers "$work_dir/device/Headers" \
    -library "$work_dir/simulator/libhuginn_messenger.a" -headers "$work_dir/simulator/Headers" \
    -output "$work_dir/HuginnCore.xcframework"
  mkdir -p "$root_dir/ios/Frameworks"
  rm -rf "$root_dir/ios/Frameworks/HuginnCore.xcframework"
  cp -R "$work_dir/HuginnCore.xcframework" "$root_dir/ios/Frameworks/"
fi
printf '%s\n' "$core_revision" > "$root_dir/native/apple/core-revision.txt"
echo "Built Apple core: $core_revision"
