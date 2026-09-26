# B9406CAA desktop freeze

ASUS ExpertBook Ultra B9406CAA. Samsung eDP panel ATNA40LE01-0. Intel Arc
B390 (`8086:b080`). PixArt haptic touchpad `093A:4F05`, ACPI name
`ASCP1D80`, on `i2c_designware.0`.

Two different failures both end with a frozen desktop. Check which one you
have before changing boot parameters. A machine can have both.

Observed on Omarchy 4.0.4 with stock `linux 7.2.3-arch1-3`. The same touchpad
bus and the same panel exist on other distros. `linux-omarchy 7.2.5` was
installed on the machine that produced these logs and was not the kernel that
froze.

Search terms: `timeout waiting for bus ready`, `controller timed out`,
`timeout in disabling adapter`, `ASCP1D80`, `i915_flip`, `ISHTP`,
`xe.enable_panel_replay=0`, `SU_STANDBY`.

## Which failure is it?

```sh
ps -eo etimes,stat,pid,wchan:24,cmd | awk 'NR==1 || $2 ~ /^D/'
journalctl -k -b --no-pager | grep -E 'controller timed out|timeout in disabling adapter|timeout waiting for bus ready|ISHTP device' | tail -n 20
tr ' ' '\n' < /proc/cmdline | grep -E 'enable_psr|enable_panel_replay|enable_dpcd_backlight'
ls -l /etc/limine-entry-tool.d/*expertbook* /etc/limine-entry-tool.d/*b9406* /etc/modprobe.d/xe-dpcd-backlight.conf
```

### 1. Touchpad I2C wedge

The kernel log grows in this order:

```
i2c_designware i2c_designware.0: controller timed out
i2c_designware i2c_designware.0: timeout in disabling adapter
i2c_designware i2c_designware.0: timeout waiting for bus ready
```

The last line repeats about twenty times a second until reboot. The
`ASCP1D80` threaded IRQ and `kworker/*+i915_flip` sit in `D` state, so the
picture stops updating, not only the cursor. `hid-sensor-hub ... timeout
waiting for response from ISHTP device` can show up a few minutes earlier.

Three boots on linux 7.2.3 ended this way, each time only at the end of a
long session:

| Session | Flood started | `timeout waiting for bus ready` lines |
|---|---|---|
| 19 Sep 18:48 → 20 Sep 15:59 | 20 Sep 15:56 | 3935 |
| 20 Sep 16:00 → 22 Sep 09:58 | 22 Sep 09:33, 41 seconds after resume | 13382 |
| 22 Sep 21:11 → 25 Sep 19:14 | 25 Sep 19:01 | 14186 |

The boot from 15 Sep 19:59 to 18 Sep 20:31, the one immediately after Omarchy
4.0.4, logged none of these lines. These journals did not contain
`Timed out waiting PSR idle state` or a DSB timeout.

`i915_flip` in `D` by itself is not this bug. After the 25 Sep reboot, with
Panel Replay already disabled and with zero I2C timeouts, two `i915_flip`
workers still stayed in `D` for many minutes.

### 2. Panel Replay switches removed

`/proc/cmdline` is missing `xe.enable_panel_replay=0` or
`xe.enable_psr2_sel_fetch=0`.

Omarchy installs the first of those in
`/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf`
(`fix-asus-ptl-b9406-display.sh`, [omarchy#5423](https://github.com/omacom/omarchy/issues/5423)).
`display-fix` 1.3 archived that file to
`asus-expertbook-b9406-display.conf.disabled-by-asus-expertbook-linux` and
left only `xe.enable_dpcd_backlight=2`. Issue
[#7](https://github.com/burakgon/asus-expertbook-linux/issues/7) asked to try
dropping `xe.enable_psr=0` while keeping the other two. Version 1.3 dropped
all three.

`xe.enable_psr=0` does not disable Panel Replay. Turning Panel Replay off by
itself falls back to PSR2 selective fetch. On 25 Sep 2026, on an already
wedged boot, that fallback was seen parked in `SU_STANDBY` and the hitching
continued. That is why `xe.enable_psr2_sel_fetch=0` stays. It is not evidence
that `xe.enable_psr=0` should be the default.

## Recover the touchpad

While the session still accepts a command:

```sh
omarchy restart trackpad
```

On a distro without that command, rebind `i2c_hid_acpi`:

```sh
for dev in /sys/bus/i2c/drivers/i2c_hid_acpi/i2c-*; do
  name=$(basename "$dev")
  echo "$name" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
  sleep 1
  echo "$name" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
done
```

Then:

```sh
journalctl -k -b --since "30 seconds ago" --no-pager | grep -c 'timeout waiting for bus ready'
```

Zero new lines and a cursor that moves means this incident is over.

If the rebind hangs, or `irq/*-ASCP1D80` is already in `D`:

- Do not `rmmod` the touchpad, the GPU, or audio. The stuck thread does not
  release.
- Do not suspend. Resume is one of the observed starts of this wedge.
- Reboot. On Omarchy, with nothing stuck in `D`, run `omarchy system reboot`.
  With `i915_flip` or the touchpad IRQ stuck in `D`, a normal reboot can leave
  the last frame on screen until the machine actually powers off. Say that,
  then `systemctl reboot --force --no-wall`. If the session is already frozen
  solid, hold the power button.

Do not poll `acpitz` or ASUS `hwmon` fan and temperature nodes, and do not
read `/sys/kernel/b9406_fan_probe/snapshot`, from a status bar. Those ACPI
reads take the embedded controller and stall this I2C bus and the sensor hub.
The libinput pressure quirk (`touchpad-fix`) stops "Touch jump detected and
discarded". It does not prevent this wedge.

## Put the display switches back

`xe` loads from the initramfs, so `modprobe.d` alone does nothing on the next
boot. The parameters have to be on the kernel command line.

`/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf`:

```
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=2 xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0"
```

`/etc/modprobe.d/xe-dpcd-backlight.conf`, for a later reload of `xe` only:

```
options xe enable_dpcd_backlight=2 enable_panel_replay=0 enable_psr2_sel_fetch=0
```

If the Omarchy drop-in was archived, move it back:

```sh
archived=/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf.disabled-by-asus-expertbook-linux
live=/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf
sudo test -f "$archived" && sudo test ! -e "$live" && sudo mv "$archived" "$live"
sudo limine-update
```

Reboot with the rule in the previous section. Confirm after boot:

```sh
tr ' ' '\n' < /proc/cmdline | grep -E 'enable_panel_replay|enable_psr2_sel_fetch|enable_dpcd_backlight'
```

`display-fix` 1.4 does this and refuses to archive the Omarchy file again.
Until that version is what `./patch.sh` installs, running display-fix 1.3
strips the switches on the following boot.

## After an Omarchy update

Run the four commands at the top before deciding the update was clean. Omarchy
4.0.4 itself was followed by a three-day boot with no I2C flood. The failure
that comes back is display-fix 1.3, or another reinstall of this repo's older
display module, deleting Omarchy's `xe.enable_panel_replay=0` drop-in. The
touchpad wedge has also returned on its own after a day or two, including
immediately after resume, with no package update in that minute.

## Reports

- Omarchy: [omacom/omarchy#13274](https://github.com/omacom/omarchy/issues/13274)
- Display-fix 1.3 retirement: [asus-expertbook-linux#7](https://github.com/burakgon/asus-expertbook-linux/issues/7)
- Restore switches and this document: [asus-expertbook-linux#22](https://github.com/burakgon/asus-expertbook-linux/pull/22)
- Original Panel Replay stall, different bug (first frame never updates, fixed by `xe.enable_panel_replay=0` alone on an older kernel): [omacom/omarchy#5423](https://github.com/omacom/omarchy/issues/5423)
