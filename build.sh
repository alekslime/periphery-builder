#!/usr/bin/env bash
set -euo pipefail
# Periphery OS — ISO build script
# Automates the validated manual process from README.md.
# Always builds fresh: staging is wiped and repopulated from the rootfs
# on every run, and the ISO is produced in a single grub-mkrescue pass.
ROOTFS="${ROOTFS:-/home/aleks/periphery/build/rootfs}"
ISO_STAGING="${ISO_STAGING:-/home/aleks/periphery/build/iso}"
OUTPUT_ISO="${OUTPUT_ISO:-/home/aleks/periphery/build/periphery-os.iso}"
VOLID="${VOLID:-PERIPHERYOS}"
echo "==> Checking rootfs has required GRUB packages"
for pkg in grub-efi-amd64-bin grub-pc-bin xorriso; do
    if ! grep -q "^Package: ${pkg}$" "$ROOTFS/var/lib/dpkg/status"; then
        echo "ERROR: $pkg not installed in rootfs. Run inside nspawn:" >&2
        echo "  apt install -y grub-efi-amd64-bin grub-efi-amd64-signed shim-signed grub-pc-bin grub-common xorriso mtools" >&2
        exit 1
    fi
done
echo "==> Checking casper payload exists"
for f in vmlinuz initrd filesystem.squashfs; do
    if [ ! -f "$ISO_STAGING/casper/$f" ]; then
        echo "ERROR: missing $ISO_STAGING/casper/$f" >&2
        echo "Run casper/squashfs build steps first." >&2
        exit 1
    fi
done
echo "==> Wiping stale GRUB staging (never patch an old tree)"
rm -rf "$ISO_STAGING/boot/grub" "$ISO_STAGING/EFI" "$ISO_STAGING/efi.img"
mkdir -p "$ISO_STAGING/boot/grub"
echo "==> Copying fresh GRUB module trees from rootfs"
cp -r "$ROOTFS/usr/lib/grub/x86_64-efi" "$ISO_STAGING/boot/grub/"
cp -r "$ROOTFS/usr/lib/grub/i386-pc" "$ISO_STAGING/boot/grub/"
echo "==> Writing grub.cfg (Periphery branding: dark green bg, gold highlight)"
cat > "$ISO_STAGING/boot/grub/grub.cfg" << 'GRUBCFG'
set default=0
set timeout=5
insmod all_video
insmod gfxterm
terminal_output gfxterm

# Periphery OS palette: #17231F background, #D6A85D gold highlight, #F1EEE4 text
background_color 23,35,31
set color_normal=white/black
set menu_color_normal=white/black
set menu_color_highlight=black/yellow

menuentry "Periphery OS (live)" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}
menuentry "Periphery OS (live, safe graphics)" {
    linux /casper/vmlinuz boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}
GRUBCFG
echo "==> Building ISO in a single grub-mkrescue pass"
grub-mkrescue -o "$OUTPUT_ISO" "$ISO_STAGING" -- -volid "$VOLID"
echo "==> Verifying output"
xorriso -indev "$OUTPUT_ISO" -ls /boot/grub/x86_64-efi/normal.mod
echo "==> Done: $OUTPUT_ISO"
