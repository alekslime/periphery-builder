# periphery-builder

Build tooling for Periphery OS — an Ubuntu 26.04 LTS ("Resolute Raccoon")
derivative focused on deliberate-practice learning environments for CS/CE
students.

**Status:** Phase 5 — installer, branding, and a first-boot tool-installer app
are all working end-to-end on a fresh install. Automation is done for the
build pipeline itself; the next milestone is expanding the actual
learning-environment features beyond the initial four fields.

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
  students check off tools for their field — Software Engineering, Computer
  Engineering, Data Science/ML, Cybersecurity — and installs them via
  apt/snap/pip with one privilege prompt per batch. Pops up automatically
  once on a real install, reopenable anytime from the app menu. Never
  auto-pops on the live ISO itself. See `WELCOME_APP.md`.
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
non-`--boot` mode — without it, DNS resolution silently fails inside the
container even though the host has working internet.

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

- `casper` replaces `dracut` with `initramfs-tools` — expected, Casper's boot
  scripts are written against the initramfs-tools hook framework.
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

- **Field toolchains beyond the initial four** — SWE, Computer Engineering,
  Data Science/ML, and Cybersecurity are covered in `tools.json`; more
  fields/majors can be added there without touching app code.
- **`gh` (GitHub CLI) apt availability** hasn't been independently verified
  against this rootfs's exact sources — confirm with `apt-cache policy gh`.
- **No GPU-accelerated PyTorch path** — intentionally CPU-only for now, since
  GPU builds need matching NVIDIA driver versions that can't be safely
  assumed for arbitrary student hardware.
- See `HANDOFF.md` for the full phase-by-phase history, including root
  causes for every bug hit along the way (a recurring one worth knowing:
  **always run `findmnt /` first** when something baked into the build
  "isn't showing up" in a VM — a stray attached disk winning the boot race
  has caused this exact symptom more than once).
