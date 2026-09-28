# shellcheck shell=bash
# power-profile-bridge module manifest.
#
# Panther Lake registers two platform-profile handlers on this laptop: Intel's
# "SoC Power Slider" (low-power / balanced / performance) and asus-wmi
# (quiet / balanced / performance). The legacy
# /sys/firmware/acpi/platform_profile, which power-profiles-daemon 0.30
# drives, lists only the choices both share, balanced and performance. Its
# power-saver therefore writes "balanced": the SoC slider never reaches its
# most efficient setting and asus-wmi never selects the quiet fan mode. The
# kernel limitation is tracked upstream (asusctl#387); nothing pending fixes it.
#
# The bridge is a small root service that follows ActiveProfile over D-Bus and
# writes each handler's own /sys/class/platform-profile/*/profile:
#
#   power-saver  -> SoC Power Slider low-power, asus-wmi quiet
#   balanced     -> both balanced
#   performance  -> both performance
#
# power-profiles-daemon keeps managing EPP and stays the only thing KDE talks
# to. When the handlers disagree the legacy file reads "custom", which
# power-profiles-daemon 0.30 ignores (acpi_platform_profile_value_to_profile
# returns PPD_PROFILE_UNSET), so the two never fight. Because it may also skip
# a write it believes is already applied, the bridge sets every profile, not
# only power-saver, and re-applies after resume.

MODULE_NAME="power-profile-bridge"
MODULE_DESC="Power-saver reaches the SoC low-power slider and asus-wmi quiet fans"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "power-profile-bridge:/usr/local/bin/power-profile-bridge"
  "power-profile-bridge.service:/etc/systemd/system/power-profile-bridge.service"
  "power-profile-bridge.conf:/usr/share/power-profile-bridge/power-profile-bridge.conf"
)

_ppb_conf=/etc/power-profile-bridge.conf

module_post_install() {
  chmod 0755 /usr/local/bin/power-profile-bridge

  if [[ -e $_ppb_conf ]]; then
    echo "  keeping existing $_ppb_conf (template at /usr/share/power-profile-bridge/)"
  else
    install -m 0644 /usr/share/power-profile-bridge/power-profile-bridge.conf "$_ppb_conf"
    echo "  seeded $_ppb_conf"
  fi

  systemctl daemon-reload
  systemctl enable power-profile-bridge.service
  systemctl restart power-profile-bridge.service

  echo
  echo "Done. Switch profiles in the KDE battery applet and check with:"
  echo "    power-profile-bridge --status"
}

module_post_uninstall() {
  systemctl disable --now power-profile-bridge.service 2>/dev/null || true
  systemctl daemon-reload
  echo
  echo "  $_ppb_conf left in place (it may carry your edits). Remove with:"
  echo "    sudo rm $_ppb_conf"
}

module_status_extra() {
  local state line
  state="$(systemctl is-active power-profile-bridge.service 2>/dev/null || true)"
  case $state in
    active) printf '  service:  %sactive%s\n' "$c_ok" "$c_off" ;;
    *)      printf '  service:  %s%s%s\n' "$c_warn" "${state:-unknown}" "$c_off" ;;
  esac

  [[ -x /usr/local/bin/power-profile-bridge ]] || return 0
  while IFS= read -r line; do
    printf '  %s%s%s\n' "$c_dim" "$line" "$c_off"
  done < <(/usr/local/bin/power-profile-bridge --status 2>/dev/null)
}
