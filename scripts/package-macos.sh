#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?Usage: package-macos.sh VERSION}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || {
  echo "Expected a SemVer version" >&2; exit 1;
}
app="$root_dir/build/macos/Build/Products/Release/huginn_messenger.app"
architectures=" $(lipo -archs "$app/Contents/MacOS/huginn_messenger") "
[[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] || {
  echo "A universal macOS build is required: $architectures" >&2; exit 1;
}
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" "$root_dir/build/packages"
ditto "$app" "$staging/root/Applications/huginn_messenger.app"
staged_app="$staging/root/Applications/huginn_messenger.app"
# Incremental Flutter builds may re-sign App.framework without refreshing the
# outer app's seal. Verify nested code, then refresh only an ad-hoc app signature.
# Never replace a Developer ID signature with an ad-hoc one.
signature="$(codesign --display --verbose=2 "$staged_app" 2>&1)"
if [[ "$signature" == *"Signature=adhoc"* ]]; then
  for framework in "$staged_app/Contents/Frameworks/"*.framework; do
    codesign --verify --deep --strict "$framework"
  done
  codesign --force --sign - \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
pkgbuild --analyze --root "$staging/root" "$staging/components.plist"
# Always replace the complete installed bundle, including removed libraries.
# Do not accidentally update a developer's build or another unpacked copy.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$staging/components.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$staging/components.plist"
pkgbuild --root "$staging/root" --component-plist "$staging/components.plist" \
  --install-location / --identifier com.huginn.huginnMessenger.pkg \
  --version "${version%%[-+]*}" \
  "$root_dir/build/packages/huginn-messenger-$version-macos-universal.pkg"
