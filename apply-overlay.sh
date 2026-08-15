#!/usr/bin/env bash
set -euo pipefail
#
# Periphery OS — overlay applier
#
# Copies everything under overlay/ into the build rootfs, preserving paths
# 1:1 (overlay/usr/bin/foo -> $ROOTFS/usr/bin/foo) and preserving
# permissions/ownership as recorded in the overlay tree.
#
# Run this BEFORE regenerating the squashfs. build.sh does not call this —
# it only packages whatever squashfs already exists in ISO_STAGING.
#
# Pipeline:
#   1. ./apply-overlay.sh              <- this script
#   2. sudo mksquashfs "$ROOTFS" "$ISO_STAGING/casper/filesystem.squashfs" -comp xz -noappend
#   3. sudo ./build.sh

OVERLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overlay"
ROOTFS="${ROOTFS:-/home/aleks/periphery/build/rootfs}"

if [ ! -d "$OVERLAY_DIR" ]; then
    echo "ERROR: overlay directory not found at $OVERLAY_DIR" >&2
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: rootfs not found at $ROOTFS (set ROOTFS=... to override)" >&2
    exit 1
fi

echo "==> Applying overlay: $OVERLAY_DIR -> $ROOTFS"
echo

file_count=0
while IFS= read -r -d '' src; do
    rel="${src#"$OVERLAY_DIR"/}"
    dest="$ROOTFS/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    perms="$(stat -c '%A %U:%G' "$src")"
    echo "  [$perms] $rel"
    file_count=$((file_count + 1))
done < <(find "$OVERLAY_DIR" -type f -print0)

echo
echo "==> Applied $file_count file(s)."
echo "==> Next: regenerate the squashfs, then run build.sh"
