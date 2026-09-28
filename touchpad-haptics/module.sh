# shellcheck shell=bash
# touchpad-haptics module manifest.
#
# The B9406CAA's PixArt 093A:4F05 is a Windows Precision Touchpad pressure pad
# with haptic feedback. Windows (MyASUS) exposes its click force and haptic
# intensity; Linux has no UI for either. Both are standard HID feature
# reports, verified in this pad's own report descriptor:
#
#   report 8  Digitizer 0x0D / Button Press Threshold 0xB0, logical 1..3
#   report 9  Haptics 0x0E / Intensity 0x23, logical 0..100
#
# The firmware does not answer GET_FEATURE, so current values cannot be read
# back; it keeps them across suspend and forgets them at power-off.
#
# The module installs a small CLI (touchpad-haptics), a udev rule that tags
# the pad's hidraw node "uaccess" (the logged-in user can change the settings
# without root) and starts a oneshot service that restores the saved values
# from /etc/touchpad-haptics.conf whenever the node appears. The CLI writes
# only after matching HID_ID 0018:0000093A:00004F05 and the exact 964-byte
# report descriptor it was verified against.

MODULE_NAME="touchpad-haptics"
MODULE_DESC="B9406CAA haptic touchpad: click force and haptic intensity, restored at boot"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "touchpad-haptics:/usr/local/bin/touchpad-haptics"
  "touchpad-haptics-restore.service:/etc/systemd/system/touchpad-haptics-restore.service"
  "71-asus-b9406-touchpad-haptics.rules:/etc/udev/rules.d/71-asus-b9406-touchpad-haptics.rules"
  "touchpad-haptics.conf:/usr/share/touchpad-haptics/touchpad-haptics.conf"
)

_th_conf=/etc/touchpad-haptics.conf

module_post_install() {
  chmod 0755 /usr/local/bin/touchpad-haptics

  if [[ -e $_th_conf ]]; then
    echo "  keeping existing $_th_conf"
  else
    install -m 0644 /usr/share/touchpad-haptics/touchpad-haptics.conf "$_th_conf"
    echo "  seeded $_th_conf (everything commented out: firmware defaults)"
  fi

  systemctl daemon-reload
  udevadm control --reload
  # Re-evaluate hidraw nodes so the uaccess ACL applies without a reboot.
  udevadm trigger --action=change --subsystem-match=hidraw >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true

  echo
  echo "Try it (no root needed once the udev rule has applied):"
  echo "    touchpad-haptics set --click-force light --intensity 30"
  echo "Keep it across reboots:"
  echo "    sudo touchpad-haptics set --click-force light --intensity 30 --save"
}

module_post_uninstall() {
  systemctl daemon-reload
  udevadm control --reload
  udevadm trigger --action=change --subsystem-match=hidraw >/dev/null 2>&1 || true
  echo
  echo "  $_th_conf left in place. The pad keeps the current values until power-off."
}

module_status_extra() {
  local line
  [[ -x /usr/local/bin/touchpad-haptics ]] || return 0
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done < <(/usr/bin/python3 /usr/local/bin/touchpad-haptics status 2>&1)
}
