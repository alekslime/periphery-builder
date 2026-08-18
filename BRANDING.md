# Periphery OS — Branding Assets

Built from your uploaded desert wallpaper photo and the two-color "eclipse mark"
logo (a solid circle with a cutout hole — not a separate dot color, confirmed by
pixel inspection: both logo variants use exactly two colors, background + shape).

Palette used (sourced from your screenshot):
| Hex | Use |
|---|---|
| `#28443A` | Dark green — logo/panel fill |
| `#F1EEE4` | Cream — logo/text on dark |
| `#D6A85D` | Gold — accent (progress bar, GRUB highlight) |
| `#17231F` | Near-black green — GRUB background |
| `#82B6C7` | Sky blue (present in photo, not separately applied) |
| `#789B88` | Sage (present in photo, not separately applied) |

## What this covers

| Surface | Path | Confidence |
|---|---|---|
| Plasma wallpaper picker entry | `/usr/share/wallpapers/Periphery/` | ✅ Solid — standard KDE wallpaper package format |
| Generic background refs | `/usr/share/backgrounds/periphery/` | ✅ Solid |
| App icon / distributor logo | `/usr/share/icons/hicolor/*/apps/` | ✅ Solid — standard hicolor theme, all common sizes |
| Pixmap fallback logo | `/usr/share/pixmaps/periphery-logo.png` | ✅ Solid |
| `/etc/os-release` branding | `LOGO=periphery-logo` references the hicolor icon | ✅ Solid, but **placeholder URLs** — edit `HOME_URL`/`SUPPORT_URL`/`PRIVACY_POLICY_URL` before shipping |
| SDDM login background | `/usr/share/sddm/themes/breeze/theme.conf.user` | ⚠️ Verify — this is breeze's standard admin-override file, but confirm your rootfs's SDDM theme is actually `breeze` (`ls /usr/share/sddm/themes/`) |
| Plymouth boot splash | `/usr/share/plymouth/themes/periphery/` | ⚠️ Verify — real script-theme (background + panel + wordmark + progress bar), but needs `update-alternatives` to activate (see below) and a real boot test — Plymouth script syntax can't be tested outside a real boot |
| GRUB boot menu | edited into `build.sh` | ⚠️ Verify — uses solid palette colors instead of the photo (GRUB's text-mode color list doesn't support arbitrary hex, and a busy background photo would hurt menu text legibility) |
| Default wallpaper for new users | `/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc` | ⚠️ Best-effort — Plasma's config format is version-sensitive. If it doesn't take effect, the wallpaper still shows up correctly in the picker (**System Settings → Appearance → Wallpaper → Periphery**) as a one-click fallback |

## Install

```bash
cd ~/periphery-builder
cp -r /path/to/branding-overlay/overlay/* overlay/
cp /path/to/branding-overlay/build.sh build.sh   # replaces existing build.sh with GRUB branding added

git add overlay/ build.sh
git commit -m "Add branding: wallpaper, logo, SDDM/Plymouth/GRUB theming"
```

Then run the normal pipeline:

```bash
sudo ROOTFS=/home/aleks/periphery/build/rootfs ./apply-overlay.sh
sudo mksquashfs build/rootfs build/iso/casper/filesystem.squashfs -comp gzip -noappend
sudo ./build.sh
```

## Activating Plymouth (one-time, inside the rootfs)

Copying the theme files isn't enough on its own — Plymouth needs to be told to
use it. Inside `systemd-nspawn`:

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs /bin/bash -c '
update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
  default.plymouth /usr/share/plymouth/themes/periphery/periphery.plymouth 100
update-alternatives --set default.plymouth /usr/share/plymouth/themes/periphery/periphery.plymouth
update-initramfs -u
'
```

That last step regenerates the initramfs so Plymouth picks up the new theme —
without it, casper's existing `initrd` in `build/iso/casper/` still has the old
theme baked in, and you'd need to re-copy the updated initrd into staging too.

## Verifying SDDM theme name

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs /bin/bash -c 'ls /usr/share/sddm/themes/'
```

If it's not `breeze`, move `theme.conf.user` to
`overlay/usr/share/sddm/themes/<actual-name>/theme.conf.user` instead.

## Boot-test checklist

- [ ] GRUB menu shows dark green background, gold-highlighted selected entry, readable text
- [ ] Plymouth splash shows desert photo, translucent panel, wordmark, gold progress bar filling left→right
- [ ] SDDM login screen shows the desert wallpaper as background
- [ ] After first login (or manually), Plasma desktop wallpaper is the desert photo — check picker regardless: **System Settings → Appearance → Wallpaper → Periphery**
- [ ] `cat /etc/os-release` shows `PRETTY_NAME="Periphery OS v1"` and correct `LOGO=`
- [ ] KInfoCenter / "About This System" shows the Periphery icon, not a blank/broken image
