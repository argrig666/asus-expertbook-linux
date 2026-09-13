# SPDX-License-Identifier: MIT
MODULE_NAME="mute-led-fix"
MODULE_DESC="F1 speaker and F4 microphone mute indicator LEDs"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "b9406-mute-led.conf:/etc/modules-load.d/b9406-mute-led.conf"
  "sync.py:/usr/local/lib/asus-expertbook/mute-led-sync.py"
  "expertbook-mute-leds.service:/etc/systemd/user/expertbook-mute-leds.service"
)

module_install() {
  if [[ $(cat /sys/class/dmi/id/product_name) != "ASUS EXPERTBOOK B9406CAA" ]]; then
    warn "[mute-led-fix] only tested on ASUS EXPERTBOOK B9406CAA; skipping"
    return 10
  fi

  local tool kernel source=/usr/src/b9406-mute-led-0.1
  kernel=$(uname -r)
  for tool in dkms make python3 pactl brightnessctl; do
    command -v "$tool" >/dev/null || {
      warn "[mute-led-fix] missing $tool; see mute-led-fix/README.md prerequisites"
      return 1
    }
  done
  [[ -f /lib/modules/$kernel/build/Makefile ]] || {
    warn "[mute-led-fix] install matching headers for $kernel first"
    return 1
  }
  if [[ -e /sys/class/leds/platform::mute && ! -d /sys/module/b9406_mute_led ]]; then
    warn "[mute-led-fix] a speaker LED already exists; use the sync service without this driver"
    return 10
  fi

  install -d "$source" || return
  install -m 644 "$MODULE_DIR"/dkms/b9406-mute-led-0.1/{b9406_mute_led.c,Makefile,dkms.conf} \
    "$source/" || return
  if [[ -z $(dkms status -m b9406-mute-led -v 0.1) ]]; then
    dkms add -m b9406-mute-led -v 0.1 || return
  fi
  dkms install -m b9406-mute-led -v 0.1 -k "$kernel" || return
  modprobe b9406_mute_led || return
  mod_install_files || return
  echo "  Driver loaded. As your desktop user (without sudo), run:"
  echo "    systemctl --user daemon-reload"
  echo "    systemctl --user enable --now expertbook-mute-leds.service"
  echo "  Disable any other mute-LED synchronizer first. No reboot required."
}

module_post_uninstall() {
  if command -v dkms >/dev/null && [[ -n $(dkms status -m b9406-mute-led -v 0.1) ]]; then
    dkms remove -m b9406-mute-led -v 0.1 --all || return
  fi
  rm -rf /usr/src/b9406-mute-led-0.1
  echo "  The loaded LED driver remains until the next reboot."
  echo "  As your desktop user: systemctl --user daemon-reload"
}

module_status_extra() {
  local led
  for led in platform::mute platform::micmute; do
    if [[ -r /sys/class/leds/$led/brightness ]]; then
      printf '  %s brightness: %s\n' "$led" "$(cat "/sys/class/leds/$led/brightness")"
    else
      printf '  %s: absent\n' "$led"
    fi
  done
  command -v dkms >/dev/null && dkms status -m b9406-mute-led -v 0.1
  echo "  Check sync as your desktop user: systemctl --user status expertbook-mute-leds"
}
