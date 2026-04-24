# lib/common.sh — shared helpers.
# shellcheck shell=bash

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  VI_C_RESET=$'\033[0m' VI_C_BOLD=$'\033[1m' VI_C_DIM=$'\033[2m'
  VI_C_RED=$'\033[31m' VI_C_GREEN=$'\033[32m' VI_C_YELLOW=$'\033[33m'
  VI_C_CYAN=$'\033[36m'
else
  VI_C_RESET="" VI_C_BOLD="" VI_C_DIM="" VI_C_RED="" VI_C_GREEN="" VI_C_YELLOW="" VI_C_CYAN=""
fi

vi_step() { printf '%s==>%s %s\n' "$VI_C_CYAN$VI_C_BOLD" "$VI_C_RESET" "$*" >&2; }
vi_info() { printf '    %s\n' "$*" >&2; }
vi_warn() { printf '%swarn:%s %s\n' "$VI_C_YELLOW" "$VI_C_RESET" "$*" >&2; }
vi_err()  { printf '%serror:%s %s\n' "$VI_C_RED" "$VI_C_RESET" "$*" >&2; }
vi_ok()   { printf '%s✓%s %s\n' "$VI_C_GREEN" "$VI_C_RESET" "$*" >&2; }

vi_run() {
  if [[ "${VI_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$VI_C_DIM" "$VI_C_RESET" "$*" >&2
    return 0
  fi
  "$@"
}

vi_confirm() {
  local prompt="${1:-Continue?}"
  [[ "${VI_DRY_RUN:-0}" == "1" ]] && return 0
  [[ "${VI_ASSUME_YES:-0}" == "1" ]] && return 0
  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Detect distribution; export VI_DISTRO in {ubuntu, debian, unsupported}
# and VI_CODENAME (e.g. jammy, bookworm).
vi_detect_distro() {
  VI_DISTRO="unsupported"
  VI_CODENAME=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu) VI_DISTRO="ubuntu"; VI_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
      debian) VI_DISTRO="debian"; VI_CODENAME="${VERSION_CODENAME:-}" ;;
      *)      VI_DISTRO="unsupported" ;;
    esac
  fi
  export VI_DISTRO VI_CODENAME
}

# Back up a file once (to path.bak.YYYYmmddHHMMSS) before first edit.
vi_backup_file() {
  local f="$1"
  [[ ! -f "$f" ]] && return 0
  local bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
  if ! ls "${f}.bak."* >/dev/null 2>&1; then
    vi_run cp -a "$f" "$bak"
    vi_info "backup -> $bak"
  fi
}

# Ensure a `key = value` style line is present exactly once in a config file.
# Matches by key (anchored). Appends if missing.
vi_set_conf() {
  local file="$1" key="$2" value="$3" sep="${4:- }"
  vi_backup_file "$file"
  if grep -qE "^[[:space:]]*#?[[:space:]]*${key}([[:space:]]|${sep})" "$file" 2>/dev/null; then
    vi_run sed -i "s|^[[:space:]]*#\?[[:space:]]*${key}[[:space:]]*${sep}.*|${key}${sep}${value}|" "$file"
  else
    vi_run bash -c "printf '%s%s%s\n' '${key}' '${sep}' '${value}' >> '${file}'"
  fi
}

# Write a file if contents differ.
vi_install_file() {
  local dest="$1" content="$2" mode="${3:-0644}"
  if [[ -f "$dest" ]] && printf '%s' "$content" | cmp -s - "$dest"; then
    vi_info "unchanged: $dest"
    return 0
  fi
  vi_backup_file "$dest"
  if [[ "${VI_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s would write %s\n' "$VI_C_DIM" "$VI_C_RESET" "$dest" >&2
    return 0
  fi
  printf '%s' "$content" > "$dest"
  chmod "$mode" "$dest"
  vi_ok "wrote: $dest"
}

# Install an apt package only if not present. Batchable.
vi_apt_install() {
  local missing=()
  local p
  for p in "$@"; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
      missing+=("$p")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    vi_info "apt: already installed: $*"
    return 0
  fi
  vi_info "apt install: ${missing[*]}"
  vi_run apt-get install -y --no-install-recommends "${missing[@]}"
}
