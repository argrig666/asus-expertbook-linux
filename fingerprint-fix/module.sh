# fingerprint-fix module manifest. Sourced by ../patch.sh.

MODULE_NAME="fingerprint-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) FocalTech FT9349 fingerprint autosuspend fix"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "61-fingerprint-no-autosuspend.hwdb:/etc/udev/hwdb.d/61-fingerprint-no-autosuspend.hwdb"
  "61-fingerprint-no-autosuspend.rules:/etc/udev/rules.d/61-fingerprint-no-autosuspend.rules"
)

module_post_install() {
  systemd-hwdb update >/dev/null 2>&1 || true
  udevadm control --reload >/dev/null 2>&1 || true
  udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2808 --attr-match=idProduct=a97a >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true

  echo "Autosuspend disabled for FocalTech FT9349 (2808:a97a)."
  echo "Sensor is integrated into the keyboard power button (top-right key)."
  echo "Enroll with: fprintd-enroll"
}

module_post_uninstall() {
  systemd-hwdb update >/dev/null 2>&1 || true
  udevadm control --reload >/dev/null 2>&1 || true
  udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2808 --attr-match=idProduct=a97a >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true

  echo "Reverted fingerprint autosuspend settings to defaults."
}

module_status_extra() {
  local dev="" pwr="" status="" d

  for d in /sys/bus/usb/devices/*; do
    if [[ -r "$d/idVendor" && -r "$d/idProduct" ]]; then
      if [[ "$(<"$d/idVendor")" == "2808" && "$(<"$d/idProduct")" == "a97a" ]]; then
        dev="$d"
        break
      fi
    fi
  done

  if [[ -z "$dev" ]]; then
    printf '  device:   %sno FocalTech FT9349 (2808:a97a) detected%s\n' "$c_warn" "$c_off"
    return 0
  fi
  printf '  device:   FocalTech FT9349 ESS (%s)\n' "$(basename "$dev")"

  if [[ -r "$dev/power/control" ]]; then
    pwr="$(<"$dev/power/control")"
    if [[ "$pwr" == "on" ]]; then
      printf '  power:    %scontrol=on (autosuspend disabled)%s\n' "$c_ok" "$c_off"
    else
      printf '  power:    %scontrol=%s (autosuspend active — presses will hang)%s\n' "$c_warn" "$pwr" "$c_off"
    fi
  fi

  if [[ -r "$dev/power/runtime_status" ]]; then
    status="$(<"$dev/power/runtime_status")"
    if [[ "$status" == "active" ]]; then
      printf '  status:   %sactive%s\n' "$c_ok" "$c_off"
    else
      printf '  status:   %s%s (device suspended)%s\n' "$c_warn" "$status" "$c_off"
    fi
  fi

  if command -v fprintd-list >/dev/null 2>&1; then
    local user="${SUDO_USER:-$USER}"
    local prints
    prints="$(fprintd-list "$user" 2>/dev/null || true)"
    if [[ "$prints" =~ (finger|#) ]]; then
      printf '  enrolled: %syes (%s)%s\n' "$c_ok" "$user" "$c_off"
    else
      printf '  enrolled: %snone for %s (run fprintd-enroll)%s\n' "$c_dim" "$user" "$c_off"
    fi
  fi
}
