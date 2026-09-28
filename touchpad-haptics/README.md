# touchpad-haptics

Click force and haptic intensity for the haptic touchpad of the ASUS
ExpertBook Ultra (B9406CAA), which Windows sets through MyASUS and Linux has
no control for.

## How it works

The PixArt `093A:4F05` pad is a Windows Precision Touchpad pressure pad. Its
own HID report descriptor (964 bytes, SHA-256 `6f5470f0…97d4`) declares two
standard feature reports:

| Report | Usage | Range | Meaning |
|---|---|---|---|
| 8 | Digitizer `0x0D` / Button Press Threshold `0xB0` | 1–3 | How hard a press must be before it clicks: 1 light, 2 medium, 3 firm |
| 9 | Haptics `0x0E` / Intensity `0x23` | 0–100 | Strength of the click feedback |

The firmware does not answer `GET_FEATURE`, so the current values cannot be
read back. It keeps them across suspend and forgets them at power-off.

The module installs:

| File | Path | What it does |
|---|---|---|
| `touchpad-haptics` | `/usr/local/bin/` | CLI that sends validated `SET_FEATURE` requests. It refuses any device that is not `HID_ID 0018:0000093A:00004F05` with exactly this report descriptor. |
| `71-asus-b9406-touchpad-haptics.rules` | `/etc/udev/rules.d/` | Tags the pad's hidraw node `uaccess`, so the logged-in user can change the settings without root, and starts the restore service when the node appears. |
| `touchpad-haptics-restore.service` | `/etc/systemd/system/` | Oneshot that applies `/etc/touchpad-haptics.conf` at boot and after a driver rebind. |
| `touchpad-haptics.conf` | `/usr/share/touchpad-haptics/` → seeded to `/etc/` | Saved settings; all commented out at first, so the firmware defaults stay. |

## Use

```sh
./patch.sh install touchpad-haptics

touchpad-haptics set --click-force light --intensity 30       # try, not saved
sudo touchpad-haptics set --click-force medium --intensity 60 --save
touchpad-haptics status
```

The `uaccess` permission applies to the active session; if `set` reports that
it cannot open the device, log out and back in once.

### Check that it reaches the firmware

The firmware cannot report its values back, so test the two reports one at a
time. Neither command below saves anything.

Intensity (report 9) is easy to feel:

```sh
touchpad-haptics set --intensity 0      # clicks lose their vibration
touchpad-haptics set --intensity 100    # strong clicks
```

That proves report 9 reaches the pad, and nothing about report 8. The click
force levels are close together, so compare the two ends with a clear
intensity, pressing slowly with one finger:

```sh
touchpad-haptics set --intensity 60 --click-force light
touchpad-haptics set --click-force firm
```

With `firm`, a press that clicked under `light` should need noticeably more
force before it clicks. If the two feel the same, report 8 is not taking
effect; please open an issue. Then pick real values and save them with
`--save`.

## Uninstall

```sh
./patch.sh uninstall touchpad-haptics
```

The pad keeps its current values until the next power-off;
`/etc/touchpad-haptics.conf` is left in place.

## Credit

The report layout and the suspend/power-off behaviour were first worked out in
[bramvera/omarchy-asus-expertbook-haptic-touchpad](https://github.com/bramvera/omarchy-asus-expertbook-haptic-touchpad)
(MIT), an Omarchy bar widget. This module is an independent, desktop-agnostic
implementation, and the report descriptor was re-verified on the reference
B9406CAA.
