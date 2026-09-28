# hdr-fix

Gives KDE an HDR toggle for the internal Samsung OLED of the ASUS ExpertBook
Ultra (B9406CAA).

## The problem

KDE's Display & Monitor settings show no HDR option for the internal panel,
and forcing it with `KWIN_FORCE_ASSUME_HDR_SUPPORT=1` gives washed-out colors.
The panel does advertise HDR. Its EDID carries an HDR Static Metadata block
and BT.2020 RGB colorimetry, but inside a CTA-861 block embedded in a
**DisplayID 2.0** extension, not in a classic CTA extension:

| | PQ (ST 2084) | BT.2020 RGB | Max luminance |
|---|---|---|---|
| libdisplay-info 0.3.0 (Arch/CachyOS today) | no | no | – |
| 0.3.0 + this backport | **yes** | **yes** | **1600 cd/m²** (avg 702.5, min 0.0002) |

KWin reads those capabilities through libdisplay-info. Version 0.4.0 looks
inside DisplayID 2.0
(`73ec53d8` "info: search CTA blocks in DisplayID v2 extensions"), but it
changes the soname to `.so.4`, so KWin has to be rebuilt against it and the
distributions still ship 0.3.0.

## What the module does

`patches/` holds the seven upstream commits that add DisplayID 2.0 data-block
and CTA-861 support, backported onto 0.3.0 unchanged apart from two test-data
files that do not exist in 0.3.0:

```
0001 displayid2: decode data blocks structure
0002 cta: introduce struct di_cta
0003 cta: make di_cta.flags optional
0004 cta: expose _di_cta_data_block_{parse,destroy}
0005 displayid2: add support for CTA-861 data blocks
0006 info: don't use di_ prefix for static helpers
0007 info: search CTA blocks in DisplayID v2 extensions
```

The public API only gains three functions and an enum, so the result keeps the
`.so.3` ABI: all 86 symbols of the packaged library are still exported
(unversioned, as before) and upstream's test suite passes 64/64.

Install:

1. refuses unless the system package is exactly `libdisplay-info 0.3.0`;
2. installs `meson`, `ninja`, `gcc`, `patch` and `hwdata` if missing;
3. downloads the 0.3.0 release tarball and checks its SHA-256 (the same pin as
   Arch's PKGBUILD);
4. applies the patches and builds the library;
5. installs it in `/usr/local/lib/asus-expertbook-hdr/` and lists that
   directory in `/etc/ld.so.conf.d/asus-expertbook-hdr.conf`. The dynamic
   linker consults `ld.so.conf` directories before `/usr/lib`, so
   `libdisplay-info.so.3` resolves to the patched copy. No pacman-owned file
   is touched.

Once the system package is 0.4.0 or newer, reinstalling the module removes the
override again: KWin then links `.so.4`, which has the fix.

## Install

```sh
./patch.sh install hdr-fix
# log out and back in: KWin loads the library when it starts
./patch.sh status hdr-fix
```

```
  system:   libdisplay-info 0.3.0
  linker:   libdisplay-info.so.3 -> /usr/local/lib/asus-expertbook-hdr/libdisplay-info.so.3
  panel:    PQ yes, BT.2020 yes, max 1600 cd/m² (as KWin reads it)
```

Then turn HDR on in System Settings > Display & Monitor.

## Uninstall

```sh
./patch.sh uninstall hdr-fix
```

Removes the library and the `ld.so.conf.d` entry; log out and back in.

## Notes

- `display-fix` pins self-refresh to PSR1, which keeps HDR colors correct
  across HDR toggles; Panel Replay lost the HDR colorimetry after every
  HDR-enabling modeset.
- `display-fix` also forces the VESA DPCD backlight (`xe.enable_dpcd_backlight=2`).
  Whether HDR brightness behaves better with Intel's own HDR backlight
  interface (`=3`) on this panel is untested.
- The durable fix is libdisplay-info 0.4.0 in the distribution with KWin
  rebuilt against it.
