# periphery-builder

Build tooling for **Periphery OS** — an Ubuntu 26.04 LTS ("Resolute Raccoon")
derivative focused on deliberate-practice learning environments for CS/CE
students.

**Status:** Rootfs, installer, full branding, and a first-boot tool-installer
app (11 fields, 51 tools) are all working end-to-end, boot-tested on a real
Calamares install. The build pipeline itself is fully automated via
`full-build.sh`. Next milestone: expanding actual learning-environment
features beyond the initial tool-installer app.

## Quickstart

```bash
git clone https://github.com/alekslime/periphery-builder.git
cd periphery-builder

# apply rootfs customizations (installer, branding, Welcome app)
sudo ROOTFS=/path/to/rootfs ./apply-overlay.sh

# full pipeline: overlay -> squashfs -> initrd refresh -> ISO
./full-build.sh              # fast iteration (gzip)
./full-build.sh --release    # distributable build (xz, smaller/slower)
```

Requires an existing rootfs built via `debootstrap` (see **Base rootfs**
below) with the packages listed in **Rootfs dependencies**.

## What's in the box

- **Custom Calamares installer branding** — `Install Periphery OS` launcher,
  fixed to run with proper privilege escalation via `pkexec`
  (`overlay/usr/bin/calamares-launch-normal`).
- **Full visual identity** — GRUB boot menu, Plymouth boot splash, SDDM login
  background, Plasma desktop wallpaper, and app/distributor icons, all pulled
  from one source photo + a two-color logo mark. See `BRANDING.md`.
- **Periphery Welcome** — a first-boot app (EndeavourOS-style) that lets
  students check off tools for their field and installs them via
  apt/snap/pip. Covers 11 fields (Software Engineering, Computer Engineering,
  Data Science/ML, Cybersecurity, Web Dev, Game Dev, DevOps/Cloud, Mobile Dev,
  Networking, Electrical Engineering, Mechanical/Robotics), 51 tools total,
  each package name individually checked against real sources rather than
  assumed. See `WELCOME_APP.md` for the full behavior spec and verification
  notes.
- **Overlay system** (`apply-overlay.sh` + `overlay/`) — every rootfs
  customization above is tracked as real files in this repo, applied
  reproducibly, instead of living only as manual edits inside a live shell.

## Repo layout

```
periphery-builder/
├── apply-overlay.sh   # copies overlay/ into a rootfs, preserving permissions
├── build.sh            # GRUB staging + grub-mkrescue -> final ISO
├── full-build.sh        # one-command pipeline: overlay -> squashfs -> initrd -> build.sh
├── overlay/              # tracked rootfs customizations, mirrors real paths
│   ├── usr/bin/calamares-launch-normal
│   ├── usr/share/applications/{periphery-installer,periphery-welcome}.desktop
│   ├── usr/share/periphery-welcome/            # Welcome app: code, assets, tools.json
│   ├── usr/share/wallpapers/Periphery/          # KDE wallpaper package
│   ├── usr/share/plymouth/themes/periphery/     # boot splash
│   ├── usr/share/sddm/themes/ubuntu-budgie-login/theme.conf
│   ├── etc/os-release
│   └── etc/xdg/autostart/periphery-welcome-autostart.desktop
├── BRANDING.md          # branding asset details, install steps, verified-vs-best-effort status
├── WELCOME_APP.md       # Welcome app architecture, install methods, boot-test checklist
└── HANDOFF.md           # phase-by-phase build log: what broke, root causes, fixes
```

## Build host

- Native Linux laptop (not a VM) — `debootstrap`/`chroot` tooling doesn't
  need Windows/VirtualBox isolation on a Linux host.
- Isolation for rootfs admin tasks: `systemd-nspawn`, not raw chroot.
- VirtualBox's role is narrowed to **ISO testing only** — a separate VM boots
  the finished `.iso`, kept deliberately isolated from the build host.

## Base rootfs

```bash
sudo debootstrap --arch=amd64 resolute ~/periphery/build/rootfs \
  http://archive.ubuntu.com/ubuntu/
```

Enter the rootfs for admin tasks (package installs, etc.):

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs --bind-ro=/etc/resolv.conf /bin/bash
```

`--bind-ro=/etc/resolv.conf` is required for networking (apt) to work in
non-`--boot` mode — `--resolv-conf=copy-host` was unreliable on this systemd
version when the rootfs had no pre-existing `resolv.conf`; without the bind
mount, DNS resolution silently fails inside the container even though the
host has working internet.

For a full boot test of the rootfs itself (not the ISO):

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs --boot
```

Requires a root password set first (`passwd`, run inside a non-boot nspawn
session) since debootstrap leaves root locked/passwordless.

## Rootfs dependencies

Installed once inside the rootfs before building:

```bash
apt install -y \
  linux-image-generic \
  casper \
  grub-efi-amd64-bin grub-efi-amd64-signed shim-signed grub-pc-bin grub-common \
  xorriso mtools \
  plymouth-label \
  python3-pyqt5
```

- `linux-image-generic` provides the kernel (`/boot/vmlinuz-<ver>`,
  `/boot/initrd.img-<ver>`).
- `casper` replaces `dracut` (pulled in transitively by the kernel package)
  with `initramfs-tools` — expected, Casper's boot scripts are written
  against the initramfs-tools hook framework, not dracut.
- `plymouth-label` is required for the custom Plymouth theme's text
  rendering; without it, `update-initramfs` warns about a missing
  `label-pango.so` plugin.
- `python3-pyqt5` is required for the Periphery Welcome app.

After installing packages that affect early boot (kernel, Plymouth theme,
casper), regenerate the initramfs — `full-build.sh` does this automatically
as part of its pipeline, but if you're working manually:

```bash
update-initramfs -u
```

## Periphery Welcome (first-run tool installer)

A PyQt5 app (`periphery_welcome.py`, launched via `/usr/bin/periphery-welcome`)
that lets a student pick field-specific tools to install on first login.

**Behavior:**

- **Tri-state category checkboxes** — checking a category checks all its
  tools; unchecking one tool inside a checked category flips the category to
  a partial/dash state.
- **Real installs** — selected tools install via apt/snap/pip, batched to
  minimize `pkexec` password prompts, with live output streamed to a log
  pane and a progress bar.
- **Skip / re-open** — "Skip for now" dismisses the app; it can still be
  reopened later from the app menu regardless of whether it's been shown
  before.
- **Autostart, scoped to real installs only** — the app auto-pops on first
  login *after a real Calamares install*, not during a live-ISO session. It
  distinguishes the two by checking the root filesystem type via `findmnt`
  (`overlay` on a live session vs. a real filesystem once installed) before
  deciding whether to autostart. This check only runs on the autostart code
  path — launching the app manually (app menu or `/usr/bin/periphery-welcome`
  directly) always works, on a live session or an install, regardless of
  this logic.
- **Marker file** — `~/.config/periphery-welcome-shown` tracks whether
  autostart has already fired once on a real install; manual launches
  ignore it entirely.

Boot-testing the Welcome app's UI, checkbox behavior, and a real install
doesn't require Calamares to have run — a live-boot session (ISO attached,
no disk) is enough. Verifying the autostart-after-real-install behavior
specifically does require a full Calamares install onto a fresh disk, since
that's the one path a live session can't exercise. See `WELCOME_APP.md` for
the full checklist and the per-tool package verification notes.

## Key decisions and why

- **Option C (debootstrap-based custom builder) over live-build or Cubic** —
  live-build is scaffolding-only reference; Cubic-style ISO respins don't
  give real ownership of the build pipeline.
- **Native Linux build host over Windows/VirtualBox** — `debootstrap`/chroot
  only work on Linux. `systemd-nspawn` gives comparable isolation
  (separate mount/PID/network namespaces) to a full VM at near-zero overhead,
  since it shares the host kernel.
- **Overlay system over manual rootfs edits** — early fixes (see
  `HANDOFF.md` Phase 3) were applied by hand inside a live `nspawn` shell,
  which meant they only existed on one machine with no record of how they
  were applied. Every customization now lives as a real file in this repo.

## Known gaps / next steps

- **Field toolchains can keep growing** — 11 fields/51 tools are in
  `tools.json` now; more fields/majors can be added there without touching
  app code. A few entries (Godot, ROS, GNS3, AWS CLI, Burp Suite, Ghidra) are
  intentionally `manual`-install rather than apt/snap, because no reliably
  verified package exists for them on this release — see `WELCOME_APP.md`
  for the specifics per tool.
- **No GPU-accelerated PyTorch path** — intentionally CPU-only for now, since
  GPU builds need matching NVIDIA driver versions that can't be safely
  assumed for arbitrary student hardware.
- Casper pulled in several `casper-bottom` scripts assuming a desktop
  environment (GNOME/KDE-specific disables) — worth a review pass.
- See `HANDOFF.md` for the full phase-by-phase history, including root
  causes for every bug hit along the way (a recurring one worth knowing:
  **always run `findmnt /` first** when something baked into the build
  "isn't showing up" in a VM — a stray attached disk winning the boot race
  has caused this exact symptom more than once).
