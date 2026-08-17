#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
version_file=${HUGINN_CORE_VERSION_FILE:-$root_dir/core-library.version}
version=${HUGINN_CORE_VERSION:-$(tr -d '[:space:]' < "$version_file")}
repository=${HUGINN_CORE_REPOSITORY:-killbane1232/huginn-messenger}
release_base=${HUGINN_CORE_RELEASE_BASE:-https://github.com/$repository/releases}
host_arch=${HUGINN_CORE_ARCH:-}

if [ -z "$version" ]; then
    echo "Huginn core version is empty" >&2
    exit 1
fi

if [ -z "$host_arch" ]; then
    case "$(uname -m)" in
        x86_64) host_arch=amd64 ;;
        aarch64|arm64) host_arch=arm64 ;;
        *)
            echo "Unsupported Huginn core architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac
fi

case "$host_arch" in
    amd64|arm64) ;;
    *)
        echo "Unsupported Huginn core architecture: $host_arch" >&2
        exit 1
        ;;
esac

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
download_url="$release_base/download/$version"
curl --fail --location --silent --show-error \
    "$download_url/SHA256SUMS" \
    --output "$temp_dir/SHA256SUMS"

install_asset() {
    platform=$1
    arch=$2
    destination=$3
    asset="huginn-messenger_${version}_${platform}_${arch}.tar.gz"
    archive="$temp_dir/$asset"
    unpack_dir="$temp_dir/unpack_${platform}_${arch}"

    curl --fail --location --silent --show-error \
        "$download_url/$asset" \
        --output "$archive"
    grep "  $asset\$" "$temp_dir/SHA256SUMS" > "$temp_dir/check_${platform}_${arch}"
    (cd "$temp_dir" && sha256sum --check "check_${platform}_${arch}")

    mkdir -p "$unpack_dir" "$destination"
    tar -xzf "$archive" -C "$unpack_dir"
    install -m 0755 "$unpack_dir/libhuginn_messenger.so" \
        "$destination/libhuginn_messenger.so"
    if [ ! -f "$root_dir/native/include/libhuginn_messenger.h" ]; then
        mkdir -p "$root_dir/native/include"
        install -m 0644 "$unpack_dir/libhuginn_messenger.h" \
            "$root_dir/native/include/libhuginn_messenger.h"
    fi
}

install_asset linux "$host_arch" "$root_dir/native/linux/$host_arch"
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
    install_asset android "$abi" "$root_dir/android/app/src/main/jniLibs/$abi"
done
