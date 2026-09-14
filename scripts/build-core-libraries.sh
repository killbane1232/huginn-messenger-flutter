#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
core_dir="$root_dir/src/huginn-messenger"
target="${1:-all}"

case "$target" in
  all|linux|android) ;;
  *) echo "Usage: $0 [all|linux|android]" >&2; exit 1 ;;
esac

if [[ "$(uname -s)" != Linux ]]; then
  echo "Linux is required to build the Linux/Android core libraries." >&2
  exit 1
fi
if command -v go >/dev/null 2>&1; then
  go_bin=go
elif [[ -x /usr/local/go/bin/go ]]; then
  go_bin=/usr/local/go/bin/go
else
  echo "Go is required to build the Huginn core." >&2
  exit 1
fi

if [[ "$target" != linux ]]; then
  ndk_dir="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
  if [[ -z "$ndk_dir" ]]; then
    sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
    ndk_dir="$(find "$sdk_dir/ndk" -mindepth 1 -maxdepth 1 -type d \
      -name '[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | sort -V | tail -n 1 || true)"
  fi
  ndk_bin="$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin"
  for triple in aarch64-linux-android armv7a-linux-androideabi x86_64-linux-android i686-linux-android; do
    if [[ ! -x "$ndk_bin/${triple}24-clang" ]]; then
      echo "Android NDK compiler not found: $ndk_bin/${triple}24-clang. Set ANDROID_NDK_HOME." >&2
      exit 1
    fi
  done
fi

# Never discard local core edits when switching to the current remote main.
if [[ -e "$core_dir/.git" ]] && [[ -n "$(git -C "$core_dir" status --porcelain)" ]]; then
  echo "Go submodule has local changes; commit or stash them before building." >&2
  exit 1
fi
git -C "$root_dir" submodule sync --recursive -- src/huginn-messenger
git -C "$root_dir" -c submodule.src/huginn-messenger.branch=main \
  submodule update --init --recursive --remote --checkout -- src/huginn-messenger
core_revision="$(git -C "$core_dir" rev-parse HEAD)"
echo "Building Huginn core from main: $core_revision"

cd "$core_dir"
if [[ "$target" != android ]]; then
  host_arch="$("$go_bin" env GOHOSTARCH)"
  case "$host_arch" in
    amd64|arm64) ;;
    *) echo "Unsupported Linux architecture: $host_arch" >&2; exit 1 ;;
  esac
  out_dir="$root_dir/native/linux/$host_arch"
  mkdir -p "$out_dir" "$root_dir/native/include"
  GOOS=linux GOARCH="$host_arch" CGO_ENABLED=1 "$go_bin" build \
    -ldflags='-checklinkname=0' -buildmode=c-shared -o "$out_dir/libhuginn_messenger.so" .
  install -m 0644 "$out_dir/libhuginn_messenger.h" "$root_dir/native/include/libhuginn_messenger.h"
fi

build_android_abi() {
  local arch="$1" abi="$2" triple="$3" arm="${4:-}"
  local out_dir="$root_dir/native/android/$abi"
  local jni_dir="$root_dir/android/app/src/main/jniLibs/$abi"
  echo "Building Android core: $abi"
  mkdir -p "$out_dir" "$jni_dir"
  GOOS=android GOARCH="$arch" GOARM="$arm" CGO_ENABLED=1 \
    CC="$ndk_bin/${triple}24-clang" PATH="$ndk_bin:$PATH" \
    "$go_bin" build -ldflags='-checklinkname=0' -buildmode=c-shared \
      -o "$out_dir/libhuginn_messenger.so" .
  install -m 0755 "$out_dir/libhuginn_messenger.so" "$jni_dir/libhuginn_messenger.so"
}

if [[ "$target" != linux ]]; then
  build_android_abi arm64 arm64-v8a aarch64-linux-android
  build_android_abi arm armeabi-v7a armv7a-linux-androideabi 7
  build_android_abi amd64 x86_64 x86_64-linux-android
  build_android_abi 386 x86 i686-linux-android
fi

echo "Built Huginn core: $core_revision"
