# B9406CAA SOF SoundWire DKMS overlay

This builds only the upstream `snd-soc-sof-sdw` machine driver and adds one
board-scoped workaround: on an ASUS B9406CAA, discard the firmware-described
RT722 endpoint when the SoundWire core reports that exact peripheral as
`SDW_SLAVE_UNATTACHED`.

The driver sources are derived from Linux `sound/soc/intel/boards/` at the
Linux 7.2 API level and remain GPL-2.0-only. Header copies retain their
original SPDX and copyright notices. `module.sh` registers this tree with
DKMS, which rebuilds the overlay whenever a kernel package is installed.

Stable updates can change the `soc_sdw_utils` API inside a release series:
Linux 7.2.8 backported the 7.3 `asoc_sdw_parse_sdw_endpoints(dev, ctx, ...)`
signature, and the 3.0.0 overlay stopped building there. The `Makefile` now
probes the target kernel's `include/sound/soc_sdw_utils.h` for that signature
instead of trusting the version number. `LLVM=1` is left to DKMS, which adds it
only for Clang-built kernels.
