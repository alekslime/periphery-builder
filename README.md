# periphery-builder

Build tooling for **Periphery OS** — an Ubuntu 26.04 LTS ("Resolute Raccoon") derivative focused on deliberate-practice learning environments for CS/CE students.

**Status:** Phase 3 — automated build pipeline working end-to-end (rootfs → overlay → squashfs → bootable ISO). Welcome app (first-run tool installer) implemented and boot-tested.

## Build host

- Native Ubuntu 26.04 laptop (not a VM — debootstrap/chroot tooling doesn't need Windows/VM isolation on a Linux host; see decision log below)
- Isolation for build steps: `systemd-nspawn`, not raw chroot
- VirtualBox is used only downstream, to boot and test the finished `.iso` — kept deliberately isolated from the build host

## Pipeline

```bash
cd ~/periphery/periphery-builder
./full-build.sh
```

`full-build.sh` runs the full chain:

1. **Base rootfs** — `debootstrap --arch=amd64 resolute ...` against the Ubuntu archive
2. **Overlay merge** — applies everything under `overlay/` on top of the rootfs (branding/installer files plus the Welcome app), file-for-file
3. **Package install inside the rootfs** (via `systemd-nspawn`), including:
   - `linux-image-generic` for the kernel (`/boot/vmlinuz-<ver>`, `/boot/initrd.img-<ver>`)
   - `casper` for live-boot support (this deliberately replaces `dracut`, pulled in transitively by the kernel package, with `initramfs-tools` — Casper's boot scripts are written against the initramfs-tools hook framework)
   - `python3-pyqt5` and the other Welcome app dependencies
4. **SquashFS + ISO assembly** — compresses the rootfs and builds the final bootable image (`casper/`, `boot/grub/`, `xorriso` with GRUB EFI stubs)

A clean run currently completes with no errors: all overlay files apply, the squashfs rebuilds, and the ISO builds successfully.

### Entering the rootfs manually

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs --bind-ro=/etc/resolv.conf
```

`--bind-ro=/etc/resolv.conf` is required for networking (apt) to work in non-`--boot` mode — `--resolv-conf=copy-host` was unreliable on this systemd version when the rootfs had no pre-existing `resolv.conf`.

For a full boot test of the rootfs itself (not the ISO):

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs --boot
```

Requires a root password set first (`passwd`, run inside a non-boot nspawn session) since debootstrap leaves root locked/passwordless.

## Overlay system

`overlay/` mirrors the target filesystem layout and is applied wholesale onto the rootfs during the build. It currently carries two categories of files side by side:

- **Branding/installer files** — Periphery OS branding and Calamares installer configuration
- **Welcome app** — `overlay/usr/share/periphery-welcome/` and `overlay/usr/bin/periphery-welcome`

## Periphery Welcome (first-run tool installer)

A PyQt5 app (`periphery_welcome.py`, launched via `/usr/bin/periphery-welcome`) that lets a student pick field-specific tools to install on first login. See `WELCOME_APP.md` for the full test checklist.

**Behavior:**

- **Tri-state category checkboxes** — checking a category checks all its tools; unchecking one tool inside a checked category flips the category to a partial/dash state
- **Real installs** — selected tools install via `apt-get` behind a single `pkexec` password prompt, with live output streamed to a log pane and a progress bar
- **Skip / re-open** — "Skip for now" dismisses the app; it can still be reopened later from the app menu regardless of whether it's been shown before
- **Autostart, scoped to real installs only** — the app is designed to auto-pop on first login *after a real Calamares install*, not during a live-ISO session. It distinguishes the two by checking the root filesystem type via `findmnt` (`overlay` on a live session vs. a real filesystem once installed) before deciding whether to autostart. This check only runs on the autostart code path — launching the app manually (app menu or `/usr/bin/periphery-welcome` directly) always works, on a live session or an install, regardless of this logic.
- **Marker file** — `~/.config/periphery-welcome-shown` tracks whether autostart has already fired once on a real install; manual launches ignore it entirely.

Boot-testing the Welcome app itself doesn't require Calamares to have run — a live-boot session (ISO attached, no disk) is enough for the UI, checkbox behavior, and a real `apt install` test. Verifying the autostart-after-real-install behavior specifically does require a full Calamares install onto a fresh disk, since that's the one path a live session can't exercise.

## Key decisions and why

- **Option C (debootstrap-based custom builder)** over live-build or Cubic — live-build is scaffolding-only reference; Cubic-style ISO respins don't give real ownership of the build pipeline.
- **Native Linux build host** over Windows/VirtualBox — debootstrap/chroot only work on Linux; once off Windows, a full VM adds isolation VirtualBox gives for free but at full VM overhead cost. `systemd-nspawn` gives comparable isolation (separate mount/PID/network namespaces) at near-zero overhead since it shares the host kernel.
- **VirtualBox's role narrowed to ISO testing only** — a separate VM boots the finished `.iso`, kept deliberately isolated from the build host.

## Known gaps / next steps

- `grub-efi-amd64-bin` needs to be installed inside the rootfs (currently only on the build host) before EFI boot can work end-to-end.
- Casper pulled in several `casper-bottom` scripts assuming a desktop environment (GNOME/KDE-specific disables) — needs review once Phase 4 desktop decisions are made.
- Welcome app: confirmed working via manual launch and live-ISO boot test; autostart-after-real-install still needs verification against a full Calamares install on a fresh disk.
