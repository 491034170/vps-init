# lib/swap.sh — add a swap file if one is not already active.
# shellcheck shell=bash

vi_cmd_swap() {
  local size="${1:-2G}"
  local path="${2:-/swapfile}"

  # Normalize: accept 2G, 2048M, 2048 (MB implied) — convert to MB for fallocate.
  local size_mb
  case "$size" in
    *G|*g) size_mb=$(( ${size%[Gg]} * 1024 )) ;;
    *M|*m) size_mb=${size%[Mm]} ;;
    *)     size_mb="$size" ;;
  esac

  if [[ ! "$size_mb" =~ ^[0-9]+$ ]] || [[ $size_mb -lt 256 ]]; then
    vi_err "bad swap size: $size (want e.g. 1G, 2G, 4G; minimum 256M)"
    return 2
  fi

  vi_step "Swap file"

  # Skip if we already have non-trivial swap enabled.
  local current
  current=$(awk 'NR==2 {print $3}' /proc/swaps 2>/dev/null || echo 0)
  if [[ "${current:-0}" -gt 0 ]]; then
    vi_info "swap already active: $((current / 1024)) MB — nothing to do"
    return 0
  fi

  if [[ -e "$path" ]]; then
    vi_warn "$path already exists but is not active; refusing to overwrite"
    return 1
  fi

  vi_info "creating $path ($size_mb MB)"
  vi_run fallocate -l "${size_mb}M" "$path"
  vi_run chmod 600 "$path"
  vi_run mkswap "$path"
  vi_run swapon "$path"

  # Add to fstab idempotently.
  if ! grep -qE "^${path}[[:space:]]" /etc/fstab 2>/dev/null; then
    vi_run bash -c "printf '%s none swap sw 0 0\n' '$path' >> /etc/fstab"
  fi

  # Gentler swap defaults for VPS (avoid thrashing on small RAM).
  vi_install_file /etc/sysctl.d/99-vps-init-swap.conf "$(cat <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
)" 0644
  vi_run sysctl --system >/dev/null

  vi_ok "swap ready: $path ($size_mb MB)"
}
