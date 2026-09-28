# shellcheck shell=bash
# hdr-fix module manifest.
#
# KDE offers no HDR toggle for the B9406CAA's Samsung OLED, although the panel
# advertises HDR: its EDID carries an HDR Static Metadata block (PQ, max 1600,
# frame-average 702.5, min 0.0002 cd/m²) and BT.2020 RGB colorimetry. Both sit
# in a CTA-861 block embedded in a DisplayID 2.0 extension rather than in a
# classic CTA extension. KWin reads HDR capabilities through libdisplay-info,
# and 0.3.0 (what Arch and CachyOS ship) does not look inside DisplayID 2.0,
# so it reports PQ=0 and BT2020=0 for this panel. libdisplay-info 0.4.0 reads
# them (commit 73ec53d8 "info: search CTA blocks in DisplayID v2 extensions"),
# but it changes the soname to .so.4, so the distribution must rebuild KWin
# against it.
#
# patches/ holds a series on top of the 0.3.0 release:
#   0001-0007  the upstream commits that add DisplayID 2.0 data blocks and
#              CTA-861 support (788c056 d535192 34b3635 4713505 7324cca
#              73ab82d 73ec53d);
#   0008-0009  two fixes of our own for bugs those commits carry, still
#              present in upstream main: an out-of-bounds read after an
#              oversized DisplayID data block, and leaked data blocks when
#              parsing fails;
#   0010-0012  upstream hardening that 0.3.0 predates (8057b29, 76f133a, and
#              cb5e3ed ported to the 0.3.0 layout).
# The public API only gains three functions and an enum, so the result keeps
# the .so.3 ABI: every symbol of the packaged library is still exported,
# unversioned as before. Upstream's tests pass (64/64), also under
# AddressSanitizer, and 300,000 randomized DisplayID 2.0 EDIDs parse without
# a sanitizer report.
#
# Install downloads the pinned 0.3.0 release tarball (the SHA-256 Arch's
# PKGBUILD pins), applies the patches, builds it, installs it under
# /usr/local/lib/asus-expertbook-hdr and lists that directory in
# /etc/ld.so.conf.d, which the dynamic linker consults before /usr/lib. No
# pacman-owned file is touched. A pacman hook retires the override as soon as
# the libdisplay-info package changes in any way, so a distribution fix is
# never shadowed; the override is only built against package releases known
# to be the plain upstream 0.3.0 source.
#
# patch.sh calls module_install in a context where `set -e` does not apply,
# so every step that matters checks its own result.

MODULE_NAME="hdr-fix"
MODULE_DESC="Internal OLED HDR in KDE: libdisplay-info 0.3.0 with the upstream DisplayID 2.0 fix"
MODULE_VERSION="1.0.0"

MODULE_FILES=()

HDR_LDI_VERSION="0.3.0"
HDR_LDI_URL="https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/${HDR_LDI_VERSION}/downloads/libdisplay-info-${HDR_LDI_VERSION}.tar.xz"
HDR_LDI_SHA256="6ae77cd937f9cf7d1321d35c116062c4911e8447010a6a713ac4286f7a9d5987"
# Package releases built from the unmodified 0.3.0 tarball (Arch 0.3.0-1 and
# CachyOS's rebuild of it). Anything else may carry distribution patches the
# override would hide.
HDR_KNOWN_PACKAGES=("0.3.0-1" "0.3.0-1.1")
HDR_LIBDIR="/usr/local/lib/asus-expertbook-hdr"
HDR_LDCONF="/etc/ld.so.conf.d/asus-expertbook-hdr.conf"
HDR_STAMP="$HDR_LIBDIR/MODULE_VERSION"
HDR_BASE="$HDR_LIBDIR/BASE_PACKAGE"
HDR_HOOK="/etc/pacman.d/hooks/asus-expertbook-hdr.hook"
HDR_GUARD="/usr/local/lib/asus-expertbook-hdr-guard"

hdr_package() {
  pacman -Q libdisplay-info 2>/dev/null | awk '{print $2}'
}

hdr_system_version() {
  hdr_package | sed 's/^[0-9]*://; s/-[^-]*$//'
}

hdr_upstream_fixed() {
  local v
  v="$(hdr_system_version)"
  [[ -n $v ]] || return 1
  [[ "$(printf '%s\n%s\n' 0.4.0 "$v" | sort -V | head -n1)" == 0.4.0 ]]
}

hdr_known_package() {
  local p known
  p="$(hdr_package)"
  for known in "${HDR_KNOWN_PACKAGES[@]}"; do
    [[ $p == "$known" ]] && return 0
  done
  return 1
}

# Path the dynamic linker resolves libdisplay-info.so.3 to.
hdr_resolved() {
  ldconfig -p 2>/dev/null | awk '$1 == "libdisplay-info.so.3" {print $NF; exit}'
}

hdr_remove_override() {
  rm -f -- "$HDR_LDCONF"
  rm -rf -- "$HDR_LIBDIR"
  ldconfig
}

hdr_require_tools() {
  local missing=() tool pkg
  for tool in meson:meson ninja:ninja cc:gcc curl:curl patch:patch; do
    command -v "${tool%%:*}" >/dev/null 2>&1 || missing+=("${tool#*:}")
  done
  [[ -f /usr/share/hwdata/pnp.ids ]] || missing+=(hwdata)
  (( ${#missing[@]} > 0 )) || return 0
  command -v pacman >/dev/null 2>&1 || die "[hdr-fix] missing build tools: ${missing[*]}"
  log "[hdr-fix] installing build tools: ${missing[*]}"
  for pkg in "${missing[@]}"; do
    pacman -S --needed --noconfirm "$pkg" || die "[hdr-fix] could not install $pkg"
  done
}

module_install_state() {
  if hdr_upstream_fixed; then
    if [[ -e $HDR_LDCONF || -d $HDR_LIBDIR ]]; then
      echo update-available
    else
      echo up-to-date
    fi
  elif [[ -f $HDR_LIBDIR/libdisplay-info.so.3 && -f $HDR_LDCONF ]]; then
    if [[ "$(cat "$HDR_STAMP" 2>/dev/null)" != "$MODULE_VERSION" ||
          "$(cat "$HDR_BASE" 2>/dev/null)" != "$(hdr_package)" ||
          ! -f $HDR_HOOK || ! -x $HDR_GUARD ]]; then
      echo update-available
    else
      echo up-to-date
    fi
  elif [[ -e $HDR_LDCONF || -d $HDR_LIBDIR ]]; then
    echo partial
  else
    echo not-installed
  fi
}

module_install() {
  local tmp src p resolved

  if hdr_upstream_fixed; then
    if [[ -e $HDR_LDCONF || -d $HDR_LIBDIR ]]; then
      hdr_remove_override
      ok "[hdr-fix] removed the override: libdisplay-info $(hdr_system_version) has the fix itself"
    fi
    warn "[hdr-fix] system libdisplay-info $(hdr_system_version) already reads DisplayID 2.0; nothing to do"
    return 10
  fi

  if ! hdr_known_package && [[ ${HDR_FIX_FORCE:-0} != 1 ]]; then
    warn "[hdr-fix] libdisplay-info $(hdr_package || echo '(not installed)') is not a release known to be plain upstream $HDR_LDI_VERSION;"
    warn "[hdr-fix] it may carry distribution fixes the override would hide. Check it, then rerun with HDR_FIX_FORCE=1."
    return 10
  fi

  hdr_require_tools
  tmp="$(mktemp -d -t asus-hdr-fix.XXXXXXXX)" || die "[hdr-fix] mktemp failed"
  # shellcheck disable=SC2064 # expand now: $tmp is local to this function
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT

  log "[hdr-fix] downloading libdisplay-info $HDR_LDI_VERSION (pinned SHA-256)"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$tmp/src.tar.xz" "$HDR_LDI_URL" || die "[hdr-fix] download failed"
  [[ "$(sha256sum "$tmp/src.tar.xz" | awk '{print $1}')" == "$HDR_LDI_SHA256" ]] || \
    die "[hdr-fix] libdisplay-info tarball SHA-256 mismatch; refusing to build"
  tar -xf "$tmp/src.tar.xz" -C "$tmp" || die "[hdr-fix] could not unpack the tarball"
  src="$tmp/libdisplay-info-$HDR_LDI_VERSION"

  for p in "$MODULE_DIR"/patches/*.patch; do
    patch -d "$src" -p1 --forward --quiet <"$p" || die "[hdr-fix] ${p##*/} does not apply"
  done

  log "[hdr-fix] building"
  meson setup "$tmp/build" "$src" --buildtype=release -Ddefault_library=shared >/dev/null ||
    die "[hdr-fix] meson setup failed"
  ninja -C "$tmp/build" >/dev/null || die "[hdr-fix] build failed"
  [[ -f $tmp/build/libdisplay-info.so.$HDR_LDI_VERSION ]] || die "[hdr-fix] build produced no library"

  install -d -m 0755 "$HDR_LIBDIR" || die "[hdr-fix] cannot create $HDR_LIBDIR"
  install -m 0755 "$tmp/build/libdisplay-info.so.$HDR_LDI_VERSION" "$HDR_LIBDIR/" ||
    die "[hdr-fix] cannot install the library"
  ln -sfn "libdisplay-info.so.$HDR_LDI_VERSION" "$HDR_LIBDIR/libdisplay-info.so.3" ||
    die "[hdr-fix] cannot create the soname link"
  printf '%s\n' "$MODULE_VERSION" >"$HDR_STAMP" || die "[hdr-fix] cannot write $HDR_STAMP"
  printf '%s\n' "$(hdr_package)" >"$HDR_BASE" || die "[hdr-fix] cannot write $HDR_BASE"

  install -D -m 0755 "$MODULE_DIR/asus-expertbook-hdr-guard" "$HDR_GUARD" ||
    die "[hdr-fix] cannot install $HDR_GUARD"
  install -D -m 0644 "$MODULE_DIR/asus-expertbook-hdr.hook" "$HDR_HOOK" ||
    die "[hdr-fix] cannot install $HDR_HOOK"

  printf '# asus-expertbook-linux hdr-fix: libdisplay-info %s + DisplayID 2.0 CTA backport\n%s\n' \
    "$HDR_LDI_VERSION" "$HDR_LIBDIR" >"$HDR_LDCONF" || die "[hdr-fix] cannot write $HDR_LDCONF"
  ldconfig || die "[hdr-fix] ldconfig failed"

  resolved="$(hdr_resolved)"
  if [[ $resolved != "$HDR_LIBDIR/libdisplay-info.so.3" ]]; then
    hdr_remove_override
    die "[hdr-fix] libdisplay-info.so.3 resolves to ${resolved:-nothing}, not the override; removed it again"
  fi
  ok "[hdr-fix] libdisplay-info.so.3 now resolves to $resolved"
  echo "Log out and back in (KWin loads the library when it starts), then turn HDR on"
  echo "in System Settings > Display & Monitor."
}

module_post_uninstall() {
  hdr_remove_override
  rm -f -- "$HDR_HOOK" "$HDR_GUARD"
  echo "Removed the libdisplay-info override. Log out and back in to return KWin to"
  echo "the packaged library (no HDR toggle for the internal panel)."
}

module_status_extra() {
  local resolved running pid base
  printf '  system:   libdisplay-info %s\n' "$(hdr_package || echo '?')"
  resolved="$(hdr_resolved)"
  base="$(cat "$HDR_BASE" 2>/dev/null || true)"
  if [[ $resolved == "$HDR_LIBDIR/"* ]]; then
    printf '  linker:   %slibdisplay-info.so.3 -> %s (built for %s)%s\n' \
      "$c_ok" "$resolved" "${base:-?}" "$c_off"
  elif hdr_upstream_fixed; then
    printf '  linker:   %spackaged library has the fix; no override needed%s\n' "$c_ok" "$c_off"
  else
    printf '  linker:   %slibdisplay-info.so.3 -> %s (packaged, no DisplayID 2.0 HDR)%s\n' \
      "$c_warn" "${resolved:-?}" "$c_off"
  fi
  if [[ -d $HDR_LIBDIR && ! -f $HDR_HOOK ]]; then
    printf '  guard:    %spacman hook missing; reinstall hdr-fix%s\n' "$c_warn" "$c_off"
  fi

  pid="$(pgrep -x kwin_wayland 2>/dev/null | head -n1 || true)"
  if [[ -n $pid ]]; then
    running="$(grep -o '/[^ ]*libdisplay-info\.so[^ ]*' "/proc/$pid/maps" 2>/dev/null | head -n1 || true)"
    if [[ -n $running && -n $resolved && $running != "$(readlink -f "$resolved")" && $running != "$resolved" ]]; then
      printf '  kwin:     %sstill running %s; log out and back in%s\n' "$c_warn" "$running" "$c_off"
    elif [[ -n $running ]]; then
      printf '  kwin:     %s%s%s\n' "$c_dim" "$running" "$c_off"
    fi
  fi

  # What KWin will read from the panel through the library the linker picks.
  python3 - <<'PY' 2>/dev/null | sed 's/^/  /'
import ctypes, glob
lib = ctypes.CDLL("libdisplay-info.so.3")
class Hdr(ctypes.Structure):
    _fields_ = [("max", ctypes.c_float), ("avg", ctypes.c_float), ("min", ctypes.c_float),
                ("type1", ctypes.c_bool), ("sdr", ctypes.c_bool), ("hdr", ctypes.c_bool),
                ("pq", ctypes.c_bool), ("hlg", ctypes.c_bool)]
class Col(ctypes.Structure):
    _fields_ = [("bt2020_cycc", ctypes.c_bool), ("bt2020_ycc", ctypes.c_bool),
                ("bt2020_rgb", ctypes.c_bool), ("st2113_rgb", ctypes.c_bool), ("ictcp", ctypes.c_bool)]
lib.di_info_parse_edid.restype = ctypes.c_void_p
lib.di_info_parse_edid.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
lib.di_info_get_hdr_static_metadata.restype = ctypes.POINTER(Hdr)
lib.di_info_get_hdr_static_metadata.argtypes = [ctypes.c_void_p]
lib.di_info_get_supported_signal_colorimetry.restype = ctypes.POINTER(Col)
lib.di_info_get_supported_signal_colorimetry.argtypes = [ctypes.c_void_p]
lib.di_info_destroy.argtypes = [ctypes.c_void_p]
for path in sorted(glob.glob("/sys/class/drm/card*-eDP-*/edid")):
    data = open(path, "rb").read()
    if not data:
        continue
    buf = ctypes.create_string_buffer(data, len(data))
    info = lib.di_info_parse_edid(buf, len(data))
    if not info:
        print("panel:    EDID not parsable")
        continue
    h = lib.di_info_get_hdr_static_metadata(info).contents
    c = lib.di_info_get_supported_signal_colorimetry(info).contents
    yes = lambda b: "yes" if b else "no"
    print(f"panel:    PQ {yes(h.pq)}, BT.2020 {yes(c.bt2020_rgb)}, max {h.max:.0f} cd/m² (as KWin reads it)")
    lib.di_info_destroy(info)
PY
}
