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

## What the module does

A small root service, `power-profile-bridge`, follows power-profiles-daemon's
`ActiveProfile` over D-Bus and writes each handler's own
`/sys/class/platform-profile/*/profile`:

| power-profiles-daemon | SoC Power Slider | asus-wmi |
|---|---|---|
| power-saver | `low-power` | `quiet` |
| balanced | `balanced` | `balanced` |
| performance | `performance` | `performance` |

power-profiles-daemon keeps managing the CPU energy-performance preference and
stays the only thing KDE talks to. When the handlers disagree the legacy file
reads `custom`, which power-profiles-daemon 0.30 ignores, so the two never
fight. Because it can also skip a write it believes is already applied, the
bridge sets every profile, not only power-saver, re-applies after resume and
when it starts. Stopping the service puts both handlers back on `balanced` if
they were left disagreeing.

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

The service stops, the handlers go back to agreeing, and power-profiles-daemon
is on its own again. `/etc/power-profile-bridge.conf` is left in place.

## Scope

- Needs power-profiles-daemon (KDE's default). With TLP or tuned instead,
  there is no `ActiveProfile` to follow and the service only applies the
  current profile at start.
- It changes only platform-profile handlers. The xe GPU's own
  `power_profile` (`base` / `power_saving`) is untouched: there are no
  measurements yet of what it costs or saves.
- The upstream fix would be a hidden `quiet` choice for Intel's slider, as
  amd-pmf does for its own handler (commit `44e94fece517`), so the shared list
  gains a low-power entry.
