## Phase 3 — Calamares installer: launcher, boot-media, and privilege bugs

**Status: ✅ Full install validated end-to-end (Welcome → Partitions → Users →
Install → Finish → Reboot into installed OS)**

### Context

Calamares (`calamares-settings-kubuntu`) was installed and the `.desktop` launcher
existed in `/usr/share/applications/`, but "Install Periphery OS" never appeared in
the Plasma (Kickoff) application menu. Root cause turned out to be three unrelated
bugs stacked on top of each other — none of them were the `.desktop` file itself.

### Bug 1 — Red herring chase: `.desktop` file, KDE menu, kbuildsycoca

Ruled out one by one, in order:
- `NoDisplay` / `Hidden` / `OnlyShowIn` / `NotShowIn` — none present
- `desktop-file-validate` — clean
- `kbuildsycoca6` cache rebuild — no effect
- KMenuEdit user-level overrides (`~/.config`) — none found
- `/etc/xdg/menus/plasma-applications.menu` category matching — correct,
  `Categories=System;Settings;` matches the merged System menu
- `applications-kmenuedit.menu` merge file — doesn't exist on this system, ruled out

None of these were the problem. Renamed the launcher from the stock
`kubuntu-calamares.desktop` to `periphery-installer.desktop` as a clean-room test —
this didn't fix it either, which was the clue that pointed away from the `.desktop`
file entirely.

### Bug 2 — VM was booting a phantom installed OS, not the live ISO

Verified via `findmnt /` inside the "live" session:
```
/  /dev/sda2  ext4  rw,relatime
```
That's a real installed filesystem, not a squashfs/overlay live root — meaning the
VM was never actually running the ISO we kept rebuilding and re-verifying (confirmed
independently via `unsquashfs -cat` against both the staged squashfs and the final
mounted ISO — the files were correctly present in the build output the entire time).

**Cause:** two stray `.vdi` disks left attached under the SATA controller from
earlier test installs. With **UEFI enabled** in VM settings, VirtualBox's boot-order
list (`System → Motherboard`, marked "BIOS only") is ignored, and UEFI firmware
found a bootable EFI System Partition on one of the leftover disks and always
booted straight to it, regardless of which ISO was attached to the optical drive.

**Fix:** Remove all `.vdi` attachments under `Settings → Storage` when doing a
clean live-ISO boot test. Only attach a fresh disk when intentionally running an
install through to completion.

### Bug 3 — Calamares running unprivileged (false storage error + explicit rights error)

Once the VM was actually booting the live ISO, Calamares showed:
- "The installer is not running with administrator rights."
- "There is not enough drive space. At least 8 GiB is required." — despite a real
  25 GB disk being attached and visible via `lsblk`.

Both traced to the same cause: `/usr/bin/calamares-launch-normal` launched
Calamares with no privilege escalation:

```bash
# before
calamares -D8;
```

Without root, Calamares can't properly enumerate block devices via udisks2/KPMcore,
so its storage check silently falls back to reporting the live session's overlay
filesystem (`/cow`, ~4.6 GB) instead of the real target disk — explaining the false
"not enough space" error alongside the explicit rights error.

**Fix:**
```bash
# after
pkexec calamares -D8;
```

`BROWSER='sudo -H -u kubuntu firefox'` earlier in the script is intentional and was
left unchanged — it keeps Calamares' embedded browser links (Donate/Support)
running as an unprivileged user even though Calamares itself now runs as root via
`pkexec`.

### Current launcher files

`/usr/share/applications/periphery-installer.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=Install Periphery OS
GenericName=Install Periphery OS
Comment=Install Periphery OS
Exec=/usr/bin/calamares-launch-normal
Icon=system-software-install
Terminal=false
Categories=System;Settings;
Keywords=installer;calamares;system;periphery;
StartupNotify=true
```

`/usr/bin/calamares-launch-normal` (relevant tail):
```bash
export BROWSER='sudo -H -u kubuntu firefox'
pkexec calamares -D8;
```

### Post-install verification

```bash
findmnt /        # /dev/sda2 ext4 rw,relatime — confirmed real installed root
lsblk             # sda1 300M /boot/efi, sda2 24.7G /
```

### Known gaps / next steps

- **Branding not applied to installed system.** `/etc/os-release` still reports
  stock `PRETTY_NAME="Ubuntu 26.04 LTS"`, `NAME="Ubuntu"`, `LOGO=ubuntu-logo`. Needs
  editing in `build/rootfs/etc/os-release` (and likely `/etc/lsb-release`, GRUB
  menu strings, Plymouth splash) before next squashfs rebuild.
- **Post-installer launcher visibility** — after a completed install, "Install
  Periphery OS" correctly no longer appears in the menu. Not yet confirmed whether
  this is intentional (matches upstream Kubuntu's live-only Calamares entry
  behavior) or accidental; worth an explicit check.
- Switch `mksquashfs` back to `-comp xz` for release builds (gzip/lzo were used
  during this session purely to speed up rebuild iteration).

### Rebuild + test procedure (reference)

```bash
cd ~/periphery
sudo rm -f build/iso/casper/filesystem.squashfs
sudo mksquashfs build/rootfs build/iso/casper/filesystem.squashfs -comp xz -noappend

# sanity check before building the ISO
sudo unsquashfs -cat build/iso/casper/filesystem.squashfs \
  /usr/share/applications/periphery-installer.desktop

cd ~/periphery/periphery-builder
sudo ./build.sh

ls -lht ~/periphery/build/*.iso   # confirm fresh timestamp
```

VM checklist before booting:
- [ ] Only the ISO attached (or ISO + one fresh disk if testing a full install)
- [ ] No stray `.vdi` files left attached from previous runs
- [ ] Boot fresh, not resuming a saved state
- [ ] After boot: `findmnt /` — expect squashfs/overlay for a live session, or
      `/dev/sdaN ext4` for a completed install
