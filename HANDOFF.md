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
## Phase 4 — Overlay system + full branding (wallpaper, logo, SDDM, Plymouth, GRUB)

**Status: ✅ Confirmed working end-to-end on a fresh boot, on a second (new) laptop**

### Overlay system

Rootfs customizations were previously applied by hand, directly inside a live
`systemd-nspawn` shell — meaning the Phase 3 installer fix only existed on one
machine's disk, with no record of *how* it was applied. Replaced with:

```
periphery-builder/
├── apply-overlay.sh       # copies overlay/ into $ROOTFS, preserving permissions
└── overlay/                # mirrors real rootfs paths exactly
    └── usr/bin/calamares-launch-normal, etc.
```

`apply-overlay.sh` is additive-only — it copies/overwrites files but does **not**
delete rootfs files that were removed from `overlay/`. If a file is intentionally
dropped from the overlay (e.g. a wrong-format metadata file), it must also be
manually deleted from the rootfs, or it'll linger and can cause confusing
"which file is actually being read" bugs (this bit us once during the wallpaper
metadata fix — see below).

Pipeline is now: `apply-overlay.sh` → `mksquashfs` → `build.sh`. Note `build.sh`
itself does **not** touch the squashfs — it only assembles GRUB + packages the
ISO from whatever's already staged.

### Branding assets added

Sourced from a real desert photo + a two-color "eclipse mark" logo (a solid
circle with a literal cutout hole — confirmed via pixel analysis, not a separate
dot color). Palette pulled from the source photo: `#28443A` dark green,
`#F1EEE4` cream, `#D6A85D` gold accent, `#17231F` near-black green.

| Surface | Path |
|---|---|
| Plasma wallpaper package | `/usr/share/wallpapers/Periphery/` |
| Generic background refs | `/usr/share/backgrounds/periphery/` |
| App/distributor icon | `/usr/share/icons/hicolor/*/apps/`, `/usr/share/pixmaps/` |
| `/etc/os-release` | Full Periphery branding, `LOGO=periphery-logo` |
| SDDM login background | `/usr/share/sddm/themes/ubuntu-budgie-login/theme.conf` |
| Plymouth boot splash | `/usr/share/plymouth/themes/periphery/` (script-based theme: background photo, translucent panel, wordmark, gold progress bar) |
| GRUB boot menu | Solid palette colors (not the photo — GRUB's text renderer can't blend a busy background with legible menu text), edited directly into `build.sh` |

### Gotchas discovered along the way

1. **SDDM theme assumption was wrong.** Initially assumed the active SDDM theme
   was `breeze` (KDE's generic default) and shipped a `theme.conf.user` override
   for it. The actual active theme, confirmed via
   `/etc/sddm.conf.d/50-ubuntu-budgie.conf`, is `ubuntu-budgie-login` — a
   completely different QML-based theme ("SilentSDDM") with its own config
   schema and **no** `.user` override mechanism. Fixed by shipping a full
   replacement `theme.conf` (only the two `background=` lines changed from the
   shipped original). **Lesson: verify the active theme name before assuming
   the generic/upstream config mechanism applies.**

2. **KDE wallpaper package metadata format was wrong twice.** First attempt used
   `metadata.desktop` with an incorrect service-type key
   (`ServiceTypes=Wallpaper/Images` instead of the real key). Second attempt
   added a `metadata.json` but with extra unverified keys
   (`KPackageStructure`, `ServiceTypes` array). Neither worked — the package
   never appeared in the wallpaper picker. Root cause found by inspecting
   Plasma's own built-in wallpaper package (`/usr/share/wallpapers/Next/`,
   displayed in the UI as "Sub-Arctic") as ground truth: **this Plasma version
   uses `metadata.json` only, with a much simpler schema — no `ServiceTypes` or
   `KPackageStructure` key needed at all**, just a minimal `KPlugin` block
   (`Id`, `Name`, `License`, `Authors`). **Lesson: when guessing a config format
   for KDE/Plasma internals, find a real working example on the same system
   first rather than trusting documentation or general knowledge — schemas
   vary meaningfully by Plasma version.**

3. **Stale `metadata.desktop` lingered after being replaced.** Because
   `apply-overlay.sh` is additive-only, removing `metadata.desktop` from the
   overlay tree did not remove it from the already-applied rootfs — it had to
   be deleted manually. Until it was, the wallpaper package directory had both
   the old broken file and the new correct one sitting side by side.

4. **The phantom-disk boot bug recurred — on a different laptop.** After
   transferring `build/rootfs` and the built ISO to a second machine (to work
   with more horsepower), the wallpaper still appeared missing. `findmnt /`
   showed `/dev/sda2 ext4` — booted into an old **installed** copy of Periphery
   OS on a leftover `.vdi`, not the live ISO — the *exact* same failure mode as
   the very first bug of this whole project (see Phase 3), just recreated fresh
   on the new machine's VirtualBox setup. Confirmed by `os-release` showing
   correct branding (so it really was a Periphery install) combined with a
   `metadata.desktop` dated days earlier than the current fix. Fixed the same
   way as before: detach the stray `.vdi`, cold-boot the VM, confirm
   `findmnt /` shows `overlay`/`/cow`, not a real disk partition.

   **Lesson: this class of bug is now a known, recurring failure mode any time
   a VM is reused or set up freshly — always run `findmnt /` as the first
   sanity check whenever something that should be baked into the build
   "isn't showing up," before assuming the build itself is broken.** Cheap to
   check, expensive to misdiagnose.

### Known cosmetic issue (not investigated further)

Wallpaper picker thumbnails show a generic broken-image placeholder for **both**
"Periphery" and Plasma's own stock "Sub-Arctic" entry in a live-boot session —
since the stock, untouched entry is affected identically, this points to a
live-session thumbnail-cache quirk (likely tied to the read-only
squashfs + writable `/cow` overlay), not a defect in our wallpaper package. The
actual full-size wallpaper renders correctly once selected. Worth re-checking
on a real (non-live) install, where thumbnail caching has a normal writable
disk to work with.
