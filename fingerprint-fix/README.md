# ASUS ExpertBook Ultra (B9406CAA) — fingerprint reader fix on Linux

The ASUS ExpertBook Ultra B9406CAA features a **FocalTech FT9349 ESS** (`2808:a97a`) Match-on-Chip (MOC) press fingerprint sensor.

While upstream `libfprint >= 1.94.100` includes the `focaltech_moc` driver supporting device `2808:a97a`, the sensor does not work reliably out of the box on Linux due to USB autosuspend.

## Root Cause

1. Upstream systemd ships `/usr/lib/udev/hwdb.d/60-autosuspend-fingerprint-reader.hwdb`, which matches `usb:v2808pA97A*` and sets `ID_AUTOSUSPEND=1`.
2. After 2 seconds of inactivity, the kernel / udev autosuspends the device (`power/control=auto`, `power/runtime_status=suspended`).
3. When suspended, the hardware **does not wake up upon finger contact**. Touch and press events are silently dropped.
4. As a result, running `fprintd-enroll`, `fprintd-verify`, or PAM fingerprint authentication (`pam_fprintd.so`) appears completely hung until it times out.

> **Caution:** Do **not** attempt to wake the device by toggling USB `authorized` (0 → 1) or cycling driver binds. On the FT9349 controller, doing so wedges the controller firmware and can freeze kernel workers in uninterruptible sleep (`D`-state). If the controller becomes wedged, only a full power-off shutdown and cold boot restores it.

## Physical Location

The sensor is physically integrated into the **keyboard power button** (the top-right key with the embedded white LED bar). It is a **press** sensor (not a swipe sensor). It is not located on the touchpad or palmrest.

## Files

| File | Destination | Purpose |
|---|---|---|
| `61-fingerprint-no-autosuspend.hwdb` | `/etc/udev/hwdb.d/` | Overrides systemd's hwdb to set `ID_AUTOSUSPEND=0` |
| `61-fingerprint-no-autosuspend.rules` | `/etc/udev/rules.d/` | Sets `power/control="on"` and `power/persist="1"` |

## Installation

Using the repository patcher:

```sh
./patch.sh install fingerprint-fix
```

Or manually:

```sh
sudo cp 61-fingerprint-no-autosuspend.hwdb /etc/udev/hwdb.d/
sudo cp 61-fingerprint-no-autosuspend.rules /etc/udev/rules.d/
sudo systemd-hwdb update
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2808 --attr-match=idProduct=a97a
```

## Enrolling Fingerprints

Make sure `fprintd` and `libfprint` are installed:

```sh
sudo pacman -S --needed libfprint fprintd
```

Enroll your right index finger (press repeatedly on the **power button** when prompted):

```sh
fprintd-enroll -f right-index-finger "$USER"
```

Verify enrollment:

```sh
fprintd-verify -f right-index-finger "$USER"
```

## PAM Integration (Optional)

To use your fingerprint for `sudo`, add `pam_fprintd.so` to `/etc/pam.d/sudo`:

```pam
auth      sufficient pam_fprintd.so
```

If on a laptop with clamshell lid detection, precede it with a lid check so fingerprint authentication is skipped when the laptop lid is closed:

```pam
auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth      sufficient pam_fprintd.so
```
