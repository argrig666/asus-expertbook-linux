# intel-perf-fix module manifest.
#
# Userspace thermal management for Intel Panther Lake / Lunar Lake, plus an
# optional low-power-mode daemon:
#
#   thermald (extra repo)   Intel thermal daemon. Panther Lake support arrived
#                           in 2.5.9 and PTL is an "adaptive" platform: thermald
#                           runs the OEM's own thermal tables (Intel DTT
#                           emulation: PL1/PL2 limits, passive trips, a
#                           power-slider condition read from
#                           power-profiles-daemon). The kernel's int340x
#                           drivers expose the sensors and limits but do not run
#                           that policy. Installed and enabled by default.
#
#   intel-lpmd              Intel Low Power Mode Daemon. OPT-IN since 1.2.0:
#   (extra / cachyos repo)  install with INTEL_PERF_LPMD=1. In its low-power
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
#                           CPUs.
#
# Upgrading from 1.1.0, which enabled intel-lpmd unconditionally, disables
# intel_lpmd.service unless INTEL_PERF_LPMD=1 is set. A system where this module
# was never recorded as installed is left alone; status only reports it.
#
# This module ships no payload files; everything happens in the install hook
# (package installs + systemd unit enables). Empty MODULE_FILES is intentional
# and supported by patch.sh (mod_files_state treats empty as "all").

MODULE_NAME="intel-perf-fix"
MODULE_DESC="Panther Lake thermal daemon (thermald); intel-lpmd opt-in"
MODULE_VERSION="1.2.0"

MODULE_FILES=()

module_post_install() {
  local prev
  prev="$(mod_get_installed_version)"

  echo "  installing thermald (extra repo)"
  pacman -S --needed --noconfirm thermald 2>&1 | tail -3 || true

  echo "  enabling thermald.service"
  systemctl enable --now thermald.service 2>&1 | tail -1 || true

  echo
  if [[ ${INTEL_PERF_LPMD:-0} == 1 ]]; then
    echo "  installing intel-lpmd (INTEL_PERF_LPMD=1)"
    pacman -S --needed --noconfirm intel-lpmd 2>&1 | tail -3 || true
    echo "  enabling intel_lpmd.service"
    systemctl enable --now intel_lpmd.service 2>&1 | tail -1 || true
  elif [[ -n $prev ]] && systemctl is-enabled --quiet intel_lpmd.service 2>/dev/null; then
    systemctl disable --now intel_lpmd.service 2>/dev/null || true
    echo "  disabled intel_lpmd.service: intel-lpmd is opt-in since 1.2.0"
    echo "  (keep it with: sudo INTEL_PERF_LPMD=1 ./patch.sh install intel-perf-fix)"
  else
    echo "  intel-lpmd is opt-in; set INTEL_PERF_LPMD=1 to install and enable it"
  fi
}

module_post_uninstall() {
  echo "  disabling thermald.service"
  systemctl disable --now thermald.service 2>/dev/null || true

  if systemctl list-unit-files intel_lpmd.service >/dev/null 2>&1; then
    systemctl disable --now intel_lpmd.service 2>/dev/null && echo "  disabled intel_lpmd.service"
  fi

  echo
  echo "  Packages left installed (so revert is reversible without re-fetching)."
  echo "  Remove fully with:"
  echo "    sudo pacman -Rns thermald"
  echo "    sudo pacman -Rns intel-lpmd"
}

module_status_extra() {
  local s
  s="$(systemctl is-active thermald.service 2>/dev/null || true)"
  case "$s" in
    active) printf '  %-22s %sactive%s\n' thermald.service "$c_ok" "$c_off" ;;
    "")     ;;
    *)      printf '  %-22s %s%s%s\n' thermald.service "$c_warn" "$s" "$c_off" ;;
  esac

  if pacman -Q thermald >/dev/null 2>&1; then
    printf '  thermald pkg:          %s%s%s\n' "$c_ok" "$(pacman -Q thermald | awk '{print $2}')" "$c_off"
  else
    printf '  thermald pkg:          %snot installed%s\n' "$c_warn" "$c_off"
  fi

  if pacman -Q intel-lpmd >/dev/null 2>&1; then
    s="$(systemctl is-active intel_lpmd.service 2>/dev/null || true)"
    if [[ $s == active ]]; then
      printf '  intel_lpmd.service     %sactive (opt-in; %s)%s\n' "$c_dim" \
        "$(pacman -Q intel-lpmd | awk '{print $2}')" "$c_off"
    else
      printf '  intel_lpmd.service     %s%s (opt-in, off by default)%s\n' "$c_dim" "${s:-inactive}" "$c_off"
    fi
  fi
}
