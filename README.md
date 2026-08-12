# periphery-builder

Build tooling for Periphery OS — an Ubuntu 26.04 LTS ("Resolute Raccoon") derivative
focused on deliberate-practice learning environments for CS/CE students.

## Status: Phase 2 — manual build process validated, automation not yet written

This repo currently contains no build scripts. Everything below was performed
manually, command-by-command, to validate the approach before automating it.
Automation is the next milestone.

## Build host

- Native Ubuntu 26.04 laptop (not a VM — debootstrap/chroot tooling doesn't
  need Windows/VM isolation on a Linux host; see decision log below)
- Isolation for build steps: `systemd-nspawn`, not raw chroot

## Process validated so far

1. **Base rootfs**: `sudo debootstrap --arch=amd64 resolute ~/periphery/build/rootfs http://archive.ubuntu.com/ubuntu/`
2. **Enter rootfs (admin tasks)**: `sudo systemd-nspawn -D ~/periphery/build/rootfs --bind-ro=/etc/resolv.conf`
   - `--bind-ro=/etc/resolv.conf` is required for networking (apt) to work in
     non-`--boot` mode. `--resolv-conf=copy-host` did NOT work reliably on this
     systemd version when the rootfs had no pre-existing resolv.conf — use the
     explicit bind mount instead.
3. **Full boot (testing)**: `sudo systemd-nspawn -D ~/periphery/build/rootfs --boot`
   - Requires a root password set first (`passwd` inside a non-boot nspawn session)
     since debootstrap leaves root locked/passwordless.
4. **Kernel**: `apt install -y linux-image-generic` (inside the rootfs)
   - Produces `/boot/vmlinuz-<ver>` + `/boot/initrd.img-<ver>`
   - Note: this pulls in `dracut` initially as part of `linux-image-generic`'s
     dependency chain.
5. **Casper (live-boot)**: `apt install -y casper`
   - This **removes `dracut`** and installs `initramfs-tools` instead — Casper's
     boot scripts are written against initramfs-tools' hook framework, not dracut.
     This is expected, not a conflict to fight.

## Key decisions and why

- **Option C (debootstrap-based custom builder) over live-build or Cubic** —
  live-build is scaffolding-only reference; Cubic-style ISO respins don't give
  real ownership of the build pipeline.
- **Native Linux build host over Windows/VirtualBox** — debootstrap/chroot only
  work on Linux; once off Windows, a full VM adds isolation VirtualBox gives for
  free but at full VM overhead cost. `systemd-nspawn` gives comparable isolation
  (separate mount/PID/network namespaces) at near-zero overhead since it shares
  the host kernel.
- **VirtualBox's role narrowed to ISO testing only** — a separate VM boots the
  finished `.iso`, kept deliberately isolated from the build host.

## Known gaps / next steps

- No build scripts yet — next milestone: SquashFS compression, ISO directory
  layout (`casper/`, `boot/grub/`), `xorriso` invocation with GRUB EFI stubs.
- `grub-efi-amd64-bin` needs to be installed *inside* the rootfs (currently only
  on the build host) before EFI boot can work.
- Casper pulled in several `casper-bottom` scripts assuming a desktop environment
  (GNOME/KDE-specific disables) — needs review once Phase 4 desktop decisions are made.
