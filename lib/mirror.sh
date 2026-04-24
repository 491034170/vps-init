# lib/mirror.sh — swap apt sources to a China mirror.
# shellcheck shell=bash

# Known-good mirror hosts. Structure: name -> host.
declare -A VI_MIRRORS=(
  [aliyun]="mirrors.aliyun.com"
  [tuna]="mirrors.tuna.tsinghua.edu.cn"
  [ustc]="mirrors.ustc.edu.cn"
  [163]="mirrors.163.com"
  [huaweicloud]="mirrors.huaweicloud.com"
)

# Ubuntu sources.list (legacy format). Jammy and older.
_vi_ubuntu_sources_legacy() {
  local host="$1" codename="$2"
  cat <<EOF
# Managed by vps-init — swapped to $host
deb https://$host/ubuntu/ $codename main restricted universe multiverse
deb https://$host/ubuntu/ $codename-updates main restricted universe multiverse
deb https://$host/ubuntu/ $codename-backports main restricted universe multiverse
deb https://$host/ubuntu/ $codename-security main restricted universe multiverse
EOF
}

# Ubuntu 24.04 (noble) uses the deb822 format at /etc/apt/sources.list.d/ubuntu.sources.
_vi_ubuntu_sources_deb822() {
  local host="$1" codename="$2"
  cat <<EOF
Types: deb
URIs: https://$host/ubuntu/
Suites: $codename $codename-updates $codename-backports $codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

_vi_debian_sources() {
  local host="$1" codename="$2"
  cat <<EOF
# Managed by vps-init — swapped to $host
deb https://$host/debian/ $codename main contrib non-free non-free-firmware
deb https://$host/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://$host/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://$host/debian-security/ $codename-security main contrib non-free non-free-firmware
EOF
}

vi_cmd_mirror() {
  local target="${1:-aliyun}"
  local host="${VI_MIRRORS[$target]:-}"
  if [[ -z "$host" ]]; then
    vi_err "unknown mirror: $target (options: ${!VI_MIRRORS[*]})"
    return 2
  fi

  vi_detect_distro
  if [[ "$VI_DISTRO" == "unsupported" ]]; then
    vi_err "unsupported distribution (need Ubuntu or Debian)"
    return 1
  fi
  if [[ -z "$VI_CODENAME" ]]; then
    vi_err "could not detect distro codename"
    return 1
  fi

  vi_step "Switching apt sources to $target ($host)"
  vi_info "distro: $VI_DISTRO $VI_CODENAME"

  local content
  if [[ "$VI_DISTRO" == "ubuntu" ]]; then
    # 24.04+ uses deb822 at /etc/apt/sources.list.d/ubuntu.sources; older uses
    # /etc/apt/sources.list. Detect by presence of the deb822 file.
    if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
      content="$(_vi_ubuntu_sources_deb822 "$host" "$VI_CODENAME")"
      vi_install_file /etc/apt/sources.list.d/ubuntu.sources "$content" 0644
      # Neutralize the old-format file so it doesn't duplicate (safe: backed up).
      if [[ -s /etc/apt/sources.list ]]; then
        vi_backup_file /etc/apt/sources.list
        vi_run bash -c ': > /etc/apt/sources.list'
      fi
    else
      content="$(_vi_ubuntu_sources_legacy "$host" "$VI_CODENAME")"
      vi_install_file /etc/apt/sources.list "$content" 0644
    fi
  else
    content="$(_vi_debian_sources "$host" "$VI_CODENAME")"
    vi_install_file /etc/apt/sources.list "$content" 0644
  fi

  vi_step "apt update"
  vi_run apt-get update
  vi_ok "mirror switched to $target"
}
