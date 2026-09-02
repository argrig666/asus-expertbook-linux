# Upstream status

Tracking and backport material for the ASUS ExpertBook Ultra B9406CAA. This
directory no longer describes every file as a submission candidate: one fix is
already in Linus' tree, one proposed audio quirk was invalid, and the display
quirk turned out to pick the wrong self-refresh mode for this panel.

Status checked against `torvalds/linux` and the released Linux 7.2.1 sources on
2026-08-28; the display status was revised on 2026-09-01 after the Linux 7.2
retest.

## Accepted upstream

### `0004-soundwire-dmi-quirks-Disable-ghost-rt722-on-ASUS-Exp.patch`

- **Upstream commit:**
  [`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8)
- **Tree:** `torvalds/linux` → `drivers/soundwire/dmi-quirks.c`
- **Author:** Charles Keepax, Cirrus Logic
- **Tracking issue:** [thesofproject/linux#5828](https://github.com/thesofproject/linux/issues/5828)
- **What it does:** matches ASUS board `B9406CAA` and applies the existing
  `ghost_realtek` address remap, causing SoundWire to discard the unfitted
  RT722 endpoint before the SOF machine driver builds duplicate DAI links.

The file here is the exact upstream commit patch, retained for distro/stable
backports. It landed after Linux 7.2, and is absent from 7.2.1, so released
kernels still need `audio-fix`'s DKMS overlay unless their distributor
backported the commit. `audio-fix` 3.1 checks the installed `soundwire_bus`
module for the B9406CAA marker per kernel: it builds DKMS only for kernels that
lack the upstream quirk and removes the overlay once all installed kernels have
it.

## Pending or experimental

### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` →
  `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab merge request at
  <https://gitlab.freedesktop.org/libinput/libinput>
- **What it does:** disables `ABS_MT_PRESSURE` / `ABS_PRESSURE` for the PixArt
  I2C-HID `093A:4F05` haptic touchpad.
- **Local replacement:** `touchpad-fix`'s `local-overrides.quirks`.

### `0001-drm-i915-Add-Panel-Replay-quirk-for-ASUS-ExpertBook-.patch`

Not submission-ready, and no longer the right fix. The patch quirks off Panel
Replay for this sink OUI, which on Linux 7.2 drops `xe` into PSR2 selective
update over the panel's DSC link, and that mode paints red/green garbage on
every screen update (most plausibly because the driver gates PSR2 + DSC on
platform generation only, while this panel advertises DSC selective update for
Panel Replay alone). The mode that works is PSR1, which `display-fix` 1.4
selects with `xe.enable_panel_replay=0 xe.enable_psr=1`: Panel Replay itself
loses the panel's HDR colorimetry after every HDR-enabling modeset (washed out
colors until something streams frames with the SDPs again) and leaves stale
content on screen, with or without Early Transport. An upstreamable equivalent
would be a per-panel quirk that forces PSR1 by disabling both Panel Replay and
PSR2, which neither `intel_quirks.c` nor the `drm_dp_dpcd_quirk` table has yet
(`DP_DPCD_QUIRK_NO_PSR` is the closest). That work, together with a root cause
for the colorimetry loss, is tracked out of tree.

Related and already fixed: the `mismatch in vsc dp vsc sdp` error and
`intel_modeset_verify.c` WARN that 7.2 logs on every HDR modeset with Panel
Replay are a readout false positive (`intel_dp_vsc_sdp_unpack()` rejects the
revision 7 VSC packet the driver itself emits for Panel Replay with
colorimetry). Kernel commit `e2cb54fbe4c3` ("drm/i915/dp: Fix VSC SDP readout
for Panel Replay with colorimetry") fixes it in Sultan Alsawaf's tree; upstream
submission is pending.

## Retired: the former `0002` sidecar-amplifier patch

The old patch added `SOC_SDW_SIDECAR_AMPS` for PCI subsystem `1043:15e4`.
It has been removed because this B9406CAA is not a SoundWire sidecar-amplifier
design. Upstream Cirrus analysis in
[SOF issue #5828](https://github.com/thesofproject/linux/issues/5828) identified
the firmware-described ghost RT722 as the kernel failure and warned that the
sidecar flag would produce the wrong component/UCM description.

No kernel SSID quirk is needed for the speaker routing:

- the permanent kernel fix is the accepted SoundWire DMI quirk above;
- the combined CS42L43 + CS35L56 UCM is already shipped by
  `alsa-ucm-conf >= 1.2.16`;
- the `1043:15e4` CS35L56 tuning is already shipped by current
  `linux-firmware-cirrus`.

## Hardware identifiers

| Field | Value |
|---|---|
| PCI audio subsystem | `1043:15e4` |
| eDP panel sink IEEE OUI | `00:aa:01` |
| EDID manufacturer / product | `SDC` / `0x4217` |
| DMI sys vendor / board | `ASUS` / `B9406CAA` |
| Touchpad | `093A:4F05` (ACPI `ASCP1D80`) |

## Verification

```sh
./patch.sh status audio-fix
./patch.sh status display-fix
cat /proc/asound/cards
journalctl -k -b | grep -Ei 'sof|soundwire|cs35|cs42|PSR|DSB|pageflip'
```

For kernels with the accepted SoundWire commit, `audio-fix` reports
`upstream B9406CAA ghost-RT722 quirk active` and no current-kernel DKMS module
is expected. On older kernels it reports the board-scoped DKMS overlay.
