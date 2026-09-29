# intel-perf-fix module manifest.
#
# Userspace thermal management for Intel Panther Lake / Lunar Lake, plus an
# optional low-power-mode daemon:
#
#   thermald                Intel thermal daemon. Panther Lake support arrived
#                           in 2.5.9 and PTL is an "adaptive" platform: thermald
#                           runs the OEM's own thermal tables (Intel DTT
#                           emulation: PL1/PL2 limits, passive trips, a
#                           power-slider condition read from
#                           power-profiles-daemon). The kernel's int340x
#                           drivers expose the sensors and limits but do not run
#                           that policy. Installed and enabled by default.
#                           Arch: extra. Debian/Ubuntu: main.
#
#   intel-lpmd              Intel Low Power Mode Daemon. OPT-IN since 1.2.0:
#   (Arch: extra/cachyos;   install with INTEL_PERF_LPMD=1.
#    Ubuntu: universe) In its low-power
#                           mode it confines system/user/machine.slice to the
#                           four LP-E CPUs (not "a single LP-E core"), forces
#                           intel_pstate to active mode and moves the SoC power
#                           slider. On this no-SMT hybrid CPU the kernel already
#                           does capacity-aware scheduling ("Hybrid CPU capacity
#                           scaling enabled"), so lpmd's ITMT step is skipped
#                           ("Open .../sched_itmt_enabled failed" is harmless).
#                           Intel marks 0.1.1 (the CachyOS build) "test release,
#                           do not include in any distro release" and upstream
#                           main no longer changes cpusets by default. A public
#                           Panther Lake A/B test (XPS 16, battery, balanced)
#                           found no significant idle-power gain and roughly
#                           doubled app launch time with lpmd. Apps started
#                           while confined also size their thread pools to four
#                           CPUs. Ubuntu 24.04 packages 0.0.3 (February 2024),
#                           which predates Panther Lake and exits a few ms after
#                           starting; Debian has no package. The hook reports
#                           both instead of claiming success.
#
# Upgrading from 1.1.0, which enabled intel-lpmd unconditionally, disables
# intel_lpmd.service unless INTEL_PERF_LPMD=1 is set. A system where this module
# was never recorded as installed is left alone; status only reports it.
#
# This module ships no payload files; everything happens in the install hook
# (package installs + systemd unit enables). Empty MODULE_FILES is intentional
# and supported by patch.sh (mod_files_state treats empty as "all").
#
# Package and service calls go through lib/distro.sh, so the same hook works
# on pacman and apt systems; unit names are resolved at runtime.

MODULE_NAME="intel-perf-fix"
MODULE_DESC="Panther Lake thermal daemon (thermald); intel-lpmd opt-in"
MODULE_VERSION="1.3.0"

MODULE_FILES=()

_ipf_lpmd_unit() {
  svc_unit intel_lpmd.service intel-lpmd.service
}

module_post_install() {
  local prev unit
  prev="$(mod_get_installed_version)"

  # pipefail carries a package/service failure through tail.
  echo "  installing thermald"
  pkg_install thermald 2>&1 | tail -3 ||
    die "[intel-perf-fix] could not install thermald"

  unit="$(svc_unit thermald.service)"
  echo "  enabling $unit"
  svc_enable_now "$unit" 2>&1 | tail -1 ||
    die "[intel-perf-fix] could not enable $unit"
  svc_is_active "$unit" ||
    warn "[intel-perf-fix] $unit is enabled but not running; see: journalctl -u $unit"

  echo
  if [[ ${INTEL_PERF_LPMD:-0} == 1 ]]; then
    if ! pkg_installed intel-lpmd && ! pkg_available intel-lpmd; then
      warn "[intel-perf-fix] intel-lpmd is not packaged for this distribution; thermald alone stays"
      return 0
    fi
    echo "  installing intel-lpmd (INTEL_PERF_LPMD=1)"
    pkg_install intel-lpmd 2>&1 | tail -3 ||
      die "[intel-perf-fix] could not install intel-lpmd"
    unit="$(_ipf_lpmd_unit)"
    echo "  enabling $unit"
    svc_enable_now "$unit" 2>&1 | tail -1 ||
      die "[intel-perf-fix] could not enable $unit"
    # intel_lpmd exits at once, without logging why, on a CPU model it
    # predates (Ubuntu 24.04's 0.0.3 on Panther Lake).
    if ! svc_is_active "$unit"; then
      warn "[intel-perf-fix] $unit is enabled but not running"
      echo "  intel-lpmd $(pkg_version intel-lpmd) exits on CPU models it does not recognise;"
      echo "  Panther Lake needs a newer release. The unit stays enabled, so a later"
      echo "  package upgrade starts working without re-running this module."
    fi
  else
    unit="$(_ipf_lpmd_unit)"
    if [[ -n $prev ]] && svc_exists "$unit" && systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      if svc_disable_now "$unit"; then
        echo "  disabled $unit: intel-lpmd is opt-in since 1.2.0"
        echo "  (keep it with: sudo INTEL_PERF_LPMD=1 ./patch.sh install intel-perf-fix)"
      else
        warn "[intel-perf-fix] could not disable $unit"
      fi
    else
      echo "  intel-lpmd is opt-in; set INTEL_PERF_LPMD=1 to install and enable it"
    fi
  fi
}

module_post_uninstall() {
  local unit

  unit="$(svc_unit thermald.service)"
  echo "  disabling $unit"
  svc_disable_now "$unit" 2>/dev/null || true

  unit="$(_ipf_lpmd_unit)"
  if svc_exists "$unit" && svc_disable_now "$unit" 2>/dev/null; then
    echo "  disabled $unit"
  fi

  echo
  echo "  Packages left installed (so revert is reversible without re-fetching)."
  echo "  Remove fully with:"
  echo "    $(pkg_remove_hint thermald)"
  echo "    $(pkg_remove_hint intel-lpmd)"
}

module_status_extra() {
  local s svc version

  svc="$(svc_unit thermald.service)"
  if svc_exists "$svc"; then
    s="$(systemctl is-active "$svc" 2>/dev/null || true)"
    case "$s" in
      active) printf '  %-22s %sactive%s\n' "$svc" "$c_ok" "$c_off" ;;
      *)      printf '  %-22s %s%s%s\n' "$svc" "$c_warn" "${s:-unknown}" "$c_off" ;;
    esac
  fi

  version="$(pkg_version thermald)"
  if [[ -n $version ]]; then
    printf '  thermald pkg:          %s%s%s\n' "$c_ok" "$version" "$c_off"
  else
    printf '  thermald pkg:          %snot installed%s\n' "$c_warn" "$c_off"
  fi

  version="$(pkg_version intel-lpmd)"
  if [[ -n $version ]]; then
    svc="$(_ipf_lpmd_unit)"
    s="$(systemctl is-active "$svc" 2>/dev/null || true)"
    if [[ $s == active ]]; then
      printf '  %-22s %sactive (opt-in; %s)%s\n' "$svc" "$c_dim" "$version" "$c_off"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      printf '  %-22s %senabled but exits at startup (%s may predate this CPU)%s\n' \
        "$svc" "$c_warn" "$version" "$c_off"
    else
      printf '  %-22s %s%s (opt-in, off by default)%s\n' "$svc" "$c_dim" "${s:-inactive}" "$c_off"
    fi
  fi
}
