# lib/timezone.sh — set system timezone + basic NTP sanity.
# shellcheck shell=bash

vi_cmd_timezone() {
  local tz="${1:-Asia/Shanghai}"

  if [[ ! -f "/usr/share/zoneinfo/$tz" ]]; then
    vi_err "unknown timezone: $tz"
    return 2
  fi

  vi_step "Timezone"
  local current
  current=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
  if [[ "$current" == "$tz" ]]; then
    vi_info "already $tz"
  else
    vi_info "$current -> $tz"
    vi_run timedatectl set-timezone "$tz"
  fi

  # Ensure systemd-timesyncd or chrony is running so clock stays accurate.
  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-timesyncd'; then
    vi_run systemctl enable --now systemd-timesyncd
  elif command -v chronyc >/dev/null 2>&1; then
    vi_run systemctl enable --now chrony || true
  fi

  vi_ok "timezone: $tz"
}
