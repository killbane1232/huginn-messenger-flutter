#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?Usage: package-linux.sh VERSION [x64|arm64]}"
arch="${2:-x64}"
case "$arch" in
  x64) deb_arch=amd64 ;;
  arm64) deb_arch=arm64 ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || {
  echo "Expected a SemVer version" >&2; exit 1;
}
bundle="$root_dir/build/linux/$arch/release/bundle"
[[ -x "$bundle/huginn_messenger" ]] || { echo "Build the Linux bundle first" >&2; exit 1; }
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/DEBIAN" "$staging/opt/huginn-messenger" \
  "$staging/usr/bin" "$staging/usr/share/applications" \
  "$root_dir/build/packages"
cp -a "$bundle/." "$staging/opt/huginn-messenger/"
ln -s /opt/huginn-messenger/huginn_messenger "$staging/usr/bin/huginn-messenger"
cat > "$staging/usr/share/applications/huginn-messenger.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Huginn Messenger
Exec=/opt/huginn-messenger/huginn_messenger
Icon=/opt/huginn-messenger/data/icon.png
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=com.example.huginn_messenger
DESKTOP
cat > "$staging/DEBIAN/control" <<CONTROL
Package: huginn-messenger
Version: ${version/-/~}
Architecture: $deb_arch
Maintainer: Huginn Messenger <noreply@github.com>
Depends: libgtk-3-0 (>= 3.24), libglib2.0-0 (>= 2.80), libstdc++6, libc6 (>= 2.39), libayatana-appindicator3-1
Description: Huginn peer-to-peer messenger
CONTROL
dpkg-deb --build --root-owner-group "$staging" \
  "$root_dir/build/packages/huginn-messenger-$version-linux-$arch.deb"
