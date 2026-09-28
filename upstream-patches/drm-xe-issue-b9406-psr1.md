# Draft: drm/xe issue — pin ASUS ExpertBook Ultra B9406CAA to PSR1

File at <https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/new>, attach the
logs listed at the end, and link the patch in
`0001-drm-i915-display-Pin-ASUS-ExpertBook-Ultra-B9406CAA-to-PSR1.patch`.

---

**Title:** PTL: ASUS ExpertBook Ultra B9406CAA (Samsung ATNA40LE01) needs Panel Replay and PSR2 disabled — quirk request

**Hardware**

- ASUS ExpertBook Ultra B9406CAA, BIOS 312, Core Ultra X7 358H (Panther Lake), Arc B390 `8086:b080`
- PCI subsystem `1043:15e4`
- eDP: Samsung ATNA40LE01 OLED, sink OUI `00:aa:01`, EDID `SDC 0x4217`, DSC link
- Sink capabilities: `PSR = yes [0x03], Panel Replay = yes, Panel Replay Selective Update = yes, Panel Replay DSC support = selective update (Early Transport)`

**Problem**

With the default mode, Panel Replay Selective Update with Early Transport:

- 7.2.0: `Timed out waiting PSR idle state`, `[CRTC:151:pipe A] DSB 0 poll error`,
  `CPU pipe A FIFO underrun`, with corruption on screen.
- 7.2.4: flicker; with VRR enabled the picture smears.
- 7.2.2: after every HDR-enabling modeset the panel is desaturated and stale
  content lingers; a write to `i915_edp_psr_debug` or a KWin color-accuracy
  toggle restores the colors. Dropping only Early Transport keeps the washed
  out colors and slows the cursor to ~20 fps.

Runtime ladder through `i915_edp_psr_debug` on 7.2.2:

| Value | Mode | Result |
|---|---|---|
| `0` | Panel Replay + SU + ET | desaturated after HDR toggle, stale frames |
| `0x40` | Panel Replay off → PSR2 + selective fetch over DSC | red/green speckle garbage on every update |
| `0x20` | Panel Replay + SU without ET | still washed out, ~20 fps cursor |
| `0x43` | PSR1 | clean: vivid across HDR toggles, smooth cursor, no stale frames |

`xe.enable_psr2_sel_fetch=0` alone keeps Panel Replay without SU and freezes
the panel on the boot console text.

**Workaround in use**

`xe.enable_panel_replay=0 xe.enable_psr=1` (several owners run the equivalent
`xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0`), both of which leave
PSR1. Reports: <https://github.com/burakgon/asus-expertbook-linux/issues/7>.

**Request**

Add this machine to the two existing quirk tables, which together leave PSR1:
`QUIRK_DISABLE_EDP_PANEL_REPLAY` for subsystem `1043:15e4` + sink OUI
`00:aa:01`, and `QUIRK_DISABLE_PSR2` for `0xb080` / `1043:15e4`. Patch
attached (applies to drm-intel-next `a8c17ccf`).

**Logs to attach**

```sh
# boot once with drm.debug=0xe on the kernel cmdline and without the xe.* PSR options, then:
journalctl -k -b > dmesg-drm-debug.txt
sudo cat /sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_psr_status > psr-status.txt
sudo cat /sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_dpcd > dpcd.txt 2>/dev/null
cat /sys/class/drm/card0-eDP-1/edid > edid.bin
```
