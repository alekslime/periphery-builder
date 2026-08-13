# Periphery OS — Build Debugging Handoff

**Date:** 2026-08-13
**Status:** Working ISO exists and is verified bootable. A follow-on hostname/branding fix caused a regression. Rootfs has been reverted to match the known-good ISO. Do not rebuild until the overlay bug (documented below) is properly fixed.

---

## Current known-good state

- **Working ISO:** `~/periphery/build/periphery-os-clean.iso`
  - Boots successfully in VirtualBox with EFI enabled
  - Reaches `ubuntu login:` prompt, `root` login works
  - This is the file to use for any testing/demoing right now — do not overwrite it
- **Rootfs:** `~/periphery/build/rootfs` has been reverted to match this ISO (hostname/casper.conf/initramfs-tools modules edits undone — see "Reverted changes" below)
- **Do NOT run `sudo ./build.sh`** until the overlay bug below is fixed — the current `build.sh` output will reproduce the broken initrd.

---

## What was accomplished this session

### 1. Fixed a real, previously-blocking EFI/GRUB boot bug

**Symptom:** ISO booted fine via BIOS but hung at `grub rescue>` under UEFI with:
```
error: file '/boot/grub/x86_64-efi/normal.mod' not found.
```
despite `xorriso -ls` proving the file was physically present in the ISO.

**Root cause:** The ISO had been hand-assembled across multiple separate manual `xorriso` invocations over time (evidence: multiple stale ISOs in `build/` — `periphery-os.iso`, `-v2`, `-v3`; staging dir `build/iso/boot/grub/` was missing `x86_64-efi/` entirely; the EFI module tree that *was* in the final ISO didn't come from the staging dir at all). Full-featured readers (`xorriso`, `isoinfo -R`) resolved the directory tree fine; GRUB's own minimal `iso9660` reader — which expects a single, coherent, non-appended-to layout — silently dropped the `x86_64-efi/` directory entry.

**Fix applied:**
1. Installed `grub-efi-amd64-bin grub-efi-amd64-signed shim-signed grub-pc-bin grub-common xorriso mtools` inside the rootfs (via `systemd-nspawn`)
2. Wiped the stale `build/iso/boot/grub/`, `build/iso/EFI/`, `build/iso/efi.img`
3. Copied fresh GRUB module trees directly from the rootfs's own installed packages:
   ```
   cp -r rootfs/usr/lib/grub/x86_64-efi build/iso/boot/grub/
   cp -r rootfs/usr/lib/grub/i386-pc build/iso/boot/grub/
   ```
4. Wrote a clean `grub.cfg` pointing at casper's `vmlinuz`/`initrd`
5. Built the ISO in **one single `grub-mkrescue` pass** — never appending to or patching an existing `.iso` again

This produced `periphery-os-clean.iso`, verified to boot all the way to a root shell in VirtualBox (screenshot evidence: `root@ubuntu:~#` prompt, kernel `7.0.0-14-generic`).

### 2. Automated the fix into `build.sh`

Created `~/periphery/periphery-builder/build.sh`, committed and pushed to GitHub. It:
- Verifies required GRUB packages are installed in the rootfs (checks `var/lib/dpkg/status` directly rather than chroot+dpkg, which is unreliable without `/proc`/`/sys` mounted)
- Verifies casper payload (`vmlinuz`, `initrd`, `filesystem.squashfs`) exists
- Wipes and repopulates `boot/grub/` fresh from the rootfs every run (never patches stale state)
- Writes `grub.cfg`
- Runs a single-pass `grub-mkrescue`
- Verifies `normal.mod` is present in the output as a sanity check

**Known gotcha already fixed in the script:** paths default to `$HOME/...`, which breaks under `sudo` (`$HOME` becomes `/root`). Script now hardcodes `/home/aleks/periphery/build/...` as defaults. If this ever moves to a different user/machine, that needs revisiting (accept a real user's home via `SUDO_USER` lookup would be the clean fix, not yet done).

`README.md` in `periphery-builder` was updated with a "Build automation — v1 (validated)" section documenting the bug and the fix. This is committed and pushed.

### 3. Attempted hostname/branding fix — caused a regression (unresolved)

**Goal:** login prompt currently says `ubuntu login:` — should say `periphery login:`.

**What was tried, in order:**
1. Set `/etc/hostname` and `/etc/hosts` in the rootfs directly → had no effect on the live boot, because...
2. Discovered `/usr/share/initramfs-tools/scripts/casper-bottom/18hostname` overwrites `/etc/hostname`/`/etc/hosts` at every live boot using a `$HOST` shell variable, sourced from `/etc/casper.conf`
3. Edited `/etc/casper.conf`: set `USERNAME`, `HOST`, `BUILD_SYSTEM` to `periphery`, and critically set `FLAVOUR="Periphery"` (the file's own comment warns that `HOST`/`USERNAME` are ignored and replaced by an auto-detected "flavour string" unless `FLAVOUR` is explicitly set to a non-empty value)
4. Regenerated `filesystem.squashfs` (`mksquashfs ... -comp xz -noappend`, matching the original build's compression flag found in `.bash_history` — an earlier squashfs regen accidentally used default gzip + `-e boot`, which was corrected)
5. Still showed `ubuntu` after rebuild — realized `/etc/casper.conf` changes only take effect if baked into `casper/initrd`, not just the squashfs, because casper-bottom scripts execute from inside the initrd *before* the squashfs is even mounted
6. Regenerated the initrd (`update-initramfs -c -k all` inside the rootfs, copied to `casper/initrd`) — **this broke boot entirely**, producing:
   ```
   (initramfs) /cow format specified as 'overlay' and no support found
   ```

### 4. Diagnosed (but did not cleanly fix) the overlay regression

Root cause isolated precisely, live, in the busybox initramfs shell:

- `overlay.ko.zst` module **is** present and correctly indexed in `modules.dep`
- Plain `modprobe overlay` and `modprobe -b overlay` **succeed** (`exit 0`)
- Casper's actual call in `/usr/share/initramfs-tools/scripts/casper` line 585 is:
  ```sh
  modprobe "${MP_QUIET}" -b overlay || panic "/cow format specified as 'overlay' and no support found"
  ```
  When `MP_QUIET` is unset, this expands to `modprobe "" -b overlay` — and **this specific empty-string-first-argument form fails** (`exit 1`), even though the equivalent call without the empty arg succeeds. This was reproduced live and confirmed repeatedly.
- A fix was attempted: `sed`-patching the script to remove the empty `${MP_QUIET}` argument, then regenerating the initrd. **This did not resolve the boot failure** — the same overlay error recurred after rebuild. This is the last thing that was tried before reverting; the patch's effect was not fully verified (no confirmation the patched initrd was correctly regenerated/picked up, and no `dmesg`/verbose modprobe output was successfully captured during the failing boot to confirm the exact failure point post-patch).

**This bug is unresolved.** Suspects not yet ruled out:
- The `sed` patch may not have matched (never confirmed the `grep` verifying the patch landed, before things escalated)
- `update-initramfs -c -k 7.0.0-14-generic` inside `systemd-nspawn` uses the **host's** running kernel context for some tooling even when targeting a different kernel version's module tree — worth checking if `depmod`/`update-initramfs` behavior differs meaningfully from a "true" target-only build environment
- Possible kmod version behavior change (newer kmod not tolerating an empty positional arg the way older versions/busybox modprobe might) — worth checking `apt policy kmod` inside the rootfs and whether a different kmod version resolves it
- Worth testing casper's script call in isolation with `set -x` tracing rather than piecemeal manual reproduction

### 5. Reverted to known-good state

To stop active damage and preserve a working demo, the rootfs was reverted:
```sh
echo "ubuntu" > /etc/hostname
sed -i 's/periphery/ubuntu/' /etc/hosts
cat > /etc/casper.conf << 'EOF'
export USERNAME="ubuntu"
export USERFULLNAME="Live session user"
export HOST="ubuntu"
export BUILD_SYSTEM="Ubuntu"
EOF
sed -i '/^overlay$/d' /etc/initramfs-tools/modules
```
The `scripts/casper` empty-arg patch (`sed 's/modprobe "\${MP_QUIET}" -b overlay/modprobe -b overlay/'`) was **left in place** — it's a plausible-looking bug fix even though it didn't resolve the observed regression on its own, and it shouldn't cause harm.

**Important:** the rootfs's `/boot/initrd.img-7.0.0-14-generic` was regenerated multiple times during this session and was NOT explicitly regenerated again after the revert above. Before trusting the rootfs to produce a working ISO again, **regenerate the initrd once more** post-revert and diff/test carefully, or — simpler — just keep using `periphery-os-clean.iso` as-is until the overlay bug is root-caused properly.

---

## Recommended next steps (in priority order)

1. **Don't touch the rootfs/initrd casually again.** Before any further changes, `cp -r` the current working `rootfs` to a `rootfs.known-good` backup, and/or keep `periphery-os-clean.iso` untouched as a fallback artifact. This whole regression happened because there was no backup/snapshot to fall back to.
2. **Properly root-cause the `modprobe "" -b overlay` failure** before re-attempting the hostname fix:
   - Get `dmesg` output at the exact moment of failure (was requested but never captured)
   - Run casper's `setup_overlay()` function with `sh -x` tracing to see real-time variable expansion
   - Check `apt policy kmod` version in the rootfs vs. what stock Ubuntu 26.04 live images ship
3. **Once overlay is fixed and verified**, redo the hostname/casper.conf/FLAVOUR fix (steps are documented above and were directionally correct — the `/etc/casper.conf` + `FLAVOUR="Periphery"` approach is the right mechanism, it just needs a working initrd to test against).
4. Regenerate `filesystem.manifest` alongside `filesystem.squashfs` — noted as stale during this session but not addressed (didn't block the login-prompt test, but should be fixed before this build is considered clean).
5. Consider adding rootfs backup/snapshotting to `build.sh` or as a separate `snapshot.sh`, given how much time a single bad initrd regen cost this session.

---

## Reference: key file locations

- Builder repo (git, pushed to GitHub): `~/periphery/periphery-builder/` (`README.md`, `build.sh`)
- Rootfs: `~/periphery/build/rootfs/`
- ISO staging: `~/periphery/build/iso/`
- Known-good ISO: `~/periphery/build/periphery-os-clean.iso`
- Casper hostname script: `rootfs/usr/share/initramfs-tools/scripts/casper-bottom/18hostname`
- Casper overlay setup: `rootfs/usr/share/initramfs-tools/scripts/casper` (function `setup_overlay`, ~line 545–585)
- Casper config: `rootfs/etc/casper.conf`
