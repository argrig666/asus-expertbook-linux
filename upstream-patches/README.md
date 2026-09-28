# Upstream status

Tracking and backport material for the ASUS ExpertBook Ultra B9406CAA: one fix
already in Linus' tree plus a stable-backport request for it, a display quirk
patch and issue draft, a libinput quirk, and a packaging request that would make
`hdr-fix` unnecessary. One proposed audio quirk turned out to be invalid.

Status rechecked on 2026-09-28 against `torvalds/linux` 7.3-rc5, the 7.2.8 and
6.18.54 stable releases and drm-intel-next `a8c17ccf`. Files meant for someone
else's tracker (`*.md`, `*.txt`) are drafts to be sent by the maintainer.

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
backports. It first ships in Linux 7.3 (present since 7.3-rc1) and is still
absent from 7.2.8 (rechecked 2026-09-28), so 7.2.y kernels need `audio-fix`'s
DKMS overlay unless their distributor backported the commit. The commit has no
`Cc: stable` tag, while the same fix for the GX651AX (`6d49beec658f`, with
`Cc: stable # 7.2.x`) reached 7.2.8.
[`stable-request-7.2-ghost-rt722.txt`](stable-request-7.2-ghost-rt722.txt) asks
for it and the Zenbook Duo and Zephyrus Duo quirks in 7.2.y; all three apply
cleanly, in order, to v7.2.8 (and 90af3209742d also to v6.18.54). `audio-fix` 3.1.1
checks the installed `soundwire_intel` module — the one that links
`dmi-quirks.o` — for the B9406CAA marker per kernel: it builds DKMS only for
kernels that lack the upstream quirk and removes the overlay once all installed
kernels have it. (3.1.0 inspected `soundwire_bus`, which never carries the
marker.)

## Pending or experimental

### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` →
  `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab merge request at
  <https://gitlab.freedesktop.org/libinput/libinput>
- **What it does:** marks the PixArt I2C-HID `093A:4F05` haptic touchpad as a
  pressure pad (`AttrInputProp=+INPUT_PROP_PRESSUREPAD`), exactly as upstream
  did for the sister pad `093A:4811`
  ([MR 1504](https://gitlab.freedesktop.org/libinput/libinput/-/merge_requests/1504),
  libinput 1.32.0). Applies to libinput 1.32.0 and passes
  `libinput quirks validate`.
- **Root cause:** the pad's report descriptor gives Tip Pressure no Logical
  Maximum of its own, so it inherits the Y field's 2601; the kernel sets
  `INPUT_PROP_PRESSUREPAD` itself only for pads reporting Button Type 1.
- **Status:** never submitted (no libinput MR or issue mentions 4F05). Send
  once the property has been confirmed on the device, with a
  `sudo libinput record` of normal use attached. Until then `touchpad-fix`
  keeps the proven `AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;` override.
- **Local replacement:** `touchpad-fix`'s block in `local-overrides.quirks`.

### `0001-drm-i915-display-Pin-ASUS-ExpertBook-Ultra-B9406CAA-to-PSR1.patch`

- **Tree:** drm-intel-next → `drivers/gpu/drm/i915/display/intel_quirks.c`
  (applies to `a8c17ccf`, 2026-09-23)
- **Where to send:** intel-gfx / intel-xe, with a drm/xe issue; the issue text
  is drafted in [`drm-xe-issue-b9406-psr1.md`](drm-xe-issue-b9406-psr1.md).
- **What it does:** adds this laptop to the two quirk tables upstream already
  has: `QUIRK_DISABLE_EDP_PANEL_REPLAY` (DPCD quirk, subsystem `1043:15e4` +
  sink OUI `00:aa:01`, the Dell XPS 14/16 pattern since 7.1) and
  `QUIRK_DISABLE_PSR2` (PCI quirk, `0xb080` / `1043:15e4`, the Xiaomi Book Pro
  14 pattern since 7.2). Panel Replay caps are then never read and PSR2 is
  never set up, which leaves PSR1, the same result as `display-fix`'s
  `xe.enable_panel_replay=0 xe.enable_psr=1`.
- **Status:** not sent. Tested only through the equivalent module parameters;
  the quirk entries still need one built-kernel test.
- **Local replacement:** `display-fix`.

The earlier version of this patch disabled Panel Replay alone, which on this
panel drops `xe` into PSR2 selective update over DSC and paints garbage. The
VSC SDP readout false positive that 7.2 logs on HDR modesets is fixed upstream
by `fd2e337ba66f` ("drm/i915/dp: Handle VSC SDP revision 7 in unpack", in
drm-intel-next for 7.4).

## Drafts for other trackers

- [`libdisplay-info-displayid2-oob.md`](libdisplay-info-displayid2-oob.md):
  a confidential report for libdisplay-info. Since 788c056, a checksum-valid
  EDID with one oversized DisplayID v2 data block makes the parser read past the
  end of the EDID buffer (reproduced with AddressSanitizer on main `62a9346`),
  and failing data blocks leak. `hdr-fix/patches/0008` and `0009` fix both, apply
  to main and pass its 69 tests.

- [`arch-libdisplay-info-0.4.0.md`](arch-libdisplay-info-0.4.0.md): asks Arch to
  ship libdisplay-info 0.4.0, which reads HDR metadata from DisplayID 2.0 and
  would make `hdr-fix` unnecessary.

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
