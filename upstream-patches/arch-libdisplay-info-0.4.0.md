# Draft: Arch packaging request — libdisplay-info 0.4.0

File at <https://gitlab.archlinux.org/archlinux/packaging/packages/libdisplay-info/-/issues>
(CachyOS rebuilds follow Arch).

---

**Title:** Update to 0.4.0: KWin cannot see HDR on panels that describe it in DisplayID 2.0

libdisplay-info 0.4.0 (released 2026-07-23) includes `73ec53d8` "info: search
CTA blocks in DisplayID v2 extensions". Several current OLED laptop panels put
their HDR Static Metadata and colorimetry blocks inside a CTA-861 block in a
DisplayID 2.0 extension instead of a classic CTA extension. With 0.3.0,
`di_info_get_hdr_static_metadata()` reports no PQ and no BT.2020 for them, so
KWin offers no HDR option.

Example, ASUS ExpertBook Ultra B9406CAA (Samsung ATNA40LE01), parsing the
panel's own EDID:

| | PQ | BT.2020 RGB | Max luminance |
|---|---|---|---|
| libdisplay-info 0.3.0 | no | no | – |
| libdisplay-info 0.4.0 | yes | yes | 1600 cd/m² |

KDE forum report of the same class of panel:
<https://discuss.kde.org/t/hdr-not-activating-on-asus-vivobook-oled-despite-correct-edid-displayid-hdr-support/48824>.

0.4.0 bumps the soname to `libdisplay-info.so.4`, so kwin, mutter, wlroots and
the other reverse dependencies need a rebuild with the update.
