# power-profile-bridge

Makes KDE's **Power Save** profile actually reach the SoC's low-power setting
and the quiet fan mode on the ASUS ExpertBook Ultra (B9406CAA).

## The problem

Panther Lake registers two platform-profile handlers on this laptop:

| Handler (`/sys/class/platform-profile/*/name`) | Choices |
|---|---|
| `SoC Power Slider` (Intel) | `low-power balanced performance` |
| `asus-wmi` | `quiet balanced performance` |

The legacy `/sys/firmware/acpi/platform_profile`, which power-profiles-daemon
0.30 drives, only lists the choices every handler shares:

```
$ cat /sys/firmware/acpi/platform_profile_choices
balanced performance
```

With no `low-power` or `quiet` in that list, power-profiles-daemon's
power-saver writes `balanced`. The SoC slider never reaches its most efficient
setting and asus-wmi never selects the quiet (whisper) fan mode. The same
intersection is tracked in
[asusctl#387](https://github.com/OpenGamingCollective/asusctl/issues/387); no
kernel change is pending.

It gets worse when you go from **performance** straight to **power-saver**:
the profile snaps back to **balanced** within a second, with nothing else
installed. power-profiles-daemon emulates power-saver by writing `balanced`,
blocks its file-monitor handler only while it writes, and then receives the
change event for its own write and takes it as a switch to balanced
(`ppd-driver-platform-profile.c`, the same in 0.30 and on main). Going from
balanced to power-saver works only because nothing is written.
[power-profiles-daemon#187](https://gitlab.freedesktop.org/upower/power-profiles-daemon/-/issues/187)
reported the same symptom and was closed by a fix for hp-wmi's `cool` choice,
which does not cover this case.

## What the module does

A small root service, `power-profile-bridge`, follows power-profiles-daemon's
`ActiveProfile` over D-Bus and writes each handler's own
`/sys/class/platform-profile/*/profile`:

| power-profiles-daemon | SoC Power Slider | asus-wmi |
|---|---|---|
| power-saver | `low-power` | `quiet` |
| balanced | `balanced` | `balanced` |
| performance | `performance` | `performance` |

power-profiles-daemon keeps managing the CPU energy-performance preference
(its `intel_pstate` driver) and stays the only thing KDE talks to. Its
`platform_profile` driver is switched off with a drop-in,
`/etc/systemd/system/power-profiles-daemon.service.d/50-asus-expertbook-power-profile-bridge.conf`
(`--block-driver=platform_profile`), so the bridge is the only thing writing
platform profiles and nothing snaps back. `powerprofilesctl list` then shows
`PlatformDriver: placeholder`. The daemon does not restore its saved profile
the first time its drivers change, so the module puts your current profile
back after restarting it.

The bridge sets every profile, not only power-saver, and re-applies after
resume, whenever power-profiles-daemon (re)appears on the bus, and once a
minute, which also puts back a handler someone changed by hand. Stopping the
service puts both handlers back on `balanced` if they were left disagreeing.
The drop-in keeps any other arguments the daemon's command line already had;
if a later drop-in overrides `ExecStart`, install stops instead of claiming
the driver is off. With a power-profiles-daemon too old for `--block-driver`,
the module warns and installs the bridge alone: power-saver then works when
reached from balanced, not straight from performance.

The mapping is generic: for each handler, power-saver picks `low-power`, then
`quiet`, `cool`, `balanced`; performance picks `performance`, then
`balanced-performance`, `balanced`. Override a single handler in
`/etc/power-profile-bridge.conf`:

```
power-saver.asus-wmi=balanced
```

## Install

```sh
./patch.sh install power-profile-bridge
power-profile-bridge --status
```

`--status` changes nothing:

```
power-profiles-daemon: power-saver
legacy platform_profile: custom
SoC Power Slider: low-power (choices: low-power balanced performance; wants low-power)
asus-wmi: quiet (choices: quiet balanced performance; wants quiet)
```

## Uninstall

```sh
./patch.sh uninstall power-profile-bridge
```

The service stops, the handlers go back to agreeing, the drop-in is removed
and power-profiles-daemon restarts with its `platform_profile` driver, keeping
your current profile. `/etc/power-profile-bridge.conf` is left in place.

## Scope

- Needs power-profiles-daemon (KDE's default), running. Install refuses while
  TLP, tuned, tuned-ppd, auto-cpufreq or system76-power is active, since the
  daemon's unit conflicts with them. The service never starts the daemon
  itself (no `Wants=`, no D-Bus auto-start) and exits quietly when it is not
  running, so switching to TLP later is safe; uninstall the module then.
- Hotkeys or tools that change the platform profile behind the daemon's back
  are no longer reflected in the KDE applet, because the daemon's platform
  driver is off.
- It changes only platform-profile handlers. The xe GPU's own
  `power_profile` (`base` / `power_saving`) is untouched: there are no
  measurements yet of what it costs or saves.
- The upstream fix would be a hidden `quiet` choice for Intel's slider, as
  amd-pmf does for its own handler (commit `44e94fece517`), so the shared list
  gains a low-power entry.
