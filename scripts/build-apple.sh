#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-all}"
case "$target" in
  all|macos|ios) ;;
  *) echo "Usage: $0 [all|macos|ios]" >&2; exit 1 ;;
esac
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
[[ -x "$flutter_bin" ]] || { echo "Flutter is required; set FLUTTER_BIN if it is not on PATH." >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo "Apple builds require macOS." >&2; exit 1; }
xcodebuild -version >/dev/null
command -v pod >/dev/null || { echo "CocoaPods is required (brew install cocoapods)." >&2; exit 1; }
cd "$root_dir"
"$flutter_bin" pub get
"$flutter_bin" analyze
"$flutter_bin" test
"$root_dir/scripts/build-apple-core.sh" "$target"
if [[ "$target" != ios ]]; then
  "$flutter_bin" build macos --release
  echo "macOS app: build/macos/Build/Products/Release/huginn_messenger.app"
fi
if [[ "$target" != macos ]]; then
  "$flutter_bin" build ios --release --no-codesign
  "$flutter_bin" build ios --simulator --debug
  echo "iOS unsigned app: build/ios/iphoneos/Runner.app"
  echo "iOS simulator app: build/ios/iphonesimulator/Runner.app"
fi
