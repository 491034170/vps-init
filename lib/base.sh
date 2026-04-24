# lib/base.sh — install base packages every VPS should have.
# shellcheck shell=bash

VI_BASE_PACKAGES=(
  # shell + editing
  vim tmux htop
  # network
  curl wget dnsutils ca-certificates net-tools
  # transfer + build
  rsync unzip zip tar
  git build-essential
  # ops
  jq tree less file
  # locale + tz
  locales tzdata
  # security foundation
  openssl gnupg
  # python (often pulled in anyway; used by certbot, glances, etc.)
  python3 python3-pip
)

VI_WEB_PACKAGES=(
  nginx certbot python3-certbot-nginx
)

vi_cmd_base() {
  vi_detect_distro
  if [[ "$VI_DISTRO" == "unsupported" ]]; then
    vi_err "unsupported distribution"
    return 1
  fi

  local with_web=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-web) with_web=0; shift ;;
      *) shift ;;
    esac
  done

  vi_step "Base packages"
  vi_run apt-get update
  vi_apt_install "${VI_BASE_PACKAGES[@]}"

  # Enable zh_CN.UTF-8 + en_US.UTF-8 if not already, without forcing the
  # default locale (box operators may want en_US.UTF-8 as LANG).
  if command -v locale-gen >/dev/null 2>&1; then
    vi_run locale-gen en_US.UTF-8 zh_CN.UTF-8 || true
  fi

  if [[ $with_web -eq 1 ]]; then
    vi_step "Web packages (nginx + certbot)"
    vi_apt_install "${VI_WEB_PACKAGES[@]}"
    vi_run systemctl enable --now nginx
  fi

  vi_ok "base install complete"
}
