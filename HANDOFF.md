# Periphery OS — Build Handoff

**Last updated:** 2026-08-14
**Status:** Working ISO with full KDE Plasma desktop, verified booting to SDDM → Plasma in VirtualBox. Hostname still shows "ubuntu" (cosmetic, deferred). Rootfs snapshot recommended before further changes.

---

## Current known-good state

- **Working rootfs:** `~/periphery/build/rootfs` — debootstrap base + KDE Plasma (`kde-plasma-desktop`) + SDDM, fully installed and verified via `sudo ./build.sh` → boots to SDDM login → Plasma desktop in VirtualBox (EFI enabled).
- **Build script:** `~/periphery/periphery-builder/build.sh` — single-pass `grub-mkrescue` build, verified working repeatedly across two major milestones (base EFI/GRUB boot, then KDE desktop).
- **Backup:** `~/periphery/build/rootfs.known-good` — should be refreshed to match current KDE-installed state (see Immediate Next Steps below; this was last snapshotted *before* KDE was installed).
- Login currently shows `ubuntu login:` / SDDM as "ubuntu" — hostname fix is a known, deferred cosmetic item (see "Deferred: hostname branding" below).

---

## Milestone 1 (earlier session): EFI/GRUB boot bug — RESOLVED

**Symptom:** ISO booted via BIOS but hung at `grub rescue>` under UEFI:
```
error: file '/boot/grub/x86_64-efi/normal.mod' not found.
```
despite `xorriso -ls` proving the file existed in the image.

**Root cause:** The ISO had been hand-assembled across multiple separate manual `xorriso` invocations over time (evidence: multiple stale ISOs in `build/`, staging dir missing `x86_64-efi/` entirely, the working EFI module tree didn't come from staging). Full readers (`xorriso`, `isoinfo -R`) resolved the directory tree fine; GRUB's own minimal `iso9660` reader — which expects a single, coherent, non-appended-to layout — silently dropped the `x86_64-efi/` directory entry.

**Fix:** Wipe stale staging, copy fresh GRUB module trees directly from the rootfs's installed packages, write clean `grub.cfg`, build the ISO in **one single `grub-mkrescue` pass**. Never append to or patch an existing `.iso`.

This became the core logic of `build.sh` (see below).

---

## build.sh — what it does

Located at `~/periphery/periphery-builder/build.sh`. Committed and pushed to GitHub.

1. Verifies required GRUB packages installed in rootfs (checks `var/lib/dpkg/status` directly — chroot+dpkg is unreliable without `/proc`/`/sys` mounted)
2. Verifies casper payload (`vmlinuz`, `initrd`, `filesystem.squashfs`) exists in `build/iso/casper/`
3. Wipes and repopulates `boot/grub/` fresh from the rootfs every run — never patches stale state
4. Writes `grub.cfg`
5. Runs single-pass `grub-mkrescue -o periphery-os.iso build/iso -- -volid PERIPHERYOS`
6. Verifies `normal.mod` present in output as a sanity check

**Known gotcha (already fixed in script):** paths default to `$HOME/...`, which breaks under `sudo` (`$HOME` becomes `/root`). Script hardcodes `/home/aleks/periphery/build/...`. If this ever moves to a different user/machine, revisit via `SUDO_USER` lookup.

**Usage after any rootfs change:**
```sh
# 1. Regenerate initrd (only if kernel modules/boot-time behavior changed)
sudo systemd-nspawn -D ~/periphery/build/rootfs --bind-ro=/etc/resolv.conf
update-initramfs -c -k all
exit
cp ~/periphery/build/rootfs/boot/initrd.img-* ~/periphery/build/iso/casper/initrd

# 2. Regenerate squashfs (always, if rootfs contents changed)
sudo rm ~/periphery/build/iso/casper/filesystem.squashfs
sudo mksquashfs ~/periphery/build/rootfs ~/periphery/build/iso/casper/filesystem.squashfs -comp xz -noappend

# 3. Rebuild ISO
cd ~/periphery/periphery-builder
sudo ./build.sh
```

---

## Milestone 2 (this session): KDE Plasma Desktop — RESOLVED

**Goal:** Give Periphery OS a real desktop environment.

**Decision:** `kde-plasma-desktop` (not `kubuntu-desktop`). Rationale: Periphery is a deliberate-practice CS/CE learning environment, not a general-purpose distro — `kubuntu-desktop` pulls in the full consumer app suite (Kontact, games, media apps) that add build time/image size without pedagogical value. `kde-plasma-desktop` gives the Plasma shell, System Settings, Konsole, Dolphin, Kate — the working surface students need. Additional tools should be added deliberately later, not as part of a mystery-meat bundle.

**Login manager:** SDDM (login screen shown, no auto-login — deliberate choice for a learning environment where multiple users may share a machine).

### Steps taken

1. **Enabled `universe`/`multiverse`/`restricted` repos** — debootstrap only enables `main` by default; KDE packages live in `universe`. Rewrote `/etc/apt/sources.list` inside rootfs to include all four components across `resolute`, `resolute-updates`, `resolute-security`.

2. **Installed packages** (inside `systemd-nspawn`):
   ```
   apt update
   apt install -y kde-plasma-desktop sddm
   ```
   This pulled ~1124 packages, ~748MB download. No blocking interactive prompts encountered this run. Some `nspawn`-related warnings during postinst (`System has not been booted with systemd as init system... Can't operate`, dbus "reload" failures) are **expected and harmless** — these are postinst hooks trying to reach a running systemd/dbus that doesn't exist in a non-`--boot` nspawn session. They resolve correctly once casper boots the ISO for real with systemd as PID 1.

3. **Regenerated initrd and squashfs** (see "build.sh — what it does" above for the exact commands), then ran `sudo ./build.sh`.

4. **Booted in VirtualBox** — confirmed SDDM login screen appears, login succeeds, full KDE Plasma desktop loads.

**Verified working, not yet spot-checked:** individual apps (Konsole, Dolphin, System Settings) — should be confirmed open cleanly, since these are the first tools students will touch.

---

## Deferred: hostname branding (`ubuntu` → `periphery`)

**Not resolved. Deliberately deferred, do not restart this work until re-reading this section.**

### What was tried (earlier session, before KDE work)

1. Editing `/etc/hostname` / `/etc/hosts` directly in rootfs → **no effect on live boot**, because...
2. `/usr/share/initramfs-tools/scripts/casper-bottom/18hostname` overwrites both files at every live boot using a `$HOST` variable sourced from `/etc/casper.conf`
3. Edited `/etc/casper.conf`: set `USERNAME`, `HOST`, `BUILD_SYSTEM` to `periphery`, and set `FLAVOUR="Periphery"` (the file's own comment warns `HOST`/`USERNAME` are ignored and replaced by an auto-detected "flavour string" unless `FLAVOUR` is explicitly non-empty)
4. Regenerated squashfs — still showed `ubuntu`, because `/etc/casper.conf` only takes effect if baked into `casper/initrd` (casper-bottom scripts run from inside the initrd, before the squashfs is even mounted)
5. Regenerated initrd — **this broke boot entirely**:
   ```
   (initramfs) /cow format specified as 'overlay' and no support found
   ```

### Root cause of the boot break, as far as it was diagnosed

Isolated live in the busybox initramfs shell: casper's actual call in `scripts/casper` (~line 585) is:
```sh
modprobe "${MP_QUIET}" -b overlay || panic "..."
```
When `MP_QUIET` is unset this becomes `modprobe "" -b overlay` — and **this exact empty-string-first-argument form fails** (confirmed reproducible: `exit 1`), even though `modprobe -b overlay` (no empty arg) succeeds, and even though the `overlay.ko.zst` module is correctly present and indexed in `modules.dep`. This looks like a kmod behavior quirk with empty positional args, not a missing-module problem.

A `sed` patch removing the empty `${MP_QUIET}` arg from `scripts/casper` was attempted but **did not resolve the failure on rebuild** — the patch's effect was never fully verified (no confirmation the `grep` check on the patched line was run before things moved on, and no `dmesg`/verbose modprobe output was captured from a rebuilt+re-tested initrd).

### What was done to stop the bleeding

Reverted rootfs's `/etc/hostname`, `/etc/hosts`, `/etc/casper.conf`, and `/etc/initramfs-tools/modules` back to original `ubuntu` state. The `scripts/casper` empty-arg sed patch was **left in place** (harmless, plausible fix, just unconfirmed).

### Why this is now lower priority

Since the hostname regression, the project pivoted to installing KDE Plasma (Milestone 2 above), which required its own initrd/squashfs regen cycles and **succeeded cleanly** — meaning the current `rootfs`'s initrd, as of this session, boots fine with a full desktop. This suggests the casper-conf/hostname changes specifically (not general initrd regen) were what triggered the overlay bug — but this has not been re-tested since KDE was added, and the two initrd regens happened under different conditions, so treat this as a hypothesis, not a confirmed fact.

### Recommended approach when resuming this work

1. **Snapshot the current KDE-working rootfs first** (see Immediate Next Steps).
2. Redo the `/etc/casper.conf` edit (`USERNAME`, `HOST`, `BUILD_SYSTEM`, `FLAVOUR` all set to `periphery`/`Periphery`) on a copy, not the live rootfs.
3. Regenerate initrd, test boot **before** touching squashfs, so failures are cheap to diagnose and revert.
4. If the overlay bug recurs, this time capture:
   - `dmesg` output at the exact failure point (never successfully captured before)
   - `sh -x` trace through casper's `setup_overlay()` function
   - `apt policy kmod` version, to check for a known kmod regression around empty positional args
5. Only touch `scripts/casper` directly as a last resort — patching a stock package script by hand is fragile across future `casper` package upgrades.

---

## Future milestone: major/degree selector (design intent, not started)

**User's stated goal:** at install time or first boot, let the student choose their major/degree (CS, CE, EE, Data Science, etc.), and have Periphery install/configure a curated package set accordingly.

**Key design decision already made:** Periphery is intended to be **installed to disk**, not purely live/USB — persistence is the real target. This means:

- The major-selector wizard belongs on **first login after installation completes**, not in the live session (live sessions don't persist installed packages anyway).
- Periphery needs an actual installer before this wizard makes sense. **Calamares** is the natural choice (used by Kubuntu and many derivatives, themeable, well-documented) — not yet added to the project.

**Not yet designed:**
- First-boot detection mechanism (systemd unit / autostart entry that fires once)
- GUI picker implementation (native Kirigami/Qt widget vs. simpler Zenity/YAD dialog)
- `major → package list` mapping format (proposed: a data file like `majors.yaml` in `periphery-builder`, not hardcoded, so instructors can extend it)
- Whether package install happens live via apt at first-boot (needs network + time) or is pre-staged during the ISO/install build

**Sequencing:** KDE (done) → Calamares installer (not started) → first-boot wizard (not started) → majors.yaml content (not started).

---

## Immediate next steps (priority order)

1. **Refresh the rootfs backup** to capture the current KDE-working state:
   ```sh
   sudo rm -rf ~/periphery/build/rootfs.known-good
   sudo cp -r ~/periphery/build/rootfs ~/periphery/build/rootfs.known-good
   ```
   The existing snapshot predates KDE and is now stale as a restore point.
2. **Spot-check core Plasma apps** — open Konsole, Dolphin, System Settings in the booted VM; confirm no crashes.
3. **Commit this handoff + confirm README reflects KDE milestone**, push to GitHub.
4. Resume hostname branding work per the "Recommended approach" above, OR move on to Calamares installer research — user's call on priority.
5. Regenerate `filesystem.manifest` alongside `filesystem.squashfs` — still noted as stale from an earlier session, never addressed. Doesn't block current boots but should be fixed before considering the build fully clean.

---

## Reference: key file locations

- Builder repo (git, pushed to GitHub): `~/periphery/periphery-builder/` (`README.md`, `build.sh`, `HANDOFF.md`)
- Rootfs: `~/periphery/build/rootfs/`
- Rootfs backup (needs refresh): `~/periphery/build/rootfs.known-good/`
- ISO staging: `~/periphery/build/iso/`
- Current built ISO: `~/periphery/build/periphery-os.iso` (produced by `build.sh`)
- Earlier known-good ISO (pre-KDE, EFI-fix only): `~/periphery/build/periphery-os-clean.iso`
- Casper hostname script: `rootfs/usr/share/initramfs-tools/scripts/casper-bottom/18hostname`
- Casper overlay setup: `rootfs/usr/share/initramfs-tools/scripts/casper` (function `setup_overlay`, ~line 545–585)
- Casper config: `rootfs/etc/casper.conf`
- apt sources (now includes universe/multiverse/restricted): `rootfs/etc/apt/sources.list`
