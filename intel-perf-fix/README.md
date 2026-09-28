# intel-perf-fix

Userspace thermal policy for Intel Panther Lake / Lunar Lake on KDE Plasma +
Arch / CachyOS: `thermald` by default, `intel-lpmd` only on request.

## What gets installed

| Package | From | Service | What it does |
|---|---|---|---|
| `thermald` | `extra` repo | `thermald.service` | Intel thermal daemon. Panther Lake (supported since 2.5.9) is an "adaptive" platform: thermald runs the OEM's own thermal tables (PL1/PL2 limits, passive trips, a power-slider condition read from power-profiles-daemon). It is not a P/E-core scheduler. |
| `intel-lpmd` | `extra` / `cachyos` repo | `intel_lpmd.service` | **Opt-in since 1.2.0.** In low-power mode it confines system/user/machine.slice to the four LP-E CPUs, forces `intel_pstate` to active mode and moves the SoC power slider. |

Why `intel-lpmd` is opt-in:

- Intel marks 0.1.1, the build CachyOS ships, "test release, do not include in
  any distro release"; upstream main no longer changes cpusets by default.
- A public Panther Lake A/B test (Dell XPS 16, battery, balanced) found no
  significant idle-power difference (+0.17 W, 95% CI −0.01…+0.34) and roughly
  doubled app launch time with it.
- Apps started while it confines the system see four CPUs and size their
  thread pools to that.
- On this no-SMT hybrid CPU the kernel already places work by core capacity;
  lpmd's ITMT step is skipped, which is what its
  "Open .../sched_itmt_enabled failed" lines mean.

The earlier "parks idle work on a single LP-E core" and "≈2–2.5 W idle"
claims were never measured on this B9406CAA.

## What we deliberately don't include

Omarchy 3.5 / 3.6 also bundles:

- **Hyprland-specific toggles** (window-gap persistence, touchpad on/off via
  `XF86TouchpadOn`, scaling cycle, etc.) — not relevant on KDE Plasma.
- **Dell-DMI-gated kernel patches** (Panel Replay, CS42L43 SOF, Wi-Fi 7 BE2xx
  Dell-XPS quirk, haptic-trackpad Synaptics quirk) — proven not to apply to
  this ASUS B9406CAA. The upstream `intel_quirks.c` entry matches PCI
  subsystem `0x1028:0x0db9` (Dell XPS 14 DA14260); ours is `0x1043:0x15e4`.
  Our `display-fix` module handles the same problem with a cmdline param
  scoped to our hardware.
- **ThinkPad mic-mute LED sync** — different vendor.
- **T2 Mac / Tuxedo / Slimbook keyboard fixes** — different hardware.
- **`/home` btrfs snapshot churn fix** — we don't snapshot `/home` (no
  `snapper -c home` config on this system).

## Install

```sh
./patch.sh install intel-perf-fix
# with intel-lpmd as well:
sudo INTEL_PERF_LPMD=1 ./patch.sh install intel-perf-fix
```

Updating from 1.1.0, which enabled `intel-lpmd` unconditionally, disables
`intel_lpmd.service` unless `INTEL_PERF_LPMD=1` is set. A system where the
module was never recorded as installed is left alone.

After install (no reboot needed), verify:

```sh
./patch.sh status intel-perf-fix
# expect:
#   thermald.service       active
#   thermald pkg:          2:2.5.x-...
#   intel_lpmd.service     inactive (opt-in, off by default)
```

To check that thermald actually applies something, look for its adaptive
conditions: `journalctl -u thermald | grep -Ei 'condition|adaptive'`. If a BIOS
table only ever lowers PL1, compare a 10-minute load with the service stopped
and started; since 2.5.12 thermald restores the power limits when it stops.

## Uninstall

```sh
./patch.sh uninstall intel-perf-fix
```

Disables both services. Packages are left installed so reverting is
reversible without re-fetching from the network. To remove them fully:

```sh
sudo pacman -Rns thermald
sudo pacman -Rns intel-lpmd
```

## Note: the intel-lpmd package

`intel-lpmd` now ships as a normal binary package in both the `extra` and
`cachyos` repos (it used to be AUR-only). The module's install hook pulls it
with a plain `pacman -S --needed --noconfirm intel-lpmd` — same path as
`thermald`, no AUR helper or `$SUDO_USER` dance. The package provides the
`intel_lpmd.service` unit. To install manually:

```sh
sudo pacman -S --needed intel-lpmd
sudo systemctl enable --now intel_lpmd.service
```
