# Periphery Welcome — first-boot tool installer

A branded, checkbox-based installer app (EndeavourOS-style) for
field-specific tooling: Software Engineering, Computer Engineering,
Data Science/ML, and Cybersecurity. Independent checkboxes across
categories — a student can pick more than one field.

## How it works

- **UI**: PyQt5, `QTreeWidget` with tri-state checkboxes (check a whole
  category, or fine-tune individual tools — checking/unchecking propagates
  automatically both ways via Qt's built-in tristate behavior).
- **Data-driven**: the tool list lives in `tools.json`, not the Python code.
  Add/remove/edit tools by editing that file — no code changes needed.
- **Install methods per tool**: `apt`, `snap` (with an optional `classic`
  flag), `pip`, or `manual` (opens the tool's website in a browser, for
  things that aren't cleanly packageable — currently just Ghidra).
- **Runs as one queued sequence**: all `apt` packages batch into a single
  `apt-get install`, snaps and pip packages likewise batch by type, each
  step runs via `pkexec` (one privilege prompt per step, not per package),
  output streams live into the log pane, progress bar advances per step.
- **First-boot behavior**: an autostart entry runs
  `periphery-welcome --autostart-check` on every login. That flag makes the
  app check `~/.config/periphery-welcome-shown` and exit immediately if it
  exists — so it only actually opens once, automatically, ever. Opening it
  from the app menu (`Periphery Welcome` in Settings/System) always shows it
  regardless of that marker, so people can come back and install more later.

## Required rootfs dependency

The app needs PyQt5 installed in the rootfs — it's not part of a base
Kubuntu install:

```bash
sudo systemd-nspawn -D ~/periphery/build/rootfs --bind-ro=/etc/resolv.conf /bin/bash -c '
apt update
apt install -y python3-pyqt5
'
```

Do this once, before your next `full-build.sh` run — it's a rootfs package
install, not something the overlay system handles (the overlay only copies
files, it doesn't install packages into the rootfs itself).

## Install

```bash
cd ~/periphery/periphery-builder
cp -r /path/to/this/overlay/* overlay/
git add overlay/
git commit -m "Add Periphery Welcome: field-specific tool installer app"
git push

./full-build.sh
```

## Verify before boot-testing

```bash
python3 -m py_compile overlay/usr/share/periphery-welcome/periphery_welcome.py
python3 -c "import json; json.load(open('overlay/usr/share/periphery-welcome/tools.json'))"
```

Both should run with no output (silent = valid).

## Boot-test checklist

- [ ] On first login after install, the window pops up automatically
- [ ] Checking a category checks all its tools; unchecking a tool inside a
      fully-checked category flips the category to the partial/dash state
- [ ] Clicking a tool shows its description below the tree
- [ ] "Skip for now" closes the window and writes the marker file (check:
      `cat ~/.config/periphery-welcome-shown`)
- [ ] After skipping, opening "Periphery Welcome" from the app menu still
      shows the full window (menu launch ignores the marker)
- [ ] After skipping, logging out and back in does **not** auto-open it again
      (autostart respects the marker)
- [ ] Selecting a real apt package (e.g. Git) and clicking Install prompts
      for a password once, then shows live `apt-get` output in the log pane
- [ ] Progress bar reaches 100% and the button re-enables when all steps finish

## Known limitations / next steps

- **pip installs use `--break-system-packages`** for a system-wide install
  (PEP 668 requires this on modern Debian/Ubuntu Python). This is a
  reasonable default for a shared educational environment, but means pip
  packages aren't isolated in a venv. Worth revisiting if that becomes a
  problem (e.g. version conflicts between courses).
- **`gh` (GitHub CLI) package availability wasn't independently verified**
  against this rootfs's exact apt sources — confirm with
  `apt-cache policy gh` before relying on it; some Ubuntu releases need
  GitHub's own apt repo added first.
- **No uninstall / "what's already installed" view.** Right now it's
  install-only, with no way to see from inside the app what's already on the
  system. Fine for v1 (first-boot flow), but worth adding if this becomes a
  tool people reopen often to manage their setup over time.
- **GPU-accelerated PyTorch isn't offered**, only CPU — intentional, since
  GPU builds need matching NVIDIA driver versions that can't be safely
  assumed for arbitrary student hardware. Marked `advanced` in `tools.json`
  as a signal, but still installs the CPU build under that label; if this
  needs to actually branch to a GPU-specific install path later, that's real
  additional work (driver detection, CUDA version matching), not a small
  edit to `tools.json`.
