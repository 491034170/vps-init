# lib/apply.sh — profile-driven runner.
# shellcheck shell=bash

# A profile is a YAML file with a `modules:` list and per-module args.
# Example:
#   description: Minimal web VPS
#   modules:
#     - mirror:
#         provider: aliyun
#     - base: {}
#     - swap:
#         size: 2G
#     - firewall: {}
#     - fail2ban: {}
#     - timezone:
#         tz: Asia/Shanghai

_vi_resolve_profile() {
  local name="$1"
  local candidates=(
    "${VI_PROFILES_DIR_OVERRIDE:-}"
    "$VI_PROFILES_DIR_DEFAULT"
    "$VI_PROFILES_DIR_SYSTEM"
  )
  local dir
  for dir in "${candidates[@]}"; do
    [[ -z "$dir" ]] && continue
    if [[ -f "$dir/$name.yaml" ]]; then
      printf '%s/%s.yaml' "$dir" "$name"
      return 0
    fi
  done
  # Accept a direct file path too.
  if [[ -f "$name" ]]; then
    printf '%s' "$name"
    return 0
  fi
  return 1
}

vi_cmd_apply() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    vi_err "usage: vps-init apply <profile>"
    return 2
  fi

  local path
  if ! path=$(_vi_resolve_profile "$profile"); then
    vi_err "profile not found: $profile"
    vi_info "looked in: $VI_PROFILES_DIR_DEFAULT and $VI_PROFILES_DIR_SYSTEM"
    return 1
  fi

  vi_step "Profile: $(basename "$path" .yaml)"
  local desc
  desc=$(grep -m1 '^description:' "$path" | sed 's/^description:[[:space:]]*//' | sed 's/^"\|"$//g')
  [[ -n "$desc" ]] && vi_info "$desc"

  # Parse module entries. Each `- <name>:` at the top of `modules:` starts a
  # new step; nested 2-space keys are args. We gather them into newline-
  # separated "name|key=value|key=value" records.
  local records
  records=$(awk '
    BEGIN { in_modules = 0; current = "" }
    /^modules:/ { in_modules = 1; next }
    !in_modules { next }
    /^[^[:space:]]/ { in_modules = 0; next }
    /^[[:space:]]*-[[:space:]]+[A-Za-z][A-Za-z0-9_-]*:/ {
      if (current != "") print current
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      sub(/:[[:space:]]*.*$/, "")
      current = $0
      next
    }
    /^[[:space:]]+[A-Za-z][A-Za-z0-9_-]*:/ {
      if (current == "") next
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/:[[:space:]]*/, "=", line)
      gsub(/"/, "", line)
      current = current "|" line
    }
    END { if (current != "") print current }
  ' "$path")

  if [[ -z "$records" ]]; then
    vi_err "profile has no modules: $path"
    return 1
  fi

  local record
  while IFS= read -r record; do
    local name="${record%%|*}"
    local args=""
    [[ "$record" == *"|"* ]] && args="${record#*|}"
    _vi_run_module "$name" "$args"
  done <<< "$records"

  vi_ok "profile applied: $(basename "$path" .yaml)"
}

# Invoke the right vi_cmd_<name> with args resolved from a key=value string.
_vi_run_module() {
  local name="$1" args_str="$2"

  # Translate args string -> positional arguments per module.
  local -a argv=()
  case "$name" in
    mirror)
      local provider=""
      if [[ "$args_str" == *"provider="* ]]; then
        provider=$(printf '%s\n' "$args_str" | tr '|' '\n' | awk -F= '/^provider=/ {print $2; exit}')
      fi
      [[ -n "$provider" ]] && argv=("$provider")
      ;;
    swap)
      local size=""
      [[ "$args_str" == *"size="* ]] && size=$(printf '%s\n' "$args_str" | tr '|' '\n' | awk -F= '/^size=/ {print $2; exit}')
      [[ -n "$size" ]] && argv=("$size")
      ;;
    timezone)
      local tz=""
      [[ "$args_str" == *"tz="* ]] && tz=$(printf '%s\n' "$args_str" | tr '|' '\n' | awk -F= '/^tz=/ {print $2; exit}')
      [[ -n "$tz" ]] && argv=("$tz")
      ;;
    node)
      local version=""
      [[ "$args_str" == *"version="* ]] && version=$(printf '%s\n' "$args_str" | tr '|' '\n' | awk -F= '/^version=/ {print $2; exit}')
      [[ -n "$version" ]] && argv=("$version")
      ;;
    base)
      if [[ "$args_str" == *"web=false"* ]]; then argv=("--no-web"); fi
      ;;
  esac

  # Source module and call.
  case "$name" in
    mirror|base|swap|timezone|firewall|fail2ban|node|docker)
      # shellcheck source=/dev/null
      source "$VI_LIB/$name.sh"
      "vi_cmd_$name" "${argv[@]}"
      ;;
    ssh-hardening|ssh)
      source "$VI_LIB/ssh.sh"
      vi_cmd_ssh
      ;;
    *)
      vi_warn "unknown module in profile: $name (skipped)"
      ;;
  esac
}
