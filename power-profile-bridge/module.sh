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
# power-profiles-daemon keeps managing EPP (its intel_pstate driver) and stays
# the only thing KDE talks to, but its platform_profile driver is switched off
# with a drop-in (--block-driver=platform_profile). Left on, it emulates
# power-saver by writing "balanced" to the legacy file and then reads its own
# write back as a request for balanced: going from performance to power-saver
# lands on balanced within a second, with or without the bridge. Its signal
# handler is blocked only during the write, while the file monitor event is
# delivered afterwards (ppd-driver-platform-profile.c, 0.30 and main). With the
# driver off, the bridge is the only writer of the platform profiles.

MODULE_NAME="power-profile-bridge"
MODULE_DESC="Power-saver reaches the SoC low-power slider and asus-wmi quiet fans"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "power-profile-bridge:/usr/local/bin/power-profile-bridge"
  "power-profile-bridge.service:/etc/systemd/system/power-profile-bridge.service"
  "power-profile-bridge.conf:/usr/share/power-profile-bridge/power-profile-bridge.conf"
)

_ppb_conf=/etc/power-profile-bridge.conf
_ppb_dropin=/etc/systemd/system/power-profiles-daemon.service.d/50-asus-expertbook-power-profile-bridge.conf
_ppb_bus=org.freedesktop.UPower.PowerProfiles
_ppb_obj=/org/freedesktop/UPower/PowerProfiles

# The daemon binary as its unit starts it (/usr/lib on Arch, /usr/libexec on
# other distributions).
_ppb_ppd_binary() {
  local p
  p="$(systemctl show -P ExecStart power-profiles-daemon.service 2>/dev/null |
    sed -n 's/^{ path=\([^ ;]*\) ;.*/\1/p')"
  [[ -n $p && -x $p ]] || return 1
  printf '%s\n' "$p"
}

# True when the daemon's effective command line blocks its platform driver
# (a later drop-in could still override ours).
_ppb_ppd_blocked() {
  systemctl show -P ExecStart power-profiles-daemon.service 2>/dev/null |
    grep -q -- '--block-driver=platform_profile'
}

_ppb_get_profile() {
  busctl get-property "$_ppb_bus" "$_ppb_obj" "$_ppb_bus" ActiveProfile 2>/dev/null |
    sed -n 's/^s "\(.*\)"$/\1/p'
}

# Restart power-profiles-daemon and keep the user's profile. The daemon does
# not restore its saved profile when its set of drivers changed, so it comes
# back on balanced once after the drop-in appears or goes away.
_ppb_restart_ppd() {
  local prev
  systemctl is-active --quiet power-profiles-daemon.service || return 0
  prev="$(_ppb_get_profile)"
  systemctl restart power-profiles-daemon.service ||
    die "[power-profile-bridge] power-profiles-daemon did not restart"
  if [[ -n $prev && $(_ppb_get_profile) != "$prev" ]]; then
    busctl set-property "$_ppb_bus" "$_ppb_obj" "$_ppb_bus" ActiveProfile s "$prev" ||
      warn "[power-profile-bridge] could not switch back to $prev; pick it again in the battery applet"
  fi
}

_ppb_install_dropin() {
  local ppd content
  if ! ppd="$(_ppb_ppd_binary)"; then
    warn "[power-profile-bridge] power-profiles-daemon.service not found; the bridge follows whatever"
    warn "[power-profile-bridge] provides org.freedesktop.UPower.PowerProfiles, if anything"
    return 0
  fi
  if ! "$ppd" --help-all 2>/dev/null | grep -q -- --block-driver; then
    warn "[power-profile-bridge] $ppd has no --block-driver option: switching from performance"
    warn "[power-profile-bridge] straight to power-saver will still fall back to balanced"
    return 0
  fi
  content="# Installed by asus-expertbook-linux (power-profile-bridge).
# power-profile-bridge writes every platform-profile handler itself. The
# daemon's platform_profile driver would emulate power-saver by writing
# \"balanced\" and then read that write back as a switch to balanced, so only
# its CPU (EPP) driver stays on.
[Service]
ExecStart=
ExecStart=$ppd --block-driver=platform_profile"
  if [[ -f $_ppb_dropin && "$(cat "$_ppb_dropin")" == "$content" ]]; then
    return 0
  fi
  install -d -m 0755 "${_ppb_dropin%/*}" || die "[power-profile-bridge] cannot create ${_ppb_dropin%/*}"
  printf '%s\n' "$content" >"$_ppb_dropin" || die "[power-profile-bridge] cannot write $_ppb_dropin"
  log "[power-profile-bridge] power-profiles-daemon: platform_profile driver off ($_ppb_dropin)"
  systemctl daemon-reload
  _ppb_ppd_blocked ||
    warn "[power-profile-bridge] another drop-in overrides ExecStart of power-profiles-daemon; add --block-driver=platform_profile there"
  _ppb_restart_ppd
}

_ppb_remove_dropin() {
  [[ -e $_ppb_dropin ]] || return 0
  rm -f -- "$_ppb_dropin"
  rmdir --ignore-fail-on-non-empty -- "${_ppb_dropin%/*}" 2>/dev/null || true
  systemctl daemon-reload
  _ppb_restart_ppd
  log "[power-profile-bridge] power-profiles-daemon drives platform_profile again"
}

module_post_install() {
  chmod 0755 /usr/local/bin/power-profile-bridge

  if [[ -e $_ppb_conf ]]; then
    echo "  keeping existing $_ppb_conf (template at /usr/share/power-profile-bridge/)"
  else
    install -m 0644 /usr/share/power-profile-bridge/power-profile-bridge.conf "$_ppb_conf"
    echo "  seeded $_ppb_conf"
  fi

  _ppb_install_dropin
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
  _ppb_remove_dropin
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
  if _ppb_ppd_blocked; then
    printf '  ppd:      %splatform_profile driver off%s\n' "$c_ok" "$c_off"
  else
    printf '  ppd:      %splatform_profile driver on: performance -> power-saver falls back to balanced%s\n' \
      "$c_warn" "$c_off"
  fi

  [[ -x /usr/local/bin/power-profile-bridge ]] || return 0
  while IFS= read -r line; do
    printf '  %s%s%s\n' "$c_dim" "$line" "$c_off"
  done < <(/usr/local/bin/power-profile-bridge --status 2>/dev/null)
}
