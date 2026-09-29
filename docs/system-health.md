# Runtime health checks

An installed version stamp does not prove a service is behaving correctly.
Run `./patch.sh status` to check the files, sensor, audio profile and running
services. `keyboard-backlight-auto` 1.3.0 also reports the daemon's lifetime CPU
average (100% means one CPU, not the whole machine).

## Keyboard backlight CPU usage

On 29 September 2026 an instance of the 1.2.0 daemon consumed roughly 86–88%
of one CPU. A three-second strace confirmed that a deleted virtual keyboard
(`/dev/input/event15`) returned `POLLERR|POLLHUP` and `ENODEV` continuously. The
loop ignored those errors and retained the dead fd.

Version 1.3.0 unregisters and closes disconnected devices, retries discovery
every five seconds, keeps normal sysfs `POLLPRI|POLLERR` notifications working,
and falls back to `/proc/acpi` if the lid input device goes away. Installing
the update restarts the daemon; `enable --now` alone did not replace a running
Python process.

```sh
./patch.sh install keyboard-backlight-auto
./patch.sh status keyboard-backlight-auto
python3 -m unittest discover -s tests -v
```

## Wi-Fi warnings: recent versus historical

`wifi-fix` 2.1.1 reports both the total missed-beacon warnings from this boot
and whether any occurred in the last fifteen minutes. Historical messages
remain in the journal. A working connection with no recent warnings does not
need a firmware downgrade or broad power-management changes merely to make
the boot's warning count zero. Check the actual link and disconnections:

```sh
iw dev wlan0 link
journalctl -k -b --since '-15 min' --no-pager
journalctl -b -u NetworkManager --since '-15 min' --no-pager
```

## Optional IR emitter and an OpenCV upgrade

`linux-enable-ir-emitter` and Howdy are separate from this repo's webcam
effects module. An old locally built IR-emitter binary can fail with missing
`libopencv_*.so.413` after OpenCV changes to 5.0 (`.so.500`). Confirm the ABI
failure rather than changing the camera firmware:

```sh
ldd /usr/bin/linux-enable-ir-emitter
journalctl -b -u linux-enable-ir-emitter --no-pager -n 20
pkg-config --list-all | grep opencv
```

Rebuild the installed AUR package against the installed libraries. For the
6.1.2 source and OpenCV 5, its `src/meson.build` dependency must be changed
from `opencv4` to `opencv5`; this machine's build and `--help` check passed.
Use a PKGBUILD `prepare()` patch so the change survives source extraction.
Install the rebuilt package through pacman, keep `/etc/linux-enable-ir-emitter`
intact, then restart the service. Do not symlink the incompatible old and new
OpenCV library names. The upstream [manual build instructions](https://github.com/EmixamPP/linux-enable-ir-emitter/blob/6.1.2/docs/manual-build.md)
describe the dependencies and Meson build.

A successful service run verifies that the loader and configured command work;
it does not verify face recognition or calibrate the emitter. Do not run
`configure` blindly: it asks the person in front of the camera to identify
which controls actually enable the emitter.

## GPU hotplug and touchpad logs

Check the current devices and recent errors before changing drivers based on
an earlier crash. Nouveau timeouts on a disconnected external NVIDIA GPU do
not imply a fault in the laptop's current Intel `xe` display. Likewise, a
couple of discarded libinput jumps are different from an I²C timeout flood.

```sh
lspci -nnk
libinput quirks list /dev/input/event10  # use the current touchpad event node
journalctl -k -b --since '-15 min' --no-pager
systemctl --failed
systemctl --user --failed
```

For recurring freezes, use the [B9406 desktop-freeze runbook](b9406-desktop-freeze.md).
An external GPU driver change needs the GPU model and an actual hotplug test;
an old journal entry alone cannot verify that the change fixed the incident.
