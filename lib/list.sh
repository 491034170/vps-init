# lib/list.sh — list profiles and modules.
# shellcheck shell=bash

vi_cmd_list() {
  local dirs=()
  [[ -n "${VI_PROFILES_DIR_OVERRIDE:-}" ]] && dirs+=("$VI_PROFILES_DIR_OVERRIDE")
  dirs+=("$VI_PROFILES_DIR_DEFAULT" "$VI_PROFILES_DIR_SYSTEM")

  vi_step "Built-in profiles"
  local f
  for d in "${dirs[@]}"; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*.yaml; do
      [[ -f "$f" ]] || continue
      local name
      name=$(basename "$f" .yaml)
      local desc
      desc=$(grep -m1 '^description:' "$f" 2>/dev/null | sed 's/^description:[[:space:]]*//' | sed 's/^"\|"$//g' || echo "")
      printf '  %-12s %s\n' "$name" "$desc"
    done
  done

  vi_step "Modules"
  cat <<'EOF'
  mirror [aliyun|tuna|ustc|163|huaweicloud]
  base [--no-web]
  swap <size>        e.g. 2G, 4G
  timezone <tz>      e.g. Asia/Shanghai
  firewall           UFW with SSH + 80/443
  fail2ban           tuned sshd jail
  ssh-hardening      key-only, no root password
  user <name>        Create operator user + sudo + SSH keys
                       --github <handle>   pull keys from github.com/<handle>.keys
                       --key-file <path>   read public key(s) from a file
                       --copy-key-from <u> inherit keys from an existing user (e.g. root)
                       --sudo-nopasswd     skip password prompt for sudo
  node [lts|20|18]   via nvm + pnpm + pm2
  docker             Docker CE from upstream repo
  postgres           PostgreSQL from PGDG repo, small-VPS-tuned conf.d
                       --version 16         pin major version (default 16)
                       --create-user app    create login role + write pw file
                       --create-db myapp    create database (owner = create-user if set)
  mysql              MySQL 8 (or MariaDB with --mariadb), small-VPS-tuned
                       --mariadb            install MariaDB instead of MySQL
                       --create-user app    create user + write pw file
                       --create-db myapp    create database + grant to create-user
  doctor             summary of current state
EOF
}
