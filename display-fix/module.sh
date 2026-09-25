# shellcheck shell=bash
# display-fix module manifest.
#
# Keep three xe parameters, on both the Limine cmdline and in modprobe.d.
# modprobe.d alone is NOT enough on this distro — xe loads from initramfs
# before /etc/modprobe.d is honoured — so the parameters have to land on the
# kernel cmdline. We install a managed limine-entry-tool drop-in and
# regenerate the Limine entries. `/etc/default/limine` is not used by current
# limine-mkinitcpio-hook releases.
#
#   xe.enable_dpcd_backlight=2    VESA AUX brightness (sysfs otherwise lies)
#   xe.enable_panel_replay=0      Omarchy's B9406 workaround; still required
#   xe.enable_psr2_sel_fetch=0    Panel Replay off falls back to PSR2 selective
#                                 fetch, which has parked this panel in SU_STANDBY
#
# Do not set xe.enable_psr=0. It does not cover Panel Replay (issue #7).
# Do not archive Omarchy's asus-expertbook-b9406-display.conf. Version 1.3
# did that, which stripped xe.enable_panel_replay=0 out from under Omarchy.
# Linux 7.2.3-arch1 boots without these two switches still hard-froze.

MODULE_NAME="display-fix"
MODULE_DESC="B9406CAA xe: DPCD brightness, Panel Replay and PSR2 selective fetch off"
MODULE_VERSION="1.4.0"

MODULE_FILES=(
  "xe-dpcd-backlight.conf:/etc/modprobe.d/xe-dpcd-backlight.conf"
  "limine-display.conf:/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf"
)

_df_remove_obsolete_files() {
  local old_modprobe="/etc/modprobe.d/xe-disable-psr.conf"
  local omarchy_limine="/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf"
  local archived="${omarchy_limine}.disabled-by-asus-expertbook-linux"

  # xe-disable-psr.conf forced xe.enable_psr=0. That switch does not cover
  # Panel Replay and is not part of this module.
  if [[ -f $old_modprobe ]]; then
    rm -- "$old_modprobe"
    log "[display-fix] removed obsolete PSR-disable file $old_modprobe"
  fi

  # Version 1.3 archived Omarchy's own Panel Replay drop-in. Put it back.
  # Our drop-in sets the same xe.enable_panel_replay=0, so both may coexist.
  if [[ -f $archived && ! -e $omarchy_limine ]]; then
    mv -- "$archived" "$omarchy_limine"
    log "[display-fix] restored Omarchy Panel Replay drop-in $omarchy_limine"
  fi
}

_df_remove_legacy_block() {
  local legacy="/etc/default/limine"
  local begin="# >>> asus-expertbook-linux display-fix >>>"
  local end="# <<< asus-expertbook-linux display-fix <<<"

  if [[ -f $legacy ]] && grep -qF "$begin" "$legacy" && \
     grep -qF "$end" "$legacy"; then
    sed -i "/^${begin}$/,/^${end}$/d" "$legacy"
    log "[display-fix] removed the obsolete managed block from $legacy"
  fi
}

_df_regen_limine() {
  if command -v limine-update >/dev/null 2>&1; then
    log "[display-fix] regenerating Limine entries"
    limine-update
  elif command -v limine-mkinitcpio >/dev/null 2>&1; then
    log "[display-fix] regenerating Limine initramfs entries"
    limine-mkinitcpio
  else
    die "[display-fix] Limine tooling not found; kernel parameters were not activated"
  fi
}

module_post_install() {
  _df_remove_legacy_block
  _df_remove_obsolete_files
  _df_regen_limine
  echo
  echo "Reboot to apply: VESA DPCD backlight, Panel Replay off, PSR2 selective fetch off."
}

module_post_uninstall() {
  _df_remove_legacy_block
  _df_remove_obsolete_files
  _df_regen_limine
  echo
  echo "Reboot to stop forcing the DPCD backlight interface and the Panel Replay / selective-fetch switches."
}

module_status_extra() {
  local backlight_value="" token

  local cmdline=""
  cmdline="$(tr '\n' ' ' </proc/cmdline 2>/dev/null || true)"
  if [[ $cmdline == *"xe.enable_panel_replay=0"* && $cmdline == *"xe.enable_psr2_sel_fetch=0"* ]]; then
    printf '  self-refresh:%s Panel Replay and PSR2 selective fetch disabled%s\n' \
      "$c_ok" "$c_off"
  else
    printf '  self-refresh:%s missing xe.enable_panel_replay=0 or xe.enable_psr2_sel_fetch=0 — reboot after install%s\n' \
      "$c_warn" "$c_off"
  fi

  while IFS= read -r token; do
    if [[ $token == xe.enable_dpcd_backlight=* ]]; then
      backlight_value="${token#*=}"
    fi
  done < <(tr ' ' '\n' </proc/cmdline 2>/dev/null)

  if [[ $backlight_value == 2 ]]; then
    printf '  backlight:%s xe.enable_dpcd_backlight=2 active (forced VESA interface)%s\n' \
      "$c_ok" "$c_off"
  elif [[ -n $backlight_value ]]; then
    printf '  backlight:%s effective xe.enable_dpcd_backlight=%s (expected 2)%s\n' \
      "$c_warn" "$backlight_value" "$c_off"
  elif [[ -f /etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf ]]; then
    printf '  backlight:%s DPCD fix staged — reboot to apply%s\n' "$c_warn" "$c_off"
  else
    printf '  backlight:%s xe.enable_dpcd_backlight=2 is not active%s\n' "$c_warn" "$c_off"
  fi

  if [[ -r /sys/kernel/debug/dri/0/i915_edp_psr_status ]]; then
    local mode
    mode="$(awk -F': ' '/^PSR mode:/ {print $2; exit}' /sys/kernel/debug/dri/0/i915_edp_psr_status 2>/dev/null)"
    if [[ -n "$mode" ]]; then
      case "$mode" in
        *"Panel Replay"*) printf '  panel:   %sPSR mode: %s%s\n' "$c_warn" "$mode" "$c_off" ;;
        *)                printf '  panel:   %sPSR mode: %s%s\n' "$c_ok" "$mode" "$c_off" ;;
      esac
    fi
  fi
}
