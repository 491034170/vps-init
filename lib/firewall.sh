# lib/firewall.sh — sensible UFW defaults for a web VPS.
# shellcheck shell=bash

vi_cmd_firewall() {
  vi_step "UFW firewall"

  # Install if missing.
  vi_apt_install ufw

  # Detect the current SSH port from sshd_config (fall back to 22).
  local ssh_port="22"
  if [[ -f /etc/ssh/sshd_config ]]; then
    local p
    p=$(awk '/^Port[[:space:]]+/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null || echo "")
    [[ -n "$p" ]] && ssh_port="$p"
  fi

  # Defaults first (idempotent; ufw no-ops if already matching).
  vi_run ufw --force default deny incoming
  vi_run ufw --force default allow outgoing

  # Allow SSH on the actual port (critical to do before enabling!).
  vi_run ufw allow "$ssh_port/tcp" comment 'SSH'

  # Allow HTTP / HTTPS for nginx.
  vi_run ufw allow 80/tcp comment 'HTTP'
  vi_run ufw allow 443/tcp comment 'HTTPS'

  # Bring it up. --force skips the interactive "ARE YOU SURE" prompt.
  vi_run ufw --force enable

  # Print a summary so the operator can eyeball it.
  if [[ "${VI_DRY_RUN:-0}" == "0" ]]; then
    ufw status verbose >&2 || true
  fi

  vi_ok "firewall active (ssh:$ssh_port, 80, 443 open)"
}
