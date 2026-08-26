#!/usr/bin/env bash
set -euo pipefail
#
# Periphery OS — full pipeline
#
# Runs the entire build in one command: overlay -> squashfs -> initrd refresh
# -> ISO. Wraps apply-overlay.sh and build.sh rather than duplicating them.
#
# Usage:
#   ./full-build.sh            # fast iteration (gzip squashfs)
#   ./full-build.sh --release  # release build (xz squashfs, smaller/slower)
#
ROOTFS="${ROOTFS:-/home/aleks/periphery/build/rootfs}"
ISO_STAGING="${ISO_STAGING:-/home/aleks/periphery/build/iso}"

COMP="gzip"
if [ "${1:-}" = "--release" ]; then
    COMP="xz"
    echo "==> Release build: using xz compression (slower, smaller ISO)"
else
    echo "==> Dev build: using gzip compression (faster iteration)"
    echo "    Run with --release for a distributable ISO."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "==> Step 1/4: Applying overlay"
sudo ROOTFS="$ROOTFS" "$SCRIPT_DIR/apply-overlay.sh"

echo
echo "==> Step 2/4: Rebuilding squashfs ($COMP)"
sudo rm -f "$ISO_STAGING/casper/filesystem.squashfs"
sudo mksquashfs "$ROOTFS" "$ISO_STAGING/casper/filesystem.squashfs" -comp "$COMP" -noappend

echo
echo "==> Step 3/4: Refreshing initrd (picks up Plymouth/initramfs-affecting changes)"
sudo cp "$ROOTFS"/boot/initrd.img-* "$ISO_STAGING/casper/initrd"

echo
echo "==> Step 4/4: Building ISO"
sudo "$SCRIPT_DIR/build.sh"

echo
echo "==> Full build complete."
