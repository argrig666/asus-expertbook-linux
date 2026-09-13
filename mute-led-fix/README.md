# Mute indicator LEDs (F1 / F4)

On the ASUS ExpertBook Ultra B9406CAA, audio mute can work while the orange
F1 speaker and F4 microphone indicators do not follow it. This module adds
the missing speaker LED and an optional desktop-session synchronizer.

Verified on **BIOS B9406CAA.312, Arch Linux 7.2.3-arch1-3, Omarchy with
PipeWire and EasyEffects**. The laptop owner physically confirmed that both
lights turn on when muted and off when unmuted after installing the fix.
Other BIOS versions and desktops have not been hardware-tested.

## What is missing

The stock `asus-wmi` driver exposes `platform::micmute` via ASUS WMI device
`0x00040017`, but does not expose the speaker mute LED on this machine.
The B9406CAA.312 DSDT provides `0x0004001c` for the speaker indicator:

- DSTS returns `GGOV(0x001a0885) | 0x00010000` (presence and current state).
- DEVS passes boolean 0/1 to `SGOV(0x001a0885, value)` and returns 1.
- The microphone device similarly uses GPIO `0x001a0884`.

These are descriptions of the firmware's existing methods, **not instructions
to write GPIOs directly**. The driver calls the exported ASUS WMI API only.
The firmware table used for this analysis was compared byte-for-byte against
the running machine's DSDT. The speaker device ID is also named `SoundMuteLed`
in [G-Helper's ASUS interface](https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs).

The small GPL-2.0-only DKMS driver registers `platform::mute`, is restricted
to this DMI product name, checks firmware presence, and refuses a conflicting
LED name. It leaves the stock microphone driver in charge of F4.

Omarchy's microphone shortcut writes its LED, but other ways of changing mute
can leave it stale. The unprivileged session service reconciles both LEDs once
a second using `brightnessctl` and logind, without changing permissions or audio
state. Readback is compared before writing. It retries after audio-server
restarts and checks again after resume; suspend/resume has not been tested here.

## Install

Prerequisites: DKMS, a kernel build toolchain, matching headers for the running
kernel, Python 3, `pactl`, `brightnessctl`, systemd/logind, and a desktop audio
server implementing the PulseAudio protocol (including `pipewire-pulse`).

For Arch's standard `linux` kernel, the additional packages are usually:

```sh
sudo pacman -S --needed dkms base-devel linux-headers python libpulse brightnessctl
```

Use your kernel's matching header package instead of `linux-headers` for LTS,
Zen or CachyOS, and the matching LLVM toolchain for a Clang-built kernel.
Only 7.2.3-arch1-3 has been built/tested for this module. DKMS's normal kernel
build settings apply; compiler overrides can be supplied through DKMS config.

```sh
./patch.sh install mute-led-fix
# Run these as your desktop user, without sudo:
systemctl --user daemon-reload
systemctl --user enable --now expertbook-mute-leds.service
```

No reboot required. The installer builds for the running kernel; DKMS
autoinstall handles future kernel installations with matching headers. If you
also boot another already-installed kernel, install for it with
`sudo dkms install b9406-mute-led/0.1 -k <kernel-release>` before using it.

Disable another service managing these LEDs before enabling this one. If the
desktop already handles F4 correctly, a second synchronizer may be unnecessary.
The session service is explicitly enabled per user; `install-all` installs its
files and the driver but does not enable it for every desktop account.

### Which audio state is shown?

On Omarchy, F1 follows `omarchy-audio-output-sink`, the same helper used by
the volume/mute shortcut, so an EasyEffects DSP sink resolves to its physical
output. On other desktops it follows `pactl get-default-sink`; automatic DSP
passthrough resolution is specific to Omarchy. F4 follows the default audio
source, matching Omarchy's microphone shortcut.

Virtual inputs such as EasyEffects and their underlying hardware can have
separate mute states. F4 reports the default source's mute flag, not a guarantee
that every microphone is muted. The service does not change routing, hardware
mute, volume, or keybindings. Zero volume alone is not treated as mute.

## Verify

```sh
./patch.sh status mute-led-fix
systemctl --user status expertbook-mute-leds
journalctl --user -u expertbook-mute-leds
brightnessctl -d platform::mute info
brightnessctl -d platform::micmute info
```

Press the usual speaker/microphone mute shortcuts and also change mute through
your audio panel. The corresponding orange light should follow within about
one second. No root password should be needed for normal operation.

Verification performed on the reference machine:

- Built the DKMS driver against the running kernel, installed and loaded it.
- Wrote each LED on/off as the desktop user and read both states back.
- Deliberately desynchronized each LED without changing audio; the service
  restored the expected state automatically.
- Laptop owner confirmed both physical F1 and F4 indicators work.

For contributors, run `python -m unittest discover -s mute-led-fix/tests` for
the synchronizer's routing and write-suppression tests.

## Uninstall

```sh
# Desktop user, before removing the service file:
systemctl --user disable --now expertbook-mute-leds.service
./patch.sh uninstall mute-led-fix
systemctl --user daemon-reload
```

The loaded LED driver remains until the next reboot; its boot entry, DKMS
installation and sources are removed. The stock microphone driver stays intact.

## Upstream path

This is a compatibility module, not an upstream kernel submission. The
long-term kernel fix belongs in ASUS WMI's LED support. Once the installed
kernel exposes `platform::mute` natively, this module should be removed;
the installer skips when a different driver already supplies that name.
The session synchronizer can then be retained separately if the desktop still
does not drive the LEDs. No claim is made that a kernel patch is accepted or
pending upstream.
