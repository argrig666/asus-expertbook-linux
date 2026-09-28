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

`patches/` holds a series on top of the 0.3.0 release:

```
0001-0007  upstream DisplayID 2.0 data-block and CTA-861 support
           (788c056 d535192 34b3635 4713505 7324cca 73ab82d 73ec53d)
0008       displayid2: don't read past the section after an oversized data block
0009       displayid2: don't leak data blocks when parsing fails
0010-0012  upstream hardening 0.3.0 predates (8057b29, 76f133a, cb5e3ed ported)
```

0001–0007 are backported unchanged apart from two test-data files that do not
exist in 0.3.0. 0008 and 0009 fix bugs those upstream commits carry and that
upstream main still has: a checksum-valid EDID with one oversized DisplayID 2.0
data block made the parser read past the end of the EDID buffer
(AddressSanitizer: heap-buffer-overflow), and a failing data block leaked the
blocks parsed before it. Both fixes apply to upstream main and pass its 69
tests there; they are drafted for upstream in
[`upstream-patches/`](../upstream-patches/). 0012 closes an out-of-bounds read
for VIC 220 that the packaged 0.3.0 library also has.

The public API only gains three functions and an enum, so the result keeps the
`.so.3` ABI: all 86 symbols of the packaged library are still exported
(unversioned, as before). Testing: upstream's 64 tests pass in a release and an
AddressSanitizer build, and 300,000 randomized, checksum-valid DisplayID 2.0
EDIDs parse under AddressSanitizer and UndefinedBehaviorSanitizer without an
error report. Two small leaks remain in 0.3.0's own CTA infoframe and speaker
location parsers on malformed input; the packaged library has them too.

Install:

1. refuses unless the system package is a release known to be built from the
   unmodified 0.3.0 tarball (Arch `0.3.0-1`, CachyOS `0.3.0-1.1`); any other
   release may carry distribution fixes the override would hide
   (`HDR_FIX_FORCE=1` overrides this after you have checked);
2. installs `meson`, `ninja`, `gcc`, `patch` and `hwdata` if missing;
3. downloads the 0.3.0 release tarball and checks its SHA-256 (the same pin as
   Arch's PKGBUILD);
4. applies the patches, builds the library and runs its own test suite (64
   EDID decode and print tests, including the expectation patch 0008
   corrects), stopping on any failure before anything is installed;
5. installs it in `/usr/local/lib/asus-expertbook-hdr/` and lists that
   directory in `/etc/ld.so.conf.d/asus-expertbook-hdr.conf`. The dynamic
   linker consults `ld.so.conf` directories before `/usr/lib`, so
   `libdisplay-info.so.3` resolves to the patched copy. No pacman-owned file is
   touched;
6. installs a pacman hook (`/etc/pacman.d/hooks/asus-expertbook-hdr.hook`)
   that removes the override as soon as the `libdisplay-info` package is
   upgraded, rebuilt, downgraded or removed, so a distribution fix is never
   shadowed. After that, KWin uses the packaged library from the next login;
   rerun the module if the toggle disappears and the new package still lacks
   the fix.

The upgrade to libdisplay-info 0.4.0 is such a package change, so the hook
retires the override then. KWin rebuilt against 0.4.0 links `.so.4`, which
reads DisplayID 2.0 itself, and would ignore the `.so.3` override anyway;
running the module again on 0.4.0 or newer only cleans up and changes nothing.

## Install

```sh
./patch.sh install hdr-fix
# log out and back in: KWin loads the library when it starts
./patch.sh status hdr-fix
```

```
  system:   libdisplay-info 0.3.0-1.1
  linker:   libdisplay-info.so.3 -> /usr/local/lib/asus-expertbook-hdr/libdisplay-info.so.3 (built for 0.3.0-1.1)
  panel:    PQ yes, BT.2020 yes, max 1600 cd/m² (as KWin reads it)
```

Then turn HDR on in System Settings > Display & Monitor.

## Uninstall

```sh
./patch.sh uninstall hdr-fix
```

Removes the library, the `ld.so.conf.d` entry and the pacman hook; log out and
back in.

## Notes

- `display-fix` pins self-refresh to PSR1, which keeps HDR colors correct
  across HDR toggles; Panel Replay lost the HDR colorimetry after every
  HDR-enabling modeset.
- `display-fix` also forces the VESA DPCD backlight (`xe.enable_dpcd_backlight=2`).
  Whether HDR brightness behaves better with Intel's own HDR backlight
  interface (`=3`) on this panel is untested.
- The durable fix is libdisplay-info 0.4.0 in the distribution with KWin
  rebuilt against it.
